# API Usage Guide

This document explains how to call various Neovim APIs using znvim.

## Basic Concepts

### Request vs Notification

- **Request**: Send request and wait for response
- **Notification**: Send notification without waiting (fire-and-forget)

```zig
// Request - wait for response
const result = try client.request("nvim_get_mode", &.{});
defer msgpack.free(result, allocator);

// Notification - no waiting
try client.notify("nvim_command", &params);
```

## Calling APIs

### 1. API Calls Without Parameters

```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var client = try znvim.Client.init(allocator, .{ .spawn_process = true });
    defer client.deinit();
    try client.connect();

    const msgpack = znvim.msgpack;
    
    // Get current mode
    const mode_result = try client.request("nvim_get_mode", &.{});
    defer msgpack.free(mode_result, allocator);
    
    // Get current buffer
    const buf_result = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf_result, allocator);
    
    const buf_handle = switch (buf_result) {
        .int => buf_result.int,
        .uint => @as(i64, @intCast(buf_result.uint)),
        else => return error.UnexpectedType,
    };
    
    std.debug.print("Current buffer handle: {}\n", .{buf_handle});
}
```

### 2. API Calls With Parameters

```zig
const msgpack = znvim.msgpack;

// Evaluate expression
const expr = try msgpack.string(allocator, "2 + 3 * 4");
defer msgpack.free(expr, allocator);

const params = [_]msgpack.Value{expr};
const result = try client.request("nvim_eval", &params);
defer msgpack.free(result, allocator);

const value = switch (result) {
    .int => result.int,
    .uint => @as(i64, @intCast(result.uint)),
    else => return error.UnexpectedType,
};

std.debug.print("Result: {}\n", .{value}); // Output: 14
```

### 3. Complex Parameters

```zig
const msgpack = znvim.msgpack;

// Get buffer lines
const buf_handle = msgpack.int(1);  // Buffer handle
const start_line = msgpack.int(0);  // Start line (0-based)
const end_line = msgpack.int(10);   // End line (exclusive)
const strict = msgpack.boolean(false);

const params = [_]msgpack.Value{ buf_handle, start_line, end_line, strict };
const result = try client.request("nvim_buf_get_lines", &params);
defer msgpack.free(result, allocator);

// Parse result (array of strings)
const lines = try msgpack.expectArray(result);
for (lines, 0..) |line, i| {
    const line_str = try msgpack.expectString(line);
    std.debug.print("Line {}: {s}\n", .{ i, line_str });
}
```

## Common API Examples

### Buffer Operations

#### Read Buffer Content

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

// Read all lines
const params = [_]msgpack.Value{
    msgpack.int(buf),
    msgpack.int(0),
    msgpack.int(-1),
    msgpack.boolean(false),
};

const lines_result = try client.request("nvim_buf_get_lines", &params);
defer msgpack.free(lines_result, allocator);

const lines = try msgpack.expectArray(lines_result);
std.debug.print("Buffer has {} lines\n", .{lines.len});
```

#### Write Buffer Content

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

// Create line array
const line1 = try msgpack.string(allocator, "First line");
const line2 = try msgpack.string(allocator, "Second line");
const line3 = try msgpack.string(allocator, "Third line");

const lines = [_]msgpack.Value{ line1, line2, line3 };
const lines_array = try msgpack.array(allocator, &lines);
defer msgpack.free(lines_array, allocator);

// Set lines (replace lines 0-2)
const params = [_]msgpack.Value{
    msgpack.int(buf),
    msgpack.int(0),
    msgpack.int(3),
    msgpack.boolean(false),
    lines_array,
};

const result = try client.request("nvim_buf_set_lines", &params);
defer msgpack.free(result, allocator);

std.debug.print("Buffer content updated\n", .{});
```

### Window Operations

```zig
const msgpack = znvim.msgpack;

// Get current window
const win_result = try client.request("nvim_get_current_win", &.{});
defer msgpack.free(win_result, allocator);

const win = switch (win_result) {
    .int => win_result.int,
    .uint => @as(i64, @intCast(win_result.uint)),
    else => return error.UnexpectedType,
};

// Set cursor position [row, col] (1-based row, 0-based col)
const row = msgpack.int(10);
const col = msgpack.int(5);
const pos = [_]msgpack.Value{ row, col };
const pos_array = try msgpack.array(allocator, &pos);
defer msgpack.free(pos_array, allocator);

const cursor_params = [_]msgpack.Value{ msgpack.int(win), pos_array };
const cursor_result = try client.request("nvim_win_set_cursor", &cursor_params);
defer msgpack.free(cursor_result, allocator);
```

