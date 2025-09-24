pub const ConnectionOptions = struct {
    socket_path: ?[]const u8 = null,
    tcp_address: ?[]const u8 = null,
    tcp_port: ?u16 = null,
    use_stdio: bool = false,
    spawn_process: bool = false,
    nvim_path: []const u8 = "nvim",
    /// Maximum time (milliseconds) to wait for blocking transport operations; 0 disables the timeout.
    timeout_ms: u32 = 5000,
    skip_api_info: bool = false,
};
