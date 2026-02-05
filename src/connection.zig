const zio = @import("zio");

/// Runtime management mode for zio-based async I/O.
pub const RuntimeMode = enum {
    /// Client creates and manages its own zio.Runtime on a background thread.
    /// This is the default mode and is safe for use from any non-runtime thread.
    owned_background_thread,

    /// Use an externally provided zio.Runtime.
    /// Caller must ensure the runtime is running and must use requestAsync()
    /// when calling from within the runtime's fiber context.
    external,
};

pub const ConnectionOptions = struct {
    // ========== Connection target options ==========

    /// Path to Unix domain socket (Unix/Linux/macOS) or named pipe (Windows).
    socket_path: ?[]const u8 = null,

    /// TCP host address for network connections.
    tcp_address: ?[]const u8 = null,

    /// TCP port number (required if tcp_address is set).
    tcp_port: ?u16 = null,

    /// Use stdin/stdout for communication (when znvim runs as nvim subprocess).
    use_stdio: bool = false,

    /// Spawn a new nvim --embed process automatically.
    spawn_process: bool = false,

    /// Path to the nvim executable (used when spawn_process is true).
    nvim_path: []const u8 = "nvim",

    /// Maximum time (milliseconds) to wait for operations; 0 disables the timeout.
    timeout_ms: u32 = 5000,

    /// Skip fetching API metadata on connect (for faster startup).
    skip_api_info: bool = false,

    // ========== zio runtime options ==========

    /// External zio.Runtime to use (only when runtime_mode == .external).
    /// If null and runtime_mode is .external, connect() will return an error.
    zio_runtime: ?*zio.Runtime = null,

    /// Runtime management mode.
    /// - .owned_background_thread: Client manages its own runtime (default, recommended)
    /// - .external: Use externally provided runtime
    runtime_mode: RuntimeMode = .owned_background_thread,

    /// Number of worker threads for the internal runtime.
    /// Only used when runtime_mode == .owned_background_thread.
    /// null means auto-detect based on CPU count.
    worker_threads: ?u16 = null,
};
