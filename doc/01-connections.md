# Connection Methods

znvim supports multiple ways to connect to Neovim for different use cases.

## Overview

| Method | Platform | Use Case | Performance |
|--------|----------|----------|-------------|
| **ChildProcess** | All | Embedded Neovim | ⭐⭐⭐⭐ |
| **Unix Socket** | Unix/Linux/macOS | Local connection | ⭐⭐⭐⭐⭐ |
| **Named Pipe** | Windows | Local connection | ⭐⭐⭐⭐⭐ |
| **TCP Socket** | All | Remote connection | ⭐⭐⭐⭐ |
| **Stdio** | All | Custom process | ⭐⭐⭐ |

## 1. ChildProcess - Embedded Neovim

The simplest way, automatically starts a Neovim process.

```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",  // Optional, default is "nvim"
        .timeout_ms = 5000,   // Optional, default is 5000
    });
    defer {
        client.disconnect();
        client.deinit();
    }
    
    try client.connect();
    
    // Now you can use the client
    const result = try client.request("nvim_get_mode", &.{});
    defer znvim.msgpack.free(result, allocator);
}
```

**Use Cases:**
- Development tools (IDE plugins, debuggers)
- Automated testing
- Scripts and utilities

**Pros:**
- ✅ Simple to use, no manual Neovim startup needed
- ✅ Cross-platform
- ✅ Automatic process lifecycle management

**Cons:**
- ❌ New process for each connection
- ❌ Cannot connect to existing Neovim instances

## 2. Unix Socket - Unix/Linux/macOS Local Connection

Unix domain socket, best performance for local connections.

**Start Neovim listening:**
```bash
nvim --listen /tmp/nvim.sock
```

**Connection code:**
```zig
var client = try znvim.Client.init(allocator, .{
    .socket_path = "/tmp/nvim.sock",
});
defer {
    client.disconnect();
    client.deinit();
}

try client.connect();
```

**Pros:**
- ✅ Best performance
- ✅ Secure (filesystem permissions)
- ✅ Low latency

**Cons:**
- ❌ Unix/Linux/macOS only

## 3. Named Pipe - Windows Local Connection

Preferred method for local connections on Windows.

**Start Neovim listening:**
```powershell
nvim --listen \\.\pipe\nvim-pipe
```

**Connection code:**
```zig
var client = try znvim.Client.init(allocator, .{
    .socket_path = "\\\\.\\pipe\\nvim-pipe",
});
defer {
    client.disconnect();
    client.deinit();
}

try client.connect();
```

**Pros:**
- ✅ Native Windows support
- ✅ Excellent performance
- ✅ Secure (ACL-based)

**Cons:**
- ❌ Windows only

## 4. TCP Socket - Remote Connection

Connect via TCP/IP network, supports remote access.

**Start Neovim listening:**
```bash
# Local connection
nvim --listen 127.0.0.1:6666

# Remote connection (use with caution!)
nvim --listen 0.0.0.0:6666
```

**Connection code:**
```zig
var client = try znvim.Client.init(allocator, .{
    .tcp_address = "127.0.0.1",
    .tcp_port = 6666,
});
defer {
    client.disconnect();
    client.deinit();
}

try client.connect();
```

**Remote connection example:**
```zig
// Connect to remote server
var client = try znvim.Client.init(allocator, .{
    .tcp_address = "192.168.1.100",
    .tcp_port = 6666,
    .timeout_ms = 10000,  // Longer timeout for remote
});
```

**Use Cases:**
- Remote editing
- Cross-machine collaboration
- Neovim in containers/VMs

**Pros:**
- ✅ Supports remote access
- ✅ Cross-platform
- ✅ Flexible

**Cons:**
- ❌ Lower performance than local
- ❌ Network configuration needed
- ❌ Security risks (needs additional protection)

**Security Recommendation:**

For remote access, use SSH tunnel:
```bash
# Create SSH tunnel on local machine
ssh -L 6666:localhost:6666 user@remote-host

# Then connect to local port
# Traffic goes through encrypted SSH tunnel
```

## Connection Options

```zig
pub const ConnectionOptions = struct {
    // Connection methods
    socket_path: ?[]const u8 = null,      // Unix socket or Named Pipe
    tcp_address: ?[]const u8 = null,      // TCP host address
    tcp_port: ?u16 = null,                // TCP port
    use_stdio: bool = false,              // Use stdin/stdout
    spawn_process: bool = false,          // Spawn child process
    
    // Child process options
    nvim_path: []const u8 = "nvim",       // Neovim executable path
    
    // General options
    timeout_ms: u32 = 5000,               // Timeout in milliseconds
    skip_api_info: bool = false,          // Skip API info fetch
};
```

## Best Practices

### 1. Choose the Right Method

- **Development tools/automation**: Use `ChildProcess`
- **Local integration**: Use `Unix Socket` (Unix/macOS) or `Named Pipe` (Windows)
- **Remote access**: Use `TCP Socket` + SSH tunnel
- **Testing**: Use `ChildProcess` or `Stdio`

### 2. Error Handling

```zig
const client = znvim.Client.init(allocator, .{
    .socket_path = "/tmp/nvim.sock",
}) catch |err| {
    std.debug.print("Init failed: {}\n", .{err});
    return err;
};

client.connect() catch |err| {
    std.debug.print("Connection failed: {}\n", .{err});
    return err;
};
```

### 3. Resource Cleanup

Always use `defer` to ensure resources are freed:

```zig
var client = try znvim.Client.init(allocator, .{ .spawn_process = true });
defer {
    client.disconnect();
    client.deinit();
}
```

---

[Back to Index](README.md) | [Next: API Usage](02-api-usage.md)
