# Advanced Usage

This document covers advanced features, best practices, and performance optimization tips for znvim.

## Thread Safety

znvim 0.1.0+ provides full thread-safety support.

### Independent Client Instances (Recommended)

Each thread creates its own Client instance:

```zig
const std = @import("std");
const znvim = @import("znvim");

fn workerThread(allocator: std.mem.Allocator, thread_id: usize) !void {
    // Independent client per thread
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
    });
    defer {
        client.disconnect();
        client.deinit();
    }
    
    try client.connect();
    
    const msgpack = znvim.msgpack;
    const expr = try std.fmt.allocPrint(allocator, "{} * 2", .{thread_id});
    defer allocator.free(expr);
    
    const expr_val = try msgpack.string(allocator, expr);
    defer msgpack.free(expr_val, allocator);
    
    const params = [_]msgpack.Value{expr_val};
    const result = try client.request("nvim_eval", &params);
    defer msgpack.free(result, allocator);
    
    std.debug.print("Thread {}: result = {}\n", .{ thread_id, result });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var threads: [4]std.Thread = undefined;
    
    // Spawn multiple threads
    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, workerThread, .{ allocator, i });
    }
    
    // Wait for all threads
    for (threads) |thread| {
        thread.join();
    }
}
```

See: `THREAD_SAFETY.md` for details.

## Memory Management Best Practices

### 1. Use Arena Allocator for Batch Operations

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();

const msgpack = znvim.msgpack;

// Create many MessagePack values
var params = std.ArrayList(msgpack.Value).init(allocator);

var i: usize = 0;
while (i < 1000) : (i += 1) {
    const line = try std.fmt.allocPrint(allocator, "Line {}", .{i});
    const line_val = try msgpack.string(allocator, line);
    try params.append(line_val);
}

const lines_array = try msgpack.array(allocator, params.items);

// Use lines_array...

// arena.deinit() frees everything at once
```

### 2. MessagePack Ownership Rules

**Key Rule**: `array()` and `map` operations take ownership of elements.

```zig
// ✅ Correct - array takes ownership
const elem = try msgpack.string(allocator, "text");
const arr = try msgpack.array(allocator, &.{elem});
defer msgpack.free(arr, allocator);  // Only free array

// ❌ Wrong - double free!
const elem = try msgpack.string(allocator, "text");
defer msgpack.free(elem, allocator);  // ERROR!
const arr = try msgpack.array(allocator, &.{elem});
defer msgpack.free(arr, allocator);  // Will free elem again → crash

// ✅ Correct - nested maps
var inner = msgpack.Value.mapPayload(allocator);
var outer = msgpack.Value.mapPayload(allocator);
try outer.map.put("key", inner);  // inner ownership transferred
defer outer.free(allocator);  // Only free outer
```

## Extmarks

Extmarks allow marking positions in buffers:

```zig
const msgpack = znvim.msgpack;

// Get current buffer
const buf_result = try client.request("nvim_get_current_buf", &.{});
defer msgpack.free(buf_result, allocator);

const buf = switch (buf_result) {
    .int => buf_result.int,
    .uint => @as(i64, @intCast(buf_result.uint)),
    else => return error.UnexpectedType,
};

// Create namespace
const ns_name = try msgpack.string(allocator, "my_namespace");
defer msgpack.free(ns_name, allocator);

const ns_params = [_]msgpack.Value{ns_name};
const ns_result = try client.request("nvim_create_namespace", &ns_params);
defer msgpack.free(ns_result, allocator);

const ns_id = try msgpack.expectI64(ns_result);

// Set extmark
var opts = msgpack.Value.mapPayload(allocator);
defer opts.free(allocator);

const hl_group = try msgpack.string(allocator, "Error");
try opts.map.put("hl_group", hl_group);

const mark_params = [_]msgpack.Value{
    msgpack.int(buf),
    msgpack.int(ns_id),
    msgpack.int(0),      // line
    msgpack.int(0),      // col
    opts,
};

const mark_result = try client.request("nvim_buf_set_extmark", &mark_params);
defer msgpack.free(mark_result, allocator);

const mark_id = try msgpack.expectI64(mark_result);
std.debug.print("Extmark ID: {}\n", .{mark_id});
```

## Virtual Text

Display text without modifying the buffer:

```zig
const msgpack = znvim.msgpack;

// Get current buffer and namespace
const buf_result = try client.request("nvim_get_current_buf", &.{});
defer msgpack.free(buf_result, allocator);

const buf = switch (buf_result) {
    .int => buf_result.int,
    .uint => @as(i64, @intCast(buf_result.uint)),
    else => return error.UnexpectedType,
};

const ns_name = try msgpack.string(allocator, "virtual_text");
defer msgpack.free(ns_name, allocator);

const ns_params = [_]msgpack.Value{ns_name};
const ns_result = try client.request("nvim_create_namespace", &ns_params);
defer msgpack.free(ns_result, allocator);

const ns_id = try msgpack.expectI64(ns_result);

// Create virtual text
const virt_text_str = try msgpack.string(allocator, "← virtual text");
const virt_hl = try msgpack.string(allocator, "Comment");

