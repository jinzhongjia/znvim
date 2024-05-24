const std = @import("std");
const tools = @import("tools.zig");
const msgpack = @import("msgpack");

const Thread = std.Thread;

const TailQueue = std.TailQueue;

const Allocator = std.mem.Allocator;
pub const Payload = msgpack.Payload;

const MessageType = enum(u2) {
    Request = 0,
    Response = 1,
    Notification = 2,
};

const ResQueue = TailQueue(Payload);

const SubscribeMap = std.AutoHashMap(u32, *Thread.ResetEvent);

pub const ResultType = union(enum) {
    err: Payload,
    result: Payload,
};

pub const ClientType = enum {
    /// this is for stdio or named pipe
    file,
    /// this is for tcp or unix socket
    socket,
};

pub fn RpcClientType(
    comptime buffer_size: usize,
    comptime client_tag: ClientType,
    comptime user_data: type,
) type {
    return struct {
        const Self = @This();

        pub const ReqMethodType = struct {
            userdata: user_data,
            func: *const fn (params: Payload, allocator: Allocator, userdata: ?*anyopaque) ResultType,
        };

        pub const NotifyMethodType = struct {
            userdata: user_data,
            func: *const fn (params: Payload, allocator: Allocator, userdata: ?*anyopaque) void,
        };

        pub const Method = union(enum) {
            req: ReqMethodType,
            notify: NotifyMethodType,
        };

        const MethodHashMap = std.StringHashMap(Method);

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

        const ThreadSafePack = tools.ThreadSafe(*Pack);

        const ThreadSafeMethodHashMap = tools.ThreadSafe(*MethodHashMap);
        const ThreadSafeId = tools.ThreadSafe(*u32);
        const ThreadSafeResQueue = tools.ThreadSafe(*ResQueue);
        const ThreadsafeSubscribeMap = tools.ThreadSafe(*SubscribeMap);

        /// just store ptr
        writer_ptr: *BufferedWriter,
        /// just store ptr
        reader_ptr: *BufferedReader,
        allocator: Allocator,

        id: ThreadSafeId,
        pack: ThreadSafePack,
        method_hash_map: ThreadSafeMethodHashMap,
        res_queue: ThreadSafeResQueue,
        subscribe_map: ThreadsafeSubscribeMap,

        thread_pool_ptr: *Thread.Pool,

        pub fn init(
            trans_writer: TransType,
            trans_reader: TransType,
            allocator: Allocator,
        ) !Self {
            const writer_ptr = try allocator.create(BufferedWriter);
            errdefer allocator.destroy(writer_ptr);

            writer_ptr.* = .{
                .buf = undefined,
                .end = 0,
                .unbuffered_writer = trans_writer.writer(),
            };

            const reader_ptr = try allocator.create(BufferedReader);
            errdefer allocator.destroy(reader_ptr);

            reader_ptr.* = .{
                .buf = undefined,
                .start = 0,
                .end = 0,
                .unbuffered_reader = trans_reader.reader(),
            };

            // init id
            const id_ptr = try allocator.create(u32);
            errdefer allocator.destroy(id_ptr);
            const id = ThreadSafeId.init(id_ptr);

            // init pack
            const pack_ptr = try allocator.create(Pack);
            errdefer allocator.destroy(pack_ptr);
            pack_ptr.* = Pack.init(writer_ptr, reader_ptr);
            const pack = ThreadSafePack.init(pack_ptr);

            // init method hash map
            const method_hash_map_ptr = try allocator.create(MethodHashMap);
            errdefer allocator.destroy(method_hash_map_ptr);
            method_hash_map_ptr.* = MethodHashMap.init(allocator);
            const method_hash_map = ThreadSafeMethodHashMap.init(method_hash_map_ptr);

            // init res queue
            const res_queue_ptr = try allocator.create(ResQueue);
            errdefer allocator.destroy(res_queue_ptr);
            res_queue_ptr.* = ResQueue{};
            const res_queue = ThreadSafeResQueue.init(res_queue_ptr);

            // init subscribe map
            const subscribe_map_ptr = try allocator.create(SubscribeMap);
            errdefer allocator.destroy(subscribe_map_ptr);
            subscribe_map_ptr.* = SubscribeMap.init(allocator);
            const subscribe_map = ThreadsafeSubscribeMap.init(subscribe_map_ptr);

            // init thread pool
            var thread_pool_ptr = try allocator.create(Thread.Pool);
            errdefer allocator.destroy(thread_pool_ptr);
            try thread_pool_ptr.init(.{ .allocator = allocator });

            return Self{
                .writer_ptr = writer_ptr,
                .reader_ptr = reader_ptr,
                .allocator = allocator,
                .id = id,
                .pack = pack,
                .method_hash_map = method_hash_map,
                .res_queue = res_queue,
                .subscribe_map = subscribe_map,
                .thread_pool_ptr = thread_pool_ptr,
            };
        }

        pub fn deinit(self: *Self) void {
            const allocator = self.allocator;
            self.thread_pool_ptr.deinit();
            allocator.destroy(self.thread_pool_ptr);

            const subscribe_map_ptr = self.subscribe_map.acquire();
            subscribe_map_ptr.deinit();
            allocator.destroy(subscribe_map_ptr);
            self.subscribe_map.release();

            const res_queue_ptr = self.res_queue.acquire();
            allocator.destroy(res_queue_ptr);
            self.res_queue.release();

            const method_hash_map_ptr = self.method_hash_map.acquire();
            method_hash_map_ptr.deinit();
            allocator.destroy(method_hash_map_ptr);
            self.method_hash_map.release();

            const pack_ptr = self.pack.acquire();
            allocator.destroy(pack_ptr);
            self.pack.release();

            const id_ptr = self.id.acquire();
            allocator.destroy(id_ptr);
            self.id.release();

            allocator.destroy(self.writer_ptr);
            allocator.destroy(self.reader_ptr);
        }
    };
}