### Execute Commands and Expressions

```zig
const msgpack = znvim.msgpack;

// Execute Vim command
const cmd = try msgpack.string(allocator, "tabnew");
defer msgpack.free(cmd, allocator);

const cmd_params = [_]msgpack.Value{cmd};
try client.notify("nvim_command", &cmd_params);  // Use notify, no response needed

// Evaluate Vim expression
const expr = try msgpack.string(allocator, "line('.')");
defer msgpack.free(expr, allocator);

const eval_params = [_]msgpack.Value{expr};
const line_result = try client.request("nvim_eval", &eval_params);
defer msgpack.free(line_result, allocator);

const current_line = switch (line_result) {
    .int => line_result.int,
    .uint => @as(i64, @intCast(line_result.uint)),
    else => return error.UnexpectedType,
};

std.debug.print("Current line: {}\n", .{current_line});
```

## MessagePack Utility Functions

znvim provides convenient MessagePack construction functions:

### Basic Types

```zig
const msgpack = znvim.msgpack;

// Basic types
const nil_val = msgpack.nil();
const bool_val = msgpack.boolean(true);
const int_val = msgpack.int(42);
const uint_val = msgpack.uint(100);
const float_val = msgpack.float(3.14);

// String (requires allocator)
const str = try msgpack.string(allocator, "Hello");
defer msgpack.free(str, allocator);

// Binary data
const bin = try msgpack.binary(allocator, &[_]u8{ 0x01, 0x02, 0x03 });
defer msgpack.free(bin, allocator);
```

### Arrays

```zig
const msgpack = znvim.msgpack;

// Create array
const elem1 = try msgpack.string(allocator, "first");
const elem2 = try msgpack.string(allocator, "second");
const elem3 = msgpack.int(42);

const elements = [_]msgpack.Value{ elem1, elem2, elem3 };
const arr = try msgpack.array(allocator, &elements);
defer msgpack.free(arr, allocator);
// Note: array() takes ownership of elements, don't free them separately
```

### Maps/Objects

```zig
const msgpack = znvim.msgpack;

// Create map
var map = msgpack.Value.mapPayload(allocator);
defer map.free(allocator);

const key1 = try msgpack.string(allocator, "name");
const key2 = try msgpack.string(allocator, "age");

try map.map.put("name", key1);
try map.map.put("age", msgpack.int(30));
```

## Parsing Responses

### expect* Functions (Strict)

```zig
const msgpack = znvim.msgpack;

const result = try client.request("nvim_get_mode", &.{});
defer msgpack.free(result, allocator);

// Expect map, returns error otherwise
const mode_map = try msgpack.expectMap(result);

// Expect array
const arr = try msgpack.expectArray(some_result);

// Expect string
const str = try msgpack.expectString(some_result);

// Expect boolean
const bool_val = try msgpack.expectBool(some_result);

// Expect integer
const int_val = try msgpack.expectI64(some_result);
const uint_val = try msgpack.expectU64(some_result);
```

### as* Functions (Lenient)

```zig
const msgpack = znvim.msgpack;

const result = try client.request("some_api", &params);
defer msgpack.free(result, allocator);

// Try to get array, returns null on failure
if (msgpack.asArray(result)) |arr| {
    std.debug.print("Is array, length: {}\n", .{arr.len});
} else {
    std.debug.print("Not an array\n", .{});
}

// Try to get string
if (msgpack.asString(result)) |str| {
    std.debug.print("String: {s}\n", .{str});
}
```

## Performance Tips

### 1. Skip API Info Fetch

If you don't need API metadata:

```zig
var client = try znvim.Client.init(allocator, .{
    .spawn_process = true,
    .skip_api_info = true,  // Faster connection
});
```

### 2. Use Notification Instead of Request

If you don't need the response:

```zig
// Slow - waits for response
const result = try client.request("nvim_command", &params);
defer msgpack.free(result, allocator);

// Fast - doesn't wait
try client.notify("nvim_command", &params);
```

## Next Steps

- [Event Subscription](03-events.md) - Handle Neovim events
- [Advanced Usage](04-advanced.md) - Advanced features and tips

---

[Back to Index](README.md) | [Previous: Connections](01-connections.md) | [Next: Events](03-events.md)

