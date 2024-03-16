const std = @import("std");
const msgpack = @import("msgpack");

const Allocator = std.mem.Allocator;
pub const Payload = msgpack.Payload;

/// this fifo restore req
const ReqFifo = std.fifo.LinearFifo(Payload, .Dynamic);
/// this fifo restore res
const ResFifo = std.fifo.LinearFifo(Payload, .Dynamic);

pub const ReqMethodType = fn (allocator: Allocator, param: Payload) Payload;
pub const NotMethodType = fn (allocator: Allocator, param: Payload) void;

const Method = union(enum) {
    req: *ReqMethodType,
    res: *NotMethodType,
};

const MessageType = enum(u2) {
    Request = 0,
    Response = 1,
    Notification = 2,
};

const MethodHashMap = std.StringHashMap(Method);

pub const ClientType = enum {
    /// this is for stdio or named pipe
    file,
    /// this is for tcp or unix socket
    socket,
};

pub const ResultType = union(enum) {
    err: Payload,
    result: Payload,
};

pub const ErrorSet = error{
    PayloadTypeError,
    PayloadLengthError,
};

pub fn rpcClientType(
    comptime buffer_size: usize,
    comptime client_tag: ClientType,
) type {
    return struct {
        const Self = @This();

        pub const TransType: type = switch (client_tag) {
            .file => std.fs.File,
            .socket => std.net.Stream,
        };

        const BufferedWriter = std.io.BufferedWriter(
            buffer_size,
            TransType.Writer,
        );
        const BufferedReader = std.io.BufferedReader(
            buffer_size,
            TransType.Reader,
        );

        const Pack = msgpack.Pack(
            *BufferedWriter,
            *BufferedReader,
            BufferedWriter.Error,
            BufferedReader.Error,
            BufferedWriter.write,
            BufferedReader.read,
        );

        msg_id: u32 = 0,
        method_hash_map: MethodHashMap,
        req_fifo: ReqFifo,
        res_fifo: ResFifo,
        pack: Pack,
        /// just store ptr
        writer_ptr: *BufferedWriter,
        /// just store ptr
        reader_ptr: *BufferedReader,
        allocator: Allocator,

        /// init
        pub fn init(
            trans_writer: TransType,
            trans_reader: TransType,
            allocator: Allocator,
        ) !Self {
            const writer_ptr = try allocator.create(BufferedWriter);
            errdefer allocator.destroy(writer_ptr);
            const reader_ptr = try allocator.create(BufferedReader);
            errdefer allocator.destroy(reader_ptr);
            const method_hash_map = MethodHashMap.init(allocator);
            const req_fifo: ReqFifo = ReqFifo.init(allocator);
            const res_fifo: ResFifo = ResFifo.init(allocator);

            writer_ptr.* = .{
                .buf = undefined,
                .end = 0,
                .unbuffered_writer = trans_writer.writer(),
            };

            reader_ptr.* = .{
                .buf = undefined,
                .start = 0,
                .end = 0,
                .unbuffered_reader = trans_reader.reader(),
            };
            const pack = Pack.init(writer_ptr, reader_ptr);

            return Self{
                .method_hash_map = method_hash_map,
                .req_fifo = req_fifo,
                .res_fifo = res_fifo,
                .pack = pack,
                .writer_ptr = writer_ptr,
                .reader_ptr = reader_ptr,
                .allocator = allocator,
            };
        }

        /// deinit
        pub fn deinit(self: *Self) void {
            self.method_hash_map.deinit();
            self.req_fifo.deinit();
            self.res_fifo.deinit();
            self.allocator.destroy(self.writer_ptr);
            self.allocator.destroy(self.reader_ptr);
        }

        fn flush(self: *Self) !void {
            try self.pack.write_context.flush();
        }

        pub fn loop(self: *Self) !void {
            var payload = try self.pack.read(self.allocator);
            errdefer payload.free(self.allocator);
            if (payload != .arr) {
                return ErrorSet.PayloadTypeError;
            }
            const arr = payload.arr;
            if (arr.len > 4 or arr.len < 3) {
                return ErrorSet.PayloadLengthError;
            }
            const t: MessageType = @enumFromInt(arr[0].uint);
            if (t == .Response) {
                try self.res_fifo.writeItem(payload);
            } else {
                try self.req_fifo.writeItem(payload);
            }
        }

        fn handleMethodReq() !void {}

        fn handleMethodNotify() !void {}

        pub fn call(self: *Self, method_name: []const u8, payload: Payload) !ResultType {
            var req_arr: [4]Payload = undefined;
            req_arr[0] = Payload.uintToPayload(@intFromEnum(MessageType.Request));
            req_arr[1] = Payload.uintToPayload(self.msg_id);
            req_arr[2] = Payload{ .str = msgpack.wrapStr(method_name) };
            req_arr[3] = payload;

            try self.pack.write(Payload{ .arr = &req_arr });
            try self.flush();
            while (true) {
                try self.loop();
                // this index will not be 0
                const latest_index = self.res_fifo.readableLength() - 1;
                var lastest_res = self.res_fifo.peekItem(latest_index);
                if (lastest_res.arr[1].uint == self.msg_id) {
                    self.res_fifo.discard(latest_index);
                    const res_err = lastest_res.arr[2];
                    const res_result = lastest_res.arr[3];
                    lastest_res.arr[2] = Payload.nilToPayload();
                    lastest_res.arr[3] = Payload.nilToPayload();
                    lastest_res.free(self.allocator);
                    if (res_err != .nil) {
                        return ResultType{
                            .err = res_err,
                        };
                    } else {
                        return ResultType{
                            .result = res_result,
                        };
                    }
                }
            }
        }

        /// this func to free payload
        fn freePayload(self: Self, payload: Payload) void {
            payload.free(self.allocator);
        }

        /// this func to free resultType
        pub fn freeResultType(self: Self, result: ResultType) void {
            switch (result) {
                inline else => |val| {
                    self.freePayload(val);
                },
            }
        }

        pub fn notify(self: Self, method_name: []const u8, payload: Payload) void {
            var req_arr: [4]Payload = undefined;
            req_arr[0] = Payload.uintToPayload(@intFromEnum(MessageType.Request));
            req_arr[1] = Payload.uintToPayload(self.msg_id);
            req_arr[2] = Payload{ .str = msgpack.wrapStr(method_name) };
            req_arr[3] = payload;

            try self.pack.write(Payload{ .arr = &req_arr });
            try self.flush();
        }
    };
}
