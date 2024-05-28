const std = @import("std");
const builtin = @import("builtin");
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

pub const ErrorSet = error{
    PayloadTypeError,
    PayloadLengthError,
    NotFoundRes,
};

const ResToClientQueue = TailQueue(Payload);
const ToServerQueue = TailQueue(Payload);

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
            func: *const fn (params: Payload, allocator: Allocator, userdata: user_data) ResultType,
        };

        pub const NotifyMethodType = struct {
            userdata: user_data,
            func: *const fn (params: Payload, allocator: Allocator, userdata: user_data) void,
        };

        pub const Method = union(enum) {
            req: ReqMethodType,
            notify: NotifyMethodType,
        };

        const MethodHashMap = std.StringHashMap(Method);

        pub const TransType: type = switch (client_tag) {
            .file => std.fs.File,
            else => std.fs.File,
            // .socket => std.net.Stream,
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

        const ThreadSafeMethodHashMap = tools.ThreadSafe(*MethodHashMap);
        const ThreadSafeId = tools.ThreadSafe(*u32);
        const ThreadSafeResToClientQueue = tools.ThreadSafe(*ResToClientQueue);
        const ThreadSafeToServerQueue = tools.ThreadSafe(*ToServerQueue);
        const ThreadsafeSubscribeMap = tools.ThreadSafe(*SubscribeMap);
        const ThreadSafeTransType = tools.ThreadSafe(*TransType);

        /// just store ptr
        writer_ptr: *BufferedWriter,
        /// just store ptr
        reader_ptr: *BufferedReader,
        allocator: Allocator,

        id: ThreadSafeId,
        pack: Pack,
        method_hash_map: ThreadSafeMethodHashMap,
        res_to_client_queue: ThreadSafeResToClientQueue,
        to_server_queue: ThreadSafeToServerQueue,
        subscribe_map: ThreadsafeSubscribeMap,
        to_server_queue_s: Thread.Semaphore = .{},

        thread_pool_ptr: *Thread.Pool,

        /// init the rpc client
        /// we should note that the trans writer and reader will not close by deinit
        /// the owner should close manually
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
            const pack = Pack.init(writer_ptr, reader_ptr);

            // init method hash map
            const method_hash_map_ptr = try allocator.create(MethodHashMap);
            errdefer allocator.destroy(method_hash_map_ptr);
            method_hash_map_ptr.* = MethodHashMap.init(allocator);
            const method_hash_map = ThreadSafeMethodHashMap.init(method_hash_map_ptr);

            // init res queue
            const res_to_client_queue_ptr = try allocator.create(ResToClientQueue);
            errdefer allocator.destroy(res_to_client_queue_ptr);
            res_to_client_queue_ptr.* = ResToClientQueue{};
            const res_to_client_queue = ThreadSafeResToClientQueue.init(res_to_client_queue_ptr);

            // init req queue
            const to_server_queue_ptr = try allocator.create(ToServerQueue);
            errdefer allocator.destroy(to_server_queue_ptr);
            to_server_queue_ptr.* = ToServerQueue{};
            const to_server_queue = ThreadSafeToServerQueue.init(to_server_queue_ptr);

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
                .res_to_client_queue = res_to_client_queue,
                .to_server_queue = to_server_queue,
                .subscribe_map = subscribe_map,
                .thread_pool_ptr = thread_pool_ptr,
            };
        }

        /// deinit
        pub fn deinit(self: *Self) void {
            const allocator = self.allocator;
            self.thread_pool_ptr.deinit();
            allocator.destroy(self.thread_pool_ptr);

            const subscribe_map_ptr = self.subscribe_map.acquire();
            subscribe_map_ptr.deinit();
            allocator.destroy(subscribe_map_ptr);
            self.subscribe_map.release();

            const res_to_client_queue_ptr = self.res_to_client_queue.acquire();
            allocator.destroy(res_to_client_queue_ptr);
            self.res_to_client_queue.release();

            const to_server_queue = self.to_server_queue.acquire();
            allocator.destroy(to_server_queue);
            self.to_server_queue.release();

            const method_hash_map_ptr = self.method_hash_map.acquire();
            method_hash_map_ptr.deinit();
            allocator.destroy(method_hash_map_ptr);
            self.method_hash_map.release();

            const id_ptr = self.id.acquire();
            allocator.destroy(id_ptr);
            self.id.release();

            allocator.destroy(self.writer_ptr);
            allocator.destroy(self.reader_ptr);
        }

        /// register request method
        pub fn registerRequestMethod(self: *Self, method_name: []const u8, func: ReqMethodType) !void {
            const method_hash_map = self.method_hash_map.acquire();
            defer self.method_hash_map.release();
            try method_hash_map.put(method_name, Method{
                .req = func,
            });
        }

        /// register notify method
        pub fn registerNotifyMethod(self: *Self, method_name: []const u8, func: NotifyMethodType) !void {
            const method_hash_map = self.method_hash_map.acquire();
            defer self.method_hash_map.release();
            try method_hash_map.put(method_name, Method{
                .notify = func,
            });
        }

        /// flush the buffer
        inline fn flush(self: *Self) !void {
            try self.pack.write_context.flush();
        }

        // free the payload which is allocated by the self.allocator
        pub fn freePayload(self: Self, payload: Payload) void {
            payload.free(self.allocator);
        }

        // free the ResultType which is allocated by the self.allocator
        pub fn freeResultType(self: *Self, result: ResultType) void {
            switch (result) {
                inline else => |val| self.freePayload(val),
            }
        }

        fn makeInform() ![2]TransType {
            switch (builtin.os.tag) {
                .windows => {
                    var res: [2]TransType = undefined;
                    try std.os.windows.CreatePipe(&res[0].handle, &res[1].handle, &.{
                        .nLength = @sizeOf(std.os.windows.SECURITY_ATTRIBUTES),
                        .bInheritHandle = 0,
                        .lpSecurityDescriptor = null,
                    });

                    return res;
                },
                else => {
                    @compileError("not support!");
                },
            }
        }

        fn readFromServer(self: *Self) void {
            while (true) {
                // message from server
                var payload = self.pack.read(self.allocator) catch unreachable;
                errdefer payload.free(self.allocator);

                if (payload != .arr) {
                    continue;
                }
                // payload must be an array and its length must be 4 or 3
                const arr = payload.arr;
                if (arr.len > 4 or arr.len < 3) {
                    continue;
                }

                // get the message type
                const t: MessageType = @enumFromInt(arr[0].uint);
                // when message is response
                switch (t) {
                    .Response => {
                        const msg_id = arr[1].uint;
                        {
                            const res_queue = self.res_to_client_queue.acquire();
                            defer self.res_to_client_queue.release();
                            const node = self.allocator.create(ResToClientQueue.Node) catch unreachable;
                            node.data = payload;
                            res_queue.append(node);
                        }
                        const subscribe_map = self.subscribe_map.acquire();
                        defer self.subscribe_map.release();
                        if (subscribe_map.get(@intCast(msg_id))) |val| {
                            val.set();
                        }
                    },
                    .Request => {
                        // get method name
                        const method_name = arr[1].str.value();
                        // try get the method_hash_map
                        const method_hash_map = self.method_hash_map.acquire();
                        // we need to release hash map
                        defer self.method_hash_map.release();

                        if (method_hash_map.get(method_name)) |method| {
                            if (method == .req) {
                                // when method is req we handle this
                                self.thread_pool_ptr.spawn(handleServerRequest, .{
                                    self,
                                    method.req,
                                    payload,
                                }) catch unreachable;
                            }
                        }
                    },
                    .Notification => {
                        // get method name
                        const method_name = arr[1].str.value();
                        // try get the method_hash_map
                        const method_hash_map = self.method_hash_map.acquire();
                        // we need to release hash map
                        defer self.method_hash_map.release();

                        if (method_hash_map.get(method_name)) |method| {
                            if (method == .notify) {
                                self.thread_pool_ptr.spawn(handleServerNotify, .{
                                    self,
                                    method.notify,
                                    payload,
                                }) catch unreachable;
                            }
                        }
                    },
                }
            }
        }

        fn sendToServer(self: *Self) void {
            while (true) {
                // use semaphore
                self.to_server_queue_s.wait();

                const to_server_queue = self.to_server_queue.acquire();
                defer self.to_server_queue.release();
                if (to_server_queue.pop()) |node| {
                    // free the payload node
                    defer self.allocator.destroy(node);
                    // collect the payload content
                    defer self.freePayload(node.data);
                    self.pack.write(node.data) catch unreachable;
                    // flush the writer buffer
                    self.flush() catch unreachable;
                }
            }
        }

        pub fn loop(self: *Self) !void {
            try self.thread_pool_ptr.spawn(readFromServer, .{self});
            try self.thread_pool_ptr.spawn(sendToServer, .{self});
        }

        /// handle the request from server
        pub fn handleServerRequest(self: *Self, method: ReqMethodType, payload: Payload) void {
            // and we need to free the payload content, that maybe contain allocated memory!
            defer self.freePayload(payload);

            // get the array
            const arr = payload.arr;
            // get the msgpack id
            const msg_id = arr[1].uint;
            // get the params
            const params = arr[3];

            // to run the corresponding method and get the result
            const result = method.func(params, self.allocator, method.userdata);

            // create a res node
            const node = self.allocator.create(ToServerQueue.Node) catch {
                return;
            };
            errdefer self.allocator.destroy(node);

            // allocator the res memory, if allocator failed, just return, and keep silent
            var res = Payload.arrPayload(4, self.allocator) catch {
                return;
            };
            errdefer self.freePayload(res);

            // setting the category code
            res.setArrElement(0, Payload.uintToPayload(@intFromEnum(MessageType.Response))) catch unreachable;

            // setting the id
            res.setArrElement(1, Payload.uintToPayload(msg_id)) catch unreachable;

            // setting the error
            res.setArrElement(2, if (result == .err) result.err else Payload.nilToPayload()) catch unreachable;

            // setting the result
            res.setArrElement(3, if (result == .result) result.result else Payload.nilToPayload()) catch unreachable;

            // get the right to handle to_server_queue
            const to_server_queue = self.to_server_queue.acquire();
            {
                defer self.to_server_queue.release();
                node.data = res;
                // append the res node to queue
                to_server_queue.append(node);
            }

            self.to_server_queue_s.post();
        }

        /// handle the notify from server
        pub fn handleServerNotify(self: *Self, method: NotifyMethodType, payload: Payload) void {
            // and we need to free the payload
            defer self.freePayload(payload);

            // get param of notify
            const params = payload.arr[2];

            // try run the handle function
            method.func(params, self.allocator, method.userdata);
        }

        pub fn call(self: *Self, method_name: []const u8, params: Payload) !ResultType {
            const node = try self.allocator.create(ResToClientQueue.Node);
            errdefer self.allocator.destroy(node);

            const req = try Payload.arrPayload(4, self.allocator);
            errdefer self.freePayload(req);

            try req.setArrElement(0, Payload.uintToPayload(@intFromEnum(MessageType.Request)));

            const id = self.id.acquire().*;
            self.id.release();

            try req.setArrElement(1, Payload.uintToPayload(id));
            try req.setArrElement(2, try Payload.strToPayload(method_name, self.allocator));
            try req.setArrElement(3, params);

            const event = try self.allocator.create(Thread.ResetEvent);
            defer self.allocator.destroy(event);
            event.* = Thread.ResetEvent{};

            {
                const subscribe_map = self.subscribe_map.acquire();
                defer self.subscribe_map.release();
                subscribe_map.put(id, event) catch unreachable;
            }

            const to_server_queue = self.to_server_queue.acquire();
            {
                defer self.to_server_queue.release();
                node.data = req;
                to_server_queue.append(node);
            }

            const id_ptr = self.id.acquire();
            {
                defer self.id.release();
                id_ptr.* += 1;
            }

            event.wait();

            {
                const subscribe_map = self.subscribe_map.acquire();
                defer self.subscribe_map.release();
                subscribe_map.remove(id);
            }

            const res_to_client_queue = self.res_to_client_queue.acquire();
            defer self.res_to_client_queue.release();

            const length = res_to_client_queue.len;

            for (0..length) |_| {
                if (res_to_client_queue.pop()) |val| {
                    const res_payload = val.data;
                    if (res_payload != .arr or res_payload.arr[1].uint != id) {
                        res_to_client_queue.prepend(val);
                        continue;
                    }
                    defer self.allocator.destroy(val);
                    if (res_payload.arr[2] != .nil) {
                        return ResultType{ .err = res_payload.arr[2] };
                    } else {
                        return ResultType{ .result = res_payload.arr[3] };
                    }
                }
            }

            return ErrorSet.NotFoundRes;
        }

        pub fn notify(self: *Self, method_name: []const u8, params: Payload) !void {
            const node = try self.allocator.create(ResToClientQueue.Node);
            errdefer self.allocator.destroy(node);

            var note = try Payload.arrPayload(3, self.allocator);
            try note.setArrElement(0, Payload.uintToPayload(@intFromEnum(MessageType.Notification)));
            try note.setArrElement(1, try Payload.strToPayload(method_name, self.allocator));
            try note.setArrElement(2, params);

            const to_server_queue = self.to_server_queue.acquire();
            {
                defer self.to_server_queue.release();
                node.data = note;
                to_server_queue.append(node);
            }
        }
    };
}
