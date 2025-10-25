# Event Subscription

znvim supports subscribing to and handling various Neovim events for real-time editor integration.

## Event Overview

Neovim supports multiple event types:
- **Buffer Events**: Buffer change events
- **UI Events**: User interface update events
- **Autocommand Events**: Automatic command events
- **Custom Events**: User-defined events

## Current Event Handling Pattern

### Approach 1: Polling (Current Implementation)

znvim currently uses a synchronous model. You can poll for notifications:

```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    var client = try znvim.Client.init(allocator, .{ .spawn_process = true });
    defer {
        client.disconnect();
        client.deinit();
    }
    try client.connect();

    const msgpack = znvim.msgpack;

    // Subscribe to buffer change events
    const buf_result = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf_result, allocator);
    
    const buf = switch (buf_result) {
        .int => buf_result.int,
        .uint => @as(i64, @intCast(buf_result.uint)),
        else => return error.UnexpectedType,
    };

    // Create options map
    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    
    const send_buffer_val = msgpack.boolean(true);
    try opts.map.put("send_buffer", send_buffer_val);

    const attach_params = [_]msgpack.Value{
        msgpack.int(buf),
        msgpack.boolean(true),
        opts,
    };
    
    const attach_result = try client.request("nvim_buf_attach", &attach_params);
    defer msgpack.free(attach_result, allocator);
    
    std.debug.print("Subscribed to buffer events\n", .{});
}
```

## Buffer Events

### Subscribe to Buffer Changes

```zig
const msgpack = znvim.msgpack;

// Get buffer handle
const buf_result = try client.request("nvim_get_current_buf", &.{});
defer msgpack.free(buf_result, allocator);

const buf = switch (buf_result) {
    .int => buf_result.int,
    .uint => @as(i64, @intCast(buf_result.uint)),
    else => return error.UnexpectedType,
};

// Subscription options
var opts = msgpack.Value.mapPayload(allocator);
defer opts.free(allocator);

// Enable various events
try opts.map.put("on_lines", msgpack.boolean(true));
try opts.map.put("on_bytes", msgpack.boolean(true));
try opts.map.put("on_changedtick", msgpack.boolean(true));

// Attach to buffer
const params = [_]msgpack.Value{
    msgpack.int(buf),
    msgpack.boolean(false),  // send_buffer
    opts,
};

const result = try client.request("nvim_buf_attach", &params);
defer msgpack.free(result, allocator);

std.debug.print("Buffer events subscribed\n", .{});
```

### Event Types

Buffer events include:
- `nvim_buf_lines_event`: Line change events
- `nvim_buf_changedtick_event`: Change tick events
- `nvim_buf_detach_event`: Detach events

## Autocommand Events

### Create Autocommand

```zig
const msgpack = znvim.msgpack;

// Create autocommand to monitor file saves
const event_str = try msgpack.string(allocator, "BufWritePost");
defer msgpack.free(event_str, allocator);

const pattern_str = try msgpack.string(allocator, "*.zig");
defer msgpack.free(pattern_str, allocator);

const command_str = try msgpack.string(allocator, "echo 'Zig file saved!'");
defer msgpack.free(command_str, allocator);

// Create opts map
var opts = msgpack.Value.mapPayload(allocator);
defer opts.free(allocator);

try opts.map.put("pattern", pattern_str);
try opts.map.put("command", command_str);

const params = [_]msgpack.Value{
    event_str,
    opts,
};

const result = try client.request("nvim_create_autocmd", &params);
defer msgpack.free(result, allocator);

std.debug.print("Autocommand created\n", .{});
```

## Using nvim_exec_lua for Event Handling

A practical approach is using Lua to handle events with RPC callbacks:

```zig
const msgpack = znvim.msgpack;

// Execute Lua code to set up event handler
const lua_code = 
    \\vim.api.nvim_create_autocmd("BufWritePost", {
    \\  pattern = "*.zig",
    \\  callback = function()
    \\    -- Can call RPC functions to notify client here
    \\    print("Zig file saved!")
    \\  end,
    \\})
;

const code = try msgpack.string(allocator, lua_code);
defer msgpack.free(code, allocator);

const empty_args = [_]msgpack.Value{};
const args_array = try msgpack.array(allocator, &empty_args);
defer msgpack.free(args_array, allocator);

const params = [_]msgpack.Value{ code, args_array };
const result = try client.request("nvim_exec_lua", &params);
defer msgpack.free(result, allocator);

std.debug.print("Lua event handler set up\n", .{});
```

## Future Features

znvim plans to add full async event support in future versions:

```zig
// Future API design (planned)
var client = try znvim.Client.init(allocator, .{ .spawn_process = true });
defer client.deinit();

// Register event handlers
try client.onNotification("nvim_buf_lines_event", handleBufferLines);
try client.onNotification("nvim_buf_changedtick_event", handleChangeTick);

// Start event loop
try client.eventLoop();

// Handler functions
fn handleBufferLines(notification: znvim.Notification) void {
    // Handle buffer line changes
}

fn handleChangeTick(notification: znvim.Notification) void {
    // Handle change tick updates
}
```

## Best Practices

### 1. Cleanup Subscriptions

Remember to unsubscribe when done:

```zig
// Subscribe
const attach_result = try client.request("nvim_buf_attach", &params);
defer msgpack.free(attach_result, allocator);

// ... use ...

// Cleanup
const buf_param = [_]msgpack.Value{ msgpack.int(buf) };
const detach_result = try client.request("nvim_buf_detach", &buf_param);
defer msgpack.free(detach_result, allocator);
```

### 2. Error Handling

```zig
const attach_result = client.request("nvim_buf_attach", &params) catch |err| {
    std.debug.print("Subscription failed: {}\n", .{err});
    return err;
};
defer msgpack.free(attach_result, allocator);
```

## References

- [Neovim API Docs](https://neovim.io/doc/user/api.html)
- [Neovim UI Protocol](https://neovim.io/doc/user/ui.html)
- [Autocommand Events](https://neovim.io/doc/user/autocmd.html#autocmd-events)

## Next Steps

- [Advanced Usage](04-advanced.md) - Advanced features and tips
- [Common Patterns](06-patterns.md) - Best practices

---

[Back to Index](README.md) | [Previous: API Usage](02-api-usage.md) | [Next: Advanced](04-advanced.md)