const virt_chunk = [_]msgpack.Value{ virt_text_str, virt_hl };
const chunk_array = try msgpack.array(allocator, &virt_chunk);

const virt_text_chunks = [_]msgpack.Value{chunk_array};
const chunks_array = try msgpack.array(allocator, &virt_text_chunks);
defer msgpack.free(chunks_array, allocator);

// Set options
var opts = msgpack.Value.mapPayload(allocator);
defer opts.free(allocator);

try opts.map.put("virt_text", chunks_array);
try opts.map.put("virt_text_pos", try msgpack.string(allocator, "eol"));

// Set extmark with virtual text
const params = [_]msgpack.Value{
    msgpack.int(buf),
    msgpack.int(ns_id),
    msgpack.int(0),  // line
    msgpack.int(0),  // col
    opts,
};

const result = try client.request("nvim_buf_set_extmark", &params);
defer msgpack.free(result, allocator);

std.debug.print("Virtual text added\n", .{});
```

## Performance Analysis

### Measure API Call Latency

```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn benchmarkApi(allocator: std.mem.Allocator) !void {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .skip_api_info = true,  // Skip API info for faster startup
    });
    defer client.deinit();
    try client.connect();

    const msgpack = znvim.msgpack;
    const iterations = 100;
    
    var timer = try std.time.Timer.start();
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const result = try client.request("nvim_get_mode", &.{});
        defer msgpack.free(result, allocator);
    }
    
    const elapsed_ns = timer.read();
    const avg_latency_us = elapsed_ns / (iterations * 1000);
    
    std.debug.print("Average latency: {} μs\n", .{avg_latency_us});
    std.debug.print("Throughput: {d:.2} req/s\n", .{
        @as(f64, iterations) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0)
    });
}
```

### Batch vs Individual Requests

```zig
// Inefficient: multiple individual requests
var total: i64 = 0;
for (expressions) |expr| {
    const result = try client.request("nvim_eval", &[_]msgpack.Value{expr});
    defer msgpack.free(result, allocator);
    total += try msgpack.expectI64(result);
}

// Efficient: use Lua for batch processing
const lua_code = 
    \\local sum = 0
    \\for _, expr in ipairs({...}) do
    \\  sum = sum + vim.fn.eval(expr)
    \\end
    \\return sum
;
const result = try client.request("nvim_exec_lua", &params);
// All computation in one RPC call
```

## Debugging Tips

### 1. Print MessagePack Values

```zig
fn debugPrintValue(value: msgpack.Value, indent: usize) void {
    const prefix = "  " ** indent;
    
    switch (value) {
        .nil => std.debug.print("{s}nil\n", .{prefix}),
        .bool => |b| std.debug.print("{s}bool: {}\n", .{ prefix, b }),
        .int => |i| std.debug.print("{s}int: {}\n", .{ prefix, i }),
        .str => |s| std.debug.print("{s}string: {s}\n", .{ prefix, s.value() }),
        .arr => |a| {
            std.debug.print("{s}array[{}]:\n", .{ prefix, a.len });
            for (a) |item| {
                debugPrintValue(item, indent + 1);
            }
        },
        .map => |m| {
            std.debug.print("{s}map({}):\n", .{ prefix, m.count() });
            var it = m.iterator();
            while (it.next()) |entry| {
                std.debug.print("{s}  {s}:\n", .{ prefix, entry.key_ptr.* });
                debugPrintValue(entry.value_ptr.*, indent + 2);
            }
        },
        else => std.debug.print("{s}other: {s}\n", .{ prefix, @tagName(value) }),
    }
}
```

## Performance Optimization Checklist

- ✅ Use `skip_api_info = true` to skip unnecessary metadata fetch
- ✅ Use `notify` instead of `request` for operations that don't need responses
- ✅ Use Lua scripts for batch operations instead of multiple RPC calls
- ✅ Reuse MessagePack values instead of recreating
- ✅ Use Arena Allocator for bulk allocation/deallocation
- ✅ Prefer Unix Socket (Unix) or Named Pipe (Windows) for local connections
- ✅ Adjust timeout values appropriately
- ✅ Use independent Client instances in multi-threaded scenarios

## Troubleshooting

### Common Issues

**Q: Request timeout**
```zig
// Increase timeout
var client = try znvim.Client.init(allocator, .{
    .spawn_process = true,
    .timeout_ms = 30000,  // 30 seconds
});
```

**Q: Memory leak**
```zig
// Use GPA to detect leaks
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer {
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("WARNING: Memory leak detected!\n", .{});
    }
}
```

**Q: MessagePack type error**
```zig
// Use as* functions instead of expect*
if (msgpack.asString(result)) |str| {
    // Handle string
} else if (msgpack.asI64(result)) |num| {
    // Handle number
} else {
    std.debug.print("Unknown type: {s}\n", .{@tagName(result)});
}
```

## References

- [Neovim API](https://neovim.io/doc/user/api.html)
- [MessagePack Spec](https://msgpack.org/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)

## Next Steps

- [Code Examples](05-examples.md) - Real-world examples
- [Common Patterns](06-patterns.md) - Best practices

---

[Back to Index](README.md) | [Previous: Events](03-events.md) | [Next: Examples](05-examples.md)

