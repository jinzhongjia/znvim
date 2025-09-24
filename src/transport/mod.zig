const builtin = @import("builtin");

/// Re-exports all transport implementations for convenient importing.
pub const Transport = @import("transport.zig").Transport;
pub const UnixSocket = @import("unix_socket.zig").UnixSocket;
pub const TcpSocket = @import("tcp_socket.zig").TcpSocket;
pub const Stdio = @import("stdio.zig").Stdio;
pub const ChildProcess = @import("child_process.zig").ChildProcess;
pub const WindowsPipe = if (builtin.os.tag == .windows)
    @import("windows_pipe.zig").WindowsPipe
else
    struct {};
