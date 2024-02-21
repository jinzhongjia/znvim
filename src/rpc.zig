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

pub fn TCPClient(pack_type: type, comptime buffer_size: usize) type {
    const type_info = @typeInfo(pack_type);
    if (type_info != .Struct or type_info.Struct.is_tuple) {
        const err_msg = comptimePrint("pack_type ({}) must be a struct", .{});
        @compileError(err_msg);
    }

    const struct_info = type_info.Struct;
    const decls = struct_info.decls;

    const BufferedWriter = std.io.BufferedWriter(buffer_size, net.Stream.Writer);
    const BufferedReader = std.io.BufferedReader(buffer_size, net.Stream.Reader);

    const streamPack = msgpack.Pack(
        *BufferedWriter,
        *BufferedReader,
        BufferedWriter.Error,
        BufferedReader.Error,
        BufferedWriter.write,
        BufferedReader.read,
    );

    return struct {
        const Self = @This();

        id_ptr: *u32,
        stream: net.Stream,
        pack: streamPack,

        writer_ptr: *BufferedWriter,
        reader_ptr: *BufferedReader,
        allocator: Allocator,

        // allocator will create a buffered writer and a buffered reader
        pub fn init(stream: net.Stream, allocator: Allocator) !Self {
            const writer_ptr = try allocator.create(BufferedWriter);
            const reader_ptr = try allocator.create(BufferedReader);
            const id_ptr = try allocator.create(u32);

            writer_ptr.* = .{
                .buf = undefined,
                .end = 0,
                .unbuffered_writer = stream.writer(),
            };

            reader_ptr.* = .{
                .buf = undefined,
                .start = 0,
                .end = 0,
                .unbuffered_reader = stream.reader(),
            };

            return Self{
                .id_ptr = id_ptr,
                .stream = stream,
                .pack = streamPack.init(
                    writer_ptr,
                    reader_ptr,
                ),
                .writer_ptr = writer_ptr,
                .reader_ptr = reader_ptr,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.destroy(self.writer_ptr);
            self.allocator.destroy(self.reader_ptr);
            self.allocator.destroy(self.id_ptr);
        }

        fn read(self: Self, T: type, allocator: Allocator) !msgpack.read_type_help(T) {
            return self.pack.read(T, allocator);
        }

        /// this function will get the type of message
        fn read_type(self: Self) !MessageType {
            const marker_u8 = try self.pack.read_type_marker_u8();
            if (marker_u8 != 0b10010100 and marker_u8 != 0b10010011) {
                return error.marker_error;
            }

            const type_id = try self.pack.read_u8();
            return @enumFromInt(type_id);
        }

        /// this function will get the msgid
        fn read_msgid(self: Self) !u32 {
            return self.pack.read_u32();
        }

        /// this function will get the method name
        /// NOTE: the str's mem need to free
        fn read_method(self: Self, allocator: Allocator) ![]const u8 {
            const str = try self.pack.read_str(allocator);
            return str.value();
        }

        /// this function will get the method params
        /// NOTE: the params's mem need to free
        fn read_params(self: Self, allocator: Allocator, paramsT: type) !paramsT {
            return self.pack.read_tuple(paramsT, allocator);
        }

        /// this function will get the method result
        /// NOTE: the result's mem need to free
        fn read_result(self: Self, allocator: Allocator, resultT: type) !msgpack.read_type_help(resultT) {
            return self.read(resultT, allocator);
        }

        /// this function will get the method error
        /// NOTE: the result's mem need to free
        fn read_error(self: Self, allocator: Allocator, errorT: type) !msgpack.read_type_help(?errorT) {
            return self.read(?errorT, allocator);
        }

        /// this function will handle request
        fn handleRequest(self: Self, id: u32, method_name: []const u8, allocator: Allocator) !void {
            inline for (decls) |decl| {
                const decl_name = decl.name;
                if (decl_name.len == method_name.len and std.mem.eql(u8, method_name, decl_name)) {
                    // This branch represents existing method

                    // get the method
                    const method = @field(pack_type, decl_name);
                    const fn_type = @TypeOf(method);
                    const fn_type_info = @typeInfo(fn_type).Fn;
                    const param_tuple_type = fnParamsToTuple(fn_type_info.params);

                    var arena = std.heap.ArenaAllocator.init(allocator);
                    defer arena.deinit();
                    const arena_allocator = arena.allocator();
                    const param = try self.read_params(arena_allocator, param_tuple_type);

                    const return_type_info = @typeInfo(fn_type_info.return_type);
                    // when return type is errorunion
                    if (return_type_info == .ErrorUnion) {
                        if (@call(.auto, method, param)) |result| {
                            try self.send_result(id, void{}, result);
                        } else |err| {
                            log.err("call ({s}) failed, err is {}", .{ method_name, err });
                            try self.send_result(id, .{@errorName(err)}, void{});
                        }
                    }
                    // when return type is not errorunion
                    else {
                        const result = @call(.auto, method, param);
                        try self.send_result(id, void{}, result);
                    }

                    return;
                }
            }

            // this represents not existing method
            try self.send_result(id, void{}, msgpack.wrapStr("not found method!"));
        }

        /// this function handle notification
        fn handleNotification(self: Self, method_name: []const u8, allocator: Allocator) !void {
            inline for (decls) |decl| {
                const decl_name = decl.name;
                if (decl_name.len == method_name.len and std.mem.eql(u8, method_name, decl_name)) {
                    // This branch represents existing method

                    // get the method
                    const method = @field(pack_type, decl_name);
                    const fn_type = @TypeOf(method);
                    const fn_type_info = @typeInfo(fn_type).Fn;
                    const param_tuple_type = fnParamsToTuple(fn_type_info.params);

                    var arena = std.heap.ArenaAllocator.init(allocator);
                    defer arena.deinit();
                    const arena_allocator = arena.allocator();
                    const param = try self.read_params(arena_allocator, param_tuple_type);

                    const return_type_info = @typeInfo(fn_type_info.return_type);
                    // when return type is errorunion
                    if (return_type_info == .ErrorUnion) {
                        _ = @call(.auto, method, param) catch |err| {
                            log.err("notification ({s}) failed, err is {}", .{ method_name, err });
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

        /// this function is used to sendd result
        fn send_result(self: Self, id: u32, err: anytype, result: anytype) !void {
            try self.pack.write(.{
                @intFromEnum(MessageType.Response),
                id,
                err,
                result,
            });
        }

        fn send_request(self: Self, method: []const u8, params: anytype) !u32 {
            const id_ptr = self.id_ptr;
            const msgid = id_ptr.*;
            const paramsT = @TypeOf(params);
            const params_type_info = @typeInfo(paramsT);
            if (params_type_info != .Struct or !params_type_info.Struct.is_tuple) {
                @compileError("params must be tuple type!");
            }
            try self.pack.write(.{ @intFromEnum(MessageType.Request), msgid, wrapStr(method), params });
            id_ptr.* += 1;
            return msgid;
        }

        /// flush write
        pub fn flushWrite(self: Self) !void {
            try self.pack.writeContext.flush();
        }

        fn call_handle(
            self: Self,
            method: []const u8,
            params: anytype,
            errorType: type,
            allocator: Allocator,
        ) !void {
            const send_id = try self.send_request(method, params);
            try self.flushWrite();
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
                            log.err("send_id ({}) is not eql msgid ({})", .{ send_id, msgid });
                            @panic("error");
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
                log.err("request method ({s}) failed, error id is ({}), msg is ({s})", .{
                    method,
                    @intFromEnum(err_value[0]),
                    err_value[1].value(),
                });
                try self.pack.skip();
                return error.MSGID_INVALID;
            }
        }

        /// remote call
        pub fn call(
            self: Self,
            method: []const u8,
            params: anytype,
            errorType: type,
            resultType: type,
            allocator: Allocator,
        ) !resultType {
            try self.call_handle(method, params, errorType, allocator);

            return self.read_result(allocator, resultType);
        }

        /// call with a reader
        /// this function will return a reader for you
        pub fn call_with_reader(
            self: Self,
            method: []const u8,
            params: anytype,
            errorType: type,
            allocator: Allocator,
        ) !Reader {
            try self.call_handle(method, params, errorType, allocator);
            return self.get_reader();
        }

        /// this is event loop
        /// prepare for the client register method
        pub fn loop(self: Self, allocator: Allocator) !void {
            const t = try self.read_type();
            switch (t) {
                .Request => {
                    const msgid = try self.read_msgid();
                    const method_name = try self.read_method(allocator);
                    try self.handleRequest(msgid, method_name, allocator);
                },
                .Response => {
                    const msgid = try self.read_msgid();
                    try self.pack.skip();
                    try self.pack.skip();
                    log.err("Msgid {} is not be handled", .{msgid});
                },
                .Notification => {
                    const method_name = try self.read_method(allocator);
                    try self.handleNotification(method_name, allocator);
                },
            }
        }

        fn get_reader(self: Self) Reader {
            return Reader.init(self);
        }

        pub const Reader = struct {
            pack: streamPack,
            s: Self,

            fn init(c: Self) Reader {
                return Reader{
                    .pack = c.pack,
                    .s = c,
                };
            }

            pub fn subArrayReader(self: Reader) !ArrayReader {
                return self.s.get_array_reader();
            }

            pub fn subMapReader(self: Reader) !MapReader {
                return self.s.get_map_reader();
            }

            pub fn read(self: Reader, comptime T: type, allocator: Allocator) !msgpack.read_type_help(T) {
                return self.pack.read(T, allocator);
            }

            pub fn read_no_alloc(self: Reader, comptime T: type) !msgpack.read_type_help_no_alloc(T) {
                return self.pack.readNoAlloc(T);
            }

            pub fn read_bool(self: Reader) !bool {
                return self.pack.read_bool();
            }

            pub fn read_int(self: Reader) !i64 {
                return try self.pack.read_i64();
            }

            pub fn read_uint(self: Reader) !u64 {
                return self.pack.read_u64();
            }

            pub fn read_float(self: Reader) !f64 {
                return self.pack.read_float();
            }

            /// read str
            pub fn read_str(self: Reader, allocator: Allocator) ![]const u8 {
                const str = try self.pack.read_str(allocator);
                return str.value();
            }

            pub fn read_ext(self: Reader, allocator: Allocator) !msgpack.EXT {
                const ext = try self.pack.read_ext(allocator);
                return ext;
            }
        };

        fn get_array_reader(self: Self) !ArrayReader {
            const reader = self.get_reader();
            return ArrayReader.init(reader);
        }

        pub const ArrayReader = struct {
            reader: Reader,
            array_reader: streamPack.ArrayReader,

            fn init(reader: Reader) !ArrayReader {
                const array_reader = try reader.pack.getArrayReader();
                return ArrayReader{
                    .reader = reader,
                    .array_reader = array_reader,
                };
            }

            pub fn subArrayReader(self: ArrayReader) !ArrayReader {
                return self.reader.subArrayReader();
            }

            pub fn subMapReader(self: ArrayReader) !MapReader {
                return self.reader.subMapReader();
            }

            // get array length
            pub fn len(self: ArrayReader) u32 {
                return self.array_reader.len;
            }

            pub fn read_element(self: ArrayReader, comptime T: type, allocator: Allocator) !msgpack.read_type_help(T) {
                return self.reader.read(T, allocator);
            }

            pub fn read_element_no_alloc(self: ArrayReader, comptime T: type) !msgpack.read_type_help_no_alloc(T) {
                return self.reader.read_no_alloc(T);
            }

            pub fn read_bool(self: ArrayReader) !bool {
                return self.reader.read_bool();
            }

            pub fn read_int(self: ArrayReader) !i64 {
                return self.reader.read_int();
            }

            pub fn read_uint(self: ArrayReader) !u64 {
                return self.reader.read_uint();
            }

            pub fn read_float(self: ArrayReader) !f64 {
                return self.reader.read_float();
            }

            pub fn read_str(self: ArrayReader, allocator: Allocator) ![]const u8 {
                return self.reader.read_str(allocator);
            }
        };

        fn get_map_reader(self: Self) !MapReader {
            const reader = self.get_reader();
            return MapReader.init(reader);
        }

        pub const MapReader = struct {
            reader: Reader,
            map_reader: streamPack.MapReader,

            fn init(reader: Reader) !MapReader {
                const map_reader = try reader.pack.getMapReader();
                return MapReader{
                    .reader = reader,
                    .map_reader = map_reader,
                };
            }

            pub fn subArrayReader(self: MapReader) !ArrayReader {
                return self.reader.subArrayReader();
            }

            pub fn subMapReader(self: MapReader) !MapReader {
                return self.reader.subMapReader();
            }

            // get map length
            pub fn len(self: MapReader) u32 {
                return self.array_reader.len;
            }

            pub fn read(self: MapReader, comptime T: type, allocator: Allocator) !msgpack.read_type_help(T) {
                return self.reader.read(T, allocator);
            }

            pub fn read_no_alloc(self: MapReader, comptime T: type) !msgpack.read_type_help_no_alloc(T) {
                return self.reader.read_no_alloc(T);
            }

            pub fn read_bool(self: MapReader) !bool {
                return self.reader.read_bool();
            }

            pub fn read_int(self: MapReader) !i64 {
                return self.reader.read_int();
            }

            pub fn read_uint(self: MapReader) !u64 {
                return self.reader.read_uint();
            }

            pub fn read_float(self: MapReader) !f64 {
                return self.reader.read_float();
            }

            pub fn read_str(self: MapReader, allocator: Allocator) ![]const u8 {
                return self.reader.read_str(allocator);
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
fn makeResTupleT(errorType: type, resType: type) type {
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
