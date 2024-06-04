const std = @import("std");
const builtin = @import("builtin");
const Thread = std.Thread;

const windows = std.os.windows;
const posix = std.posix;
const named_pipe = @import("named_pipe.zig");

pub const ClientType = enum {
    stdio,
    pipe,
    socket,
};

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

const listenErrors = error{
    win32,
    waspoll,
    winsocket,
    socket,
};

// listenPipe for windows
pub fn listen(comptime client_tag: ClientType, pl: anytype) !bool {
    const trans = switch (client_tag) {
        .pipe, .stdio => @as(std.fs.File, pl),
        .socket => @as(std.net.Stream, pl),
    };
    switch (comptime builtin.target.os.tag) {
        .windows => {
            if (client_tag == .pipe) {
                const check_result = named_pipe
                    .checkNamePipeData(trans);
                switch (check_result) {
                    .result => |data_available| {
                        if (!data_available) {
                            return false;
                        }
                    },
                    .win_error => |err| {
                        _ = err;
                        return listenErrors.win32;
                    },
                }
            } else if (client_tag == .socket) {
                var sockfds: [1]windows.ws2_32.pollfd = undefined;

                sockfds[0].fd = trans.handle;
                sockfds[0].events = POLLwin.POLLIN;

                const res = windows.poll(&sockfds, 1, 0);
                if (res == 0) {
                    return false;
                } else if (res < 0) {
                    return listenErrors.waspoll;
                } else if (sockfds[0].revents &
                    (POLLwin.POLLERR |
                    POLLwin.POLLHUP |
                    POLLwin.POLLNVAL) != 0)
                {
                    return listenErrors.winsocket;
                }
            }
        },

        .linux => {
            var pollfd: [1]posix.pollfd = undefined;
            pollfd[0].fd = trans.handle;
            pollfd[0].events = posix.POLL.IN;
            const res = try std.posix.poll(
                &pollfd,
                0,
            );
            if (res == 0) {
                return false;
            } else if (pollfd[0].revents & (posix.POLL.ERR | posix.POLL.HUP | posix.POLL.NVAL) != 0) {
                return listenErrors.socket;
            }
        },
        else => @compileError(std.fmt.comptimePrint(
            "not support current os {s}",
            .{@tagName(builtin.target.os.tag)},
        )),
    }
    return true;
}
