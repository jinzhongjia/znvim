const std = @import("std");
const builtin = @import("builtin");
const znvim = @import("znvim");

/// Connection method types
pub const ConnectionMethod = enum {
    /// Unix Socket (Unix/Linux/macOS only)
    unix_socket,
    /// Windows Named Pipe (Windows only)
    windows_pipe,
    /// TCP network connection (cross-platform)
    tcp,
    /// Standard input/output (cross-platform)
    stdio,
    /// Auto-spawn subprocess (cross-platform)
    spawn,
};

/// Connection configuration
pub const ConnectionConfig = struct {
    /// Unix socket path (Unix/Linux/macOS)
    unix_socket_path: ?[]const u8 = null,
    /// Windows named pipe name (Windows)
    windows_pipe_name: ?[]const u8 = null,
    /// TCP address
    tcp_host: ?[]const u8 = null,
    /// TCP port
    tcp_port: ?u16 = null,
    /// Use stdio
    use_stdio: bool = false,
    /// Auto-spawn Neovim
    spawn_nvim: bool = false,
    /// Neovim executable path
    nvim_path: []const u8 = "nvim",
    /// Connection timeout (milliseconds)
    timeout_ms: u32 = 5000,
};

/// Smart connect: automatically choose the best connection method based on platform and environment
pub fn smartConnect(allocator: std.mem.Allocator) !znvim.Client {
    // 1. Try to get connection info from environment variable
    if (std.process.getEnvVarOwned(allocator, "NVIM_LISTEN_ADDRESS")) |address| {
        defer allocator.free(address);

        // Determine address type
        if (std.mem.indexOf(u8, address, ":") != null) {
            // Contains colon, likely a TCP address
            return try connectTcp(allocator, address);
        } else if (builtin.os.tag == .windows) {
            // On Windows, assume named pipe
            return try connectWindowsPipe(allocator, address);
        } else {
            // On Unix systems, assume Unix socket
            return try connectUnixSocket(allocator, address);
        }
    } else |_| {
        // 2. No environment variable, auto-spawn Neovim
        std.debug.print("NVIM_LISTEN_ADDRESS not set, spawning Neovim...\n", .{});
        return try connectSpawn(allocator, "nvim", 5000);
    }
}

/// Connect with configuration
pub fn connectWithConfig(allocator: std.mem.Allocator, config: ConnectionConfig) !znvim.Client {
    // Priority: spawn > stdio > platform-specific > tcp

    if (config.spawn_nvim) {
        return try connectSpawn(allocator, config.nvim_path, config.timeout_ms);
    }

    if (config.use_stdio) {
        return try connectStdio(allocator, config.timeout_ms);
    }

    if (builtin.os.tag == .windows) {
        if (config.windows_pipe_name) |pipe_name| {
            return try connectWindowsPipe(allocator, pipe_name);
        }
    } else {
        if (config.unix_socket_path) |socket_path| {
            return try connectUnixSocket(allocator, socket_path);
        }
    }

    if (config.tcp_host) |host| {
        if (config.tcp_port) |port| {
            const address = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ host, port });
            defer allocator.free(address);
            return try connectTcp(allocator, address);
        }
    }

    return error.NoConnectionMethodSpecified;
}

/// Connect to Unix Socket (Unix/Linux/macOS only)
pub fn connectUnixSocket(allocator: std.mem.Allocator, socket_path: []const u8) !znvim.Client {
    if (builtin.os.tag == .windows) {
        std.debug.print("Unix Socket not supported on Windows\n", .{});
        return error.UnsupportedPlatform;
    }

    std.debug.print("Connecting via Unix Socket: {s}\n", .{socket_path});
    var client = try znvim.Client.init(allocator, .{
        .socket_path = socket_path,
    });
    try client.connect();
    std.debug.print("Connected successfully!\n\n", .{});
    return client;
}

/// Connect to Windows Named Pipe (Windows only)
pub fn connectWindowsPipe(allocator: std.mem.Allocator, pipe_name: []const u8) !znvim.Client {
    if (builtin.os.tag != .windows) {
        std.debug.print("Windows Named Pipe not supported on {s}\n", .{@tagName(builtin.os.tag)});
        return error.UnsupportedPlatform;
    }

    std.debug.print("Connecting via Windows Named Pipe: {s}\n", .{pipe_name});
    var client = try znvim.Client.init(allocator, .{
        .socket_path = pipe_name,
    });
    try client.connect();
    std.debug.print("Connected successfully!\n\n", .{});
    return client;
}

