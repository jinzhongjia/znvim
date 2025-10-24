const std = @import("std");

/// Thin virtual dispatch wrapper used by the client to talk to any transport implementation.
pub const Transport = struct {
    pub const ReadError = error{
        ConnectionClosed,
        Timeout,
        UnexpectedError,
    };

    pub const WriteError = error{
        ConnectionClosed,
        BrokenPipe,
        UnexpectedError,
    };

    /// Function table each concrete transport must implement.
    pub const VTable = struct {
        connect: *const fn (*Transport, address: []const u8) anyerror!void,
        disconnect: *const fn (*Transport) void,
        read: *const fn (*Transport, buffer: []u8) ReadError!usize,
        write: *const fn (*Transport, data: []const u8) WriteError!void,
        is_connected: *const fn (*const Transport) bool,
    };

    vtable: *const VTable,
    impl: *anyopaque,

    /// Initializes the wrapper with a pointer to the concrete instance and its vtable.
    pub fn init(impl: *anyopaque, vtable: *const VTable) Transport {
        return .{ .vtable = vtable, .impl = impl };
    }

    pub fn connect(self: *Transport, address: []const u8) anyerror!void {
        return self.vtable.connect(self, address);
    }

    pub fn disconnect(self: *Transport) void {
        self.vtable.disconnect(self);
    }

    pub fn read(self: *Transport, buffer: []u8) ReadError!usize {
        return self.vtable.read(self, buffer);
    }

    pub fn write(self: *Transport, data: []const u8) WriteError!void {
        return self.vtable.write(self, data);
    }

    pub fn isConnected(self: *const Transport) bool {
        return self.vtable.is_connected(self);
    }

    /// Casts the opaque pointer back to its original transport type.
    pub fn downcast(self: *Transport, comptime T: type) *T {
        return @as(*T, @ptrCast(@alignCast(self.impl)));
    }

    /// Const variant of `downcast`.
    pub fn downcastConst(self: *const Transport, comptime T: type) *const T {
        return @as(*const T, @ptrCast(@alignCast(self.impl)));
    }
};
