const std = @import("std");
const Thread = std.Thread;

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
