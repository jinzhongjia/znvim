# Quick Start

znvim is a lightweight, high-performance Neovim RPC client library written in Zig.

## Installation

Add znvim to your `build.zig.zon` file:

```zig
.dependencies = .{
    .znvim = .{
        .url = "https://github.com/jinzhongjia/znvim/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...", // zig will auto-generate
    },
},
```

In your `build.zig`:

```zig
const znvim = b.dependency("znvim", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("znvim", znvim.module("znvim"));
```

## First Program

```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create and connect to embedded Neovim
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
    });
    defer {
        client.disconnect();
        client.deinit();
    }

    try client.connect();

    // Execute a simple command
    const msgpack = znvim.msgpack;
    const cmd = try msgpack.string(allocator, "echo 'Hello from znvim!'");
    defer msgpack.free(cmd, allocator);

    const params = [_]msgpack.Value{cmd};
    const result = try client.request("nvim_command", &params);
    defer msgpack.free(result, allocator);

    std.debug.print("Command executed successfully!\n", .{});
}
```

## Run

```bash
zig build run
```

## Next Steps

- [Connections](01-connections.md) - Learn different connection methods
- [API Usage](02-api-usage.md) - Deep dive into API calls
- [Event Subscription](03-events.md) - Handle Neovim events
- [Advanced Usage](04-advanced.md) - Advanced features and tips

## Minimal Example

If you just want to test quickly, here's the minimal runnable code:

```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    var client = try znvim.Client.init(allocator, .{ .spawn_process = true });
    defer client.deinit();
    
    try client.connect();
    
    const result = try client.request("nvim_get_mode", &.{});
    defer znvim.msgpack.free(result, allocator);
    
    std.debug.print("Neovim mode: {}\n", .{result});
}
```

## FAQ

### Q: How to connect to a running Neovim instance?

Use Unix socket or TCP:

```zig
// Unix Socket
var client = try znvim.Client.init(allocator, .{
    .socket_path = "/tmp/nvim.sock",
});

// TCP
var client = try znvim.Client.init(allocator, .{
    .tcp_address = "127.0.0.1",
    .tcp_port = 6666,
});
```

Start Neovim with listening:
```bash
# Unix Socket
nvim --listen /tmp/nvim.sock

# TCP
nvim --listen 127.0.0.1:6666
```

### Q: Which platforms are supported?

- ✅ Linux (Unix Socket, TCP, Stdio, ChildProcess)
- ✅ macOS (Unix Socket, TCP, Stdio, ChildProcess)
- ✅ Windows (Named Pipe, TCP, Stdio, ChildProcess)

### Q: What Neovim version is required?

Neovim 0.9.0 or higher is recommended.

---

[Back to Index](README.md)
