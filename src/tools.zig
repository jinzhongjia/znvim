const std = @import("std");
const builtin = @import("builtin");
const Thread = std.Thread;

pub const POLLwin = struct {
    pub const POLLRDNORM = 0x0100;
    pub const POLLRDBAND = 0x0200;
    pub const POLLIN = POLLRDNORM | POLLRDBAND;
    pub const POLLPRI = 0x0400;

    pub const POLLWRNORM = 0x0010;
    pub const POLLOUT = POLLWRNORM;
    pub const POLLWRBAND = 0x0020;

    pub const POLLERR = 0x0001;
    pub const POLLHUP = 0x0002;
    pub const POLLNVAL = 0x0004;
};

/// create a automic context
pub fn ThreadSafe(context: type) type {
    return struct {
        const Self = @This();

        context: context,
        lock: Thread.Mutex,

        /// init
        pub fn init(param: context) Self {
            return Self{
                .context = param,
                .lock = .{},
            };
        }

        /// lock and return the context
        pub fn acquire(self: *Self) context {
            self.lock.lock();
            return self.context;
        }

        /// unlock
        pub fn release(self: *Self) void {
            self.lock.unlock();
        }
    };
}

// listenPipe for windows
pub fn listenFiles(file_0: std.fs.File, file_1: std.fs.File) !u32 {
    if (builtin.os.tag == .windows) {
        var pipes: [2]std.os.windows.HANDLE = .{ file_0.handle, file_1.handle };
        return try std.os.windows.WaitForMultipleObjectsEx(&pipes, false, 0, false);
    } else {
        @compileError("not support !");
    }
}