/// Connect to TCP (cross-platform)
pub fn connectTcp(allocator: std.mem.Allocator, address: []const u8) !znvim.Client {
    std.debug.print("Connecting via TCP: {s}\n", .{address});

    // Parse address and port
    const colon_pos = std.mem.lastIndexOf(u8, address, ":") orelse return error.InvalidTcpAddress;
    const host = address[0..colon_pos];
    const port_str = address[colon_pos + 1 ..];
    const port = try std.fmt.parseInt(u16, port_str, 10);

    var client = try znvim.Client.init(allocator, .{
        .tcp_address = host,
        .tcp_port = port,
    });
    try client.connect();
    std.debug.print("Connected successfully!\n\n", .{});
    return client;
}

/// Connect to Stdio (cross-platform)
pub fn connectStdio(allocator: std.mem.Allocator, timeout_ms: u32) !znvim.Client {
    std.debug.print("Connecting via Stdio\n", .{});
    var client = try znvim.Client.init(allocator, .{
        .use_stdio = true,
        .timeout_ms = timeout_ms,
    });
    try client.connect();
    std.debug.print("Connected successfully!\n\n", .{});
    return client;
}

/// Auto-spawn Neovim (cross-platform)
pub fn connectSpawn(allocator: std.mem.Allocator, nvim_path: []const u8, timeout_ms: u32) !znvim.Client {
    std.debug.print("Spawning Neovim: {s}\n", .{nvim_path});
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = nvim_path,
        .timeout_ms = timeout_ms,
    });
    try client.connect();
    std.debug.print("Neovim started successfully!\n\n", .{});
    return client;
}

/// Print supported connection methods
pub fn printSupportedMethods() void {
    std.debug.print("=== Supported Connection Methods ===\n\n", .{});

    std.debug.print("Cross-platform methods (all systems):\n", .{});
    std.debug.print("  * TCP Socket     - Network connection (requires Neovim listening on TCP port)\n", .{});
    std.debug.print("  * Stdio          - Standard input/output pipes\n", .{});
    std.debug.print("  * Spawn Process  - Auto-spawn embedded Neovim\n", .{});
    std.debug.print("\n", .{});

    if (builtin.os.tag == .windows) {
        std.debug.print("Windows-specific methods:\n", .{});
        std.debug.print("  * Named Pipe     - Windows named pipes\n", .{});
    } else {
        std.debug.print("Unix/Linux/macOS-specific methods:\n", .{});
        std.debug.print("  * Unix Socket    - Unix domain sockets\n", .{});
    }
    std.debug.print("\n", .{});

    std.debug.print("Current platform: {s}\n", .{@tagName(builtin.os.tag)});
    std.debug.print("\n", .{});
}

/// Print environment variable configuration examples
pub fn printEnvVarExamples() void {
    std.debug.print("=== Environment Variable Configuration ===\n\n", .{});

    if (builtin.os.tag == .windows) {
        std.debug.print("Windows:\n", .{});
        std.debug.print("  set NVIM_LISTEN_ADDRESS=127.0.0.1:6666\n", .{});
        std.debug.print("  set NVIM_LISTEN_ADDRESS=\\\\.\\pipe\\nvim-pipe\n", .{});
    } else {
        std.debug.print("Unix/Linux/macOS:\n", .{});
        std.debug.print("  export NVIM_LISTEN_ADDRESS=/tmp/nvim.sock\n", .{});
        std.debug.print("  export NVIM_LISTEN_ADDRESS=127.0.0.1:6666\n", .{});
    }
    std.debug.print("\n", .{});
}

/// Display connection help information
pub fn printHelp() void {
    std.debug.print("=== znvim Connection Help ===\n\n", .{});
    printSupportedMethods();
    printEnvVarExamples();

    std.debug.print("Usage:\n", .{});
    std.debug.print("  1. Set NVIM_LISTEN_ADDRESS environment variable to connect to running Neovim\n", .{});
    std.debug.print("  2. Leave environment variable unset to auto-spawn new Neovim instance\n", .{});
    std.debug.print("  3. Use command-line arguments to specify connection method\n", .{});
    std.debug.print("\n", .{});
}
