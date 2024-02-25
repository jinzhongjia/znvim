const std = @import("std");
const msgpack = @import("msgpack");

const net = std.net;
const Allocator = std.mem.Allocator;

const comptimePrint = std.fmt.comptimePrint;
const wrapStr = msgpack.wrapStr;

const MessageType = enum(u2) {
    Request = 0,
    Response = 1,
    Notification = 2,
};

const log = std.log.scoped(.znvim);

pub const ClientEnum = enum {
    /// this is for stdio or named pipe
    file,
    /// this is for tcp or unix socket
    socket,
};

pub fn CreateClient(
    comptime pack_type: type,
    comptime buffer_size: usize,
    comptime client_tag: ClientEnum,
) type {
    const type_info = @typeInfo(pack_type);
    if (type_info != .Struct or type_info.Struct.is_tuple) {
        const err_msg = comptimePrint("pack_type ({}) must be a struct", .{});
        @compileError(err_msg);
    }

    const struct_info = type_info.Struct;
    const decls = struct_info.decls;

    return struct {
        const Self = @This();
        pub const payloadType: type = switch (client_tag) {
            .file => std.fs.File,
            .socket => net.Stream,
        };

        const BufferedWriter = std.io.BufferedWriter(
            buffer_size,
            payloadType.Writer,
        );
        const BufferedReader = std.io.BufferedReader(
            buffer_size,
            payloadType.Reader,
        );

        const payloadPack = msgpack.Pack(
            *BufferedWriter,
            *BufferedReader,
            BufferedWriter.Error,
            BufferedReader.Error,
            BufferedWriter.write,
            BufferedReader.read,
        );

        id_ptr: *u32,
        payload: payloadPack,

        /// just store ptr
        writer_ptr: *BufferedWriter,
        /// just store ptr
        reader_ptr: *BufferedReader,
        allocator: Allocator,

        if_log: bool,

        // allocator will create a buffered writer and a buffered reader
        pub fn init(
            payload_writer: payloadType,
            payload_reader: payloadType,
            allocator: Allocator,
            if_log: bool,
        ) !Self {
            const writer_ptr = try allocator.create(BufferedWriter);
            const reader_ptr = try allocator.create(BufferedReader);
            const id_ptr = try allocator.create(u32);

            writer_ptr.* = .{
                .buf = undefined,
                .end = 0,
                .unbuffered_writer = payload_writer.writer(),
            };

            reader_ptr.* = .{
                .buf = undefined,
                .start = 0,
                .end = 0,
                .unbuffered_reader = payload_reader.reader(),
            };

            return Self{
                .id_ptr = id_ptr,
                .payload = payloadPack.init(
                    writer_ptr,
                    reader_ptr,
                ),
                .writer_ptr = writer_ptr,
                .reader_ptr = reader_ptr,
                .allocator = allocator,
                .if_log = if_log,
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.destroy(self.writer_ptr);
            self.allocator.destroy(self.reader_ptr);
            self.allocator.destroy(self.id_ptr);
        }

        fn read(
            self: Self,
            comptime T: type,
            allocator: Allocator,
        ) !msgpack.read_type_help(T) {
            return self.payload.read(T, allocator);
        }

        /// this function will get the type of message
        fn read_type(self: Self) !MessageType {
            const marker_u8 = try self.payload.read_type_marker_u8();
            if (marker_u8 != 0b10010100 and marker_u8 != 0b10010011) {
                return error.marker_error;
            }

            const type_id = try self.payload.read_u8();
            return @enumFromInt(type_id);
        }

        /// this function will get the msgid
        fn read_msgid(self: Self) !u32 {
            return self.payload.read_u32();
        }

        /// this function will get the method name
        /// NOTE: the str's mem need to free
        fn read_method(self: Self, allocator: Allocator) ![]const u8 {
            const str = try self.payload.read_str(allocator);
            return str.value();
        }

        /// this function will get the method params
        /// NOTE: the params's mem need to free
        fn read_params(
            self: Self,
            allocator: Allocator,
            comptime paramsT: type,
        ) !paramsT {
            return self.payload.read_tuple(paramsT, allocator);
        }

        /// this function will get the method result
        /// NOTE: the result's mem need to free
        fn read_result(
            self: Self,
            allocator: Allocator,
            comptime resultT: type,
        ) !msgpack.read_type_help(resultT) {
            return self.read(resultT, allocator);
        }

        /// this function will get the method error
        /// NOTE: the result's mem need to free
        fn read_error(
            self: Self,
            allocator: Allocator,
            comptime errorT: type,
        ) !msgpack.read_type_help(?errorT) {
            return self.read(?errorT, allocator);
        }

        /// this function is used to send request
        fn send_request(self: Self, method: []const u8, params: anytype) !u32 {
            const id_ptr = self.id_ptr;
            const msgid = id_ptr.*;
            const paramsT = @TypeOf(params);
            const params_type_info = @typeInfo(paramsT);
            if (params_type_info != .Struct or
                !params_type_info.Struct.is_tuple)
                @compileError("params must be tuple type!");

            try self.payload.write(.{
                @intFromEnum(MessageType.Request),
                msgid,
                wrapStr(method),
                params,
            });
            id_ptr.* += 1;
            try self.flushWrite();
            return msgid;
        }

        /// this function is used to send notification
        /// This function seems useless at the moment
        fn send_notification(self: Self, method: []const u8, params: anytype) !void {
            const paramsT = @TypeOf(params);
            const params_type_info = @typeInfo(paramsT);
            if (params_type_info != .Struct or
                !params_type_info.Struct.is_tuple)
                @compileError("params must be tuple type!");

            try self.payload.write(.{
                @intFromEnum(MessageType.Notification),
                wrapStr(method),
                params,
            });
            try self.flushWrite();
        }

        /// this function is used to send result
        fn send_result(self: Self, id: u32, err: anytype, result: anytype) !void {
            try self.payload.write(.{
                @intFromEnum(MessageType.Response),
                id,
                err,
                result,
            });
            try self.flushWrite();
        }

        // TODO: add send_notification support

        /// this function will handle request
        fn handleRequest(
            self: Self,
            id: u32,
            method_name: []const u8,
            allocator: Allocator,
        ) !void {
            inline for (decls) |decl| {
                const decl_name = decl.name;
                if (decl_name.len == method_name.len and
                    std.mem.eql(u8, method_name, decl_name))
                {

                    // This branch represents existing method
                    // get the method
                    const method = @field(pack_type, decl_name);
                    const fn_type = @TypeOf(method);
                    if (@typeInfo(fn_type) != .Fn) {
                        const err_msg = comptimePrint("pack_type must be a struct will all function", .{pack_type});
                        @compileError(err_msg);
                    }
                    const fn_type_info = @typeInfo(fn_type).Fn;
                    const param_tuple_type = fnParamsToTuple(fn_type_info.params);

                    var arena = std.heap.ArenaAllocator.init(allocator);
                    defer arena.deinit();
                    const arena_allocator = arena.allocator();
                    const param = try self.read_params(
                        arena_allocator,
                        param_tuple_type,
                    );

                    const return_type =
                        if (fn_type_info.return_type) |val|
                        val
                    else
                        void;

                    const return_type_info = @typeInfo(return_type);

                    // when return type is errorunion
                    if (return_type_info == .ErrorUnion) {
                        if (@call(.auto, method, param)) |result| {
                            try self.send_result(id, void{}, result);
                        } else |err| {
                            if (self.if_log) log.err(
                                "call ({s}) failed, err is {}",
                                .{ method_name, err },
                            );

                            try self.send_result(id, .{@errorName(err)}, void{});
                        }
                    }
                    // when return type is not errorunion
                    else {
                        const result: return_type = @call(.auto, method, param);
                        log.info("send result is {} ", .{result});
                        try self.send_result(id, void{}, result);
                    }

                    return;
                }
            }

            // this represents not existing method
            try self.send_result(id, void{}, msgpack.wrapStr("not found method!"));
        }

        /// this function handle notification
        fn handleNotification(
            self: Self,
            method_name: []const u8,
            allocator: Allocator,
        ) !void {
            inline for (decls) |decl| {
                const decl_name = decl.name;
                if (decl_name.len == method_name.len and
                    std.mem.eql(u8, method_name, decl_name))
                {
                    // This branch represents existing method

                    // get the method
                    const method = @field(pack_type, decl_name);
                    const fn_type = @TypeOf(method);
                    const fn_type_info = @typeInfo(fn_type).Fn;
                    const param_tuple_type = fnParamsToTuple(fn_type_info.params);

                    var arena = std.heap.ArenaAllocator.init(allocator);
                    defer arena.deinit();
                    const arena_allocator = arena.allocator();
                    const param = try self.read_params(
                        arena_allocator,
                        param_tuple_type,
                    );

                    const return_type =
                        if (fn_type_info.return_type) |val|
                        val
                    else
                        void;

                    const return_type_info = @typeInfo(return_type);

                    // when return type is errorunion
                    if (return_type_info == .ErrorUnion) {
                        _ = @call(.auto, method, param) catch |err| {
                            if (self.if_log)
                                log.err(
                                    "notification ({s}) failed, err is {}",
                                    .{ method_name, err },
                                );
                        };
                    }
                    // when return type is not errorunion
                    else {
                        _ = @call(.auto, method, param);
                    }

                    return;
                }
            }
        }

        /// flush write
        pub fn flushWrite(self: Self) !void {
            try self.payload.writeContext.flush();
        }

        fn call_res_header_handle(
            self: Self,
            method: []const u8,
            send_id: u32,
            comptime errorType: type,
            allocator: Allocator,
        ) !void {
            // This logic is to prevent a request from the server from being received when sending a request.
            while (true) {
                const t = try self.read_type();
                switch (t) {
                    .Request => {
                        const msgid = try self.read_msgid();
                        const method_name = try self.read_method(allocator);
                        try self.handleRequest(msgid, method_name, allocator);
                        // free method name
                        allocator.free(method_name);
                    },
                    .Response => {
                        const msgid = try self.read_msgid();
                        if (msgid != send_id) {
                            if (self.if_log)
                                log.err(
                                    "send_id ({}) is not eql msgid ({})",
                                    .{ send_id, msgid },
                                );
                            @panic("get response error");
                        }
                        break;
                    },
                    .Notification => {
                        const method_name = try self.read_method(allocator);
                        try self.handleNotification(method_name, allocator);
                        allocator.free(method_name);
                    },
                }
            }

            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const arena_allocator = arena.allocator();

            const err = try self.read_error(arena_allocator, errorType);
            if (err) |err_value| {
                if (self.if_log)
                    log.err("request method ({s}) failed, error id is ({}), msg is ({s})", .{
                        method,
                        @intFromEnum(err_value[0]),
                        err_value[1].value(),
                    });
                try self.payload.skip();
                return error.MSGID_INVALID;
            }
        }

        /// remote call
        pub fn call(
            self: Self,
            method: []const u8,
            params: anytype,
            comptime errorType: type,
            comptime resultType: type,
            allocator: Allocator,
        ) !resultType {
            const send_id = try self.send_request(method, params);
            try self.call_res_header_handle(
                method,
                send_id,
                errorType,
                allocator,
            );

            return self.read_result(allocator, resultType);
        }

        /// call with a reader
        /// this function will return a reader for you
        pub fn call_with_reader(
            self: Self,
            method: []const u8,
            params: anytype,
            comptime errorType: type,
            allocator: Allocator,
        ) !Reader {
            const send_id = try self.send_request(method, params);
            try self.call_res_header_handle(
                method,
                send_id,
                errorType,
                allocator,
            );

            return self.get_reader();
        }

        pub fn call_with_writer(self: Self, method: []const u8) !Writer {
            const id_ptr = self.id_ptr;
            const msgid = id_ptr.*;
            const writer = self.get_writer(msgid, method);
            try writer.write_array_header(4);
            try writer.write_uint(@intFromEnum(MessageType.Request));
            try writer.write_uint(msgid);
            try writer.write_str(method);

            return writer;
        }

        pub fn get_result_with_writer(
            self: Self,
            writer: Writer,
            comptime errorType: type,
            comptime resultType: type,
            allocator: Allocator,
        ) !resultType {
            try self.flushWrite();
            try self.call_res_header_handle(
                writer.method,
                writer.msg_id,
                errorType,
                allocator,
            );

            return self.read_result(allocator, resultType);
        }

        pub fn get_reader_with_writer(
            self: Self,
            writer: Writer,
            comptime errorType: type,
            allocator: Allocator,
        ) !Reader {
            try self.flushWrite();
            try self.call_res_header_handle(
                writer.method,
                writer.msg_id,
                errorType,
                allocator,
            );
            return self.get_reader();
        }

        /// this is event loop
        /// prepare for the client register method
        pub fn loop(self: Self, allocator: Allocator) !void {
            const t = try self.read_type();
            log.info("get message, type is {}", .{t});
            switch (t) {
                .Request => {
                    const msgid = try self.read_msgid();
                    const method_name = try self.read_method(allocator);
                    try self.handleRequest(msgid, method_name, allocator);
                },
                .Response => {
                    const msgid = try self.read_msgid();
                    try self.payload.skip();
                    try self.payload.skip();
                    if (self.if_log)
                        log.err("Msgid {} is not be handled", .{msgid});
                },
                .Notification => {
                    const method_name = try self.read_method(allocator);
                    try self.handleNotification(method_name, allocator);
                },
            }
        }

        fn get_writer(self: Self, msg_id: u32, method: []const u8) Writer {
            return Writer.init(self, msg_id, method);
        }

        pub const Writer = struct {
            client: Self,
            msg_id: u32,
            method: []const u8,

            fn init(c: Self, msg_id: u32, method: []const u8) Writer {
                return Writer{
                    .client = c,
                    .msg_id = msg_id,
                    .method = method,
                };
            }

            pub fn write(self: Writer, val: anytype) !void {
                return self.client.payload.write(val);
            }

            pub fn write_bool(self: Writer, val: bool) !void {
                return self.write(val);
            }

            pub fn write_int(self: Writer, val: i64) !void {
                return self.write(val);
            }

            pub fn write_uint(self: Writer, val: u64) !void {
                return self.write(val);
            }

            pub fn write_float(self: Writer, val: f64) !void {
                return self.write(val);
            }

            pub fn write_str(self: Writer, val: []const u8) !void {
                return self.write(wrapStr(val));
            }

            pub fn write_array_header(self: Writer, len: u32) !void {
                _ = try self.client.payload.getArrayWriter(len);
            }

            pub fn write_map_header(self: Writer, len: u32) !void {
                _ = try self.client.payload.getMapWriter(len);
            }

            pub fn write_ext(self: Writer, val: msgpack.EXT) !void {
                return self.write(val);
            }
        };

        fn get_reader(self: Self) Reader {
            return Reader.init(self);
        }

        pub const Reader = struct {
            client: Self,

            fn init(c: Self) Reader {
                return Reader{
                    .client = c,
                };
            }

            pub fn read(
                self: Reader,
                comptime T: type,
                allocator: Allocator,
            ) !msgpack.read_type_help(T) {
                return self.client.payload.read(T, allocator);
            }

            pub fn read_no_alloc(
                self: Reader,
                comptime T: type,
            ) !msgpack.read_type_help_no_alloc(T) {
                return self.client.payload.readNoAlloc(T);
            }

            pub fn read_bool(self: Reader) !bool {
                return self.read_no_alloc(bool);
            }

            pub fn read_int(self: Reader) !i64 {
                return self.read_no_alloc(i64);
            }

            pub fn read_uint(self: Reader) !u64 {
                return self.read_no_alloc(u64);
            }

            pub fn read_float(self: Reader) !f64 {
                return self.read_no_alloc(f64);
            }

            /// read str
            pub fn read_str(self: Reader, allocator: Allocator) ![]const u8 {
                const str: msgpack.Str = try self.read(msgpack.Str, allocator);
                return str.value();
            }

            pub fn read_array_len(self: Reader) !u32 {
                const array_reader = try self.client.payload.getArrayReader();
                return array_reader.len;
            }

            pub fn read_map_len(self: Reader) !u32 {
                const map_reader = try self.client.payload.getMapReader();
                return map_reader.len;
            }

            pub fn read_ext(self: Reader, allocator: Allocator) !msgpack.EXT {
                const ext: msgpack.EXT = try self.read(msgpack.EXT, allocator);
                return ext;
            }

            pub fn skip(self: Reader) !void {
                return self.client.payload.skip();
            }
        };
    };
}

/// generate a tuple through a fn param slice
/// Tuple keeps the same order as sliced
pub fn fnParamsToTuple(comptime params: []const std.builtin.Type.Fn.Param) type {
    const Type = std.builtin.Type;
    const fields: [params.len]Type.StructField = blk: {
        var res: [params.len]Type.StructField = undefined;

        for (params, 0..params.len) |param, i| {
            res[i] = Type.StructField{
                .type = param.type.?,
                .alignment = @alignOf(param.type.?),
                .default_value = null,
                .is_comptime = false,
                .name = std.fmt.comptimePrint("{}", .{i}),
            };
        }
        break :blk res;
    };
    return @Type(.{
        .Struct = std.builtin.Type.Struct{
            .layout = .Auto,
            .is_tuple = true,
            .decls = &.{},
            .fields = &fields,
        },
    });
}

/// make res tuple type
fn makeResTupleT(comptime errorType: type, comptime resType: type) type {
    return @Type(std.builtin.Type{
        .Struct = .{
            .layout = .Auto,
            .fields = &.{
                .{
                    .alignment = @alignOf(u8),
                    .name = "0",
                    .type = u8,
                    .is_comptime = false,
                    .default_value = null,
                },
                .{
                    .alignment = @alignOf(u32),
                    .name = "1",
                    .type = u32,
                    .is_comptime = false,
                    .default_value = null,
                },
                .{
                    .alignment = @alignOf(errorType),
                    .name = "2",
                    .type = errorType,
                    .is_comptime = false,
                    .default_value = null,
                },
                .{
                    .alignment = @alignOf(resType),
                    .name = "3",
                    .type = resType,
                    .is_comptime = false,
                    .default_value = null,
                },
            },
            .decls = &.{},
            .is_tuple = true,
        },
    });
}
