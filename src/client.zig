const std = @import("std");
const msgpack = @import("msgpack");
const transport = @import("transport/mod.zig");
const connection = @import("connection.zig");
const protocol = @import("protocol/msgpack_rpc.zig");
const payload_utils = @import("protocol/payload_utils.zig");
const builtin = @import("builtin");

/// Keeps track of which concrete transport is currently backing the client.
const TransportKind = enum { none, unix_socket, named_pipe, tcp_socket, stdio, child_process };
const ApiParseError = error{ InvalidFormat, MissingField, OutOfMemory };

/// Represents a single parameter entry exposed by the Neovim API.
pub const ApiParameter = struct {
    type_name: []const u8,
    name: []const u8,
};

/// Metadata describing a callable function exposed by Neovim.
pub const ApiFunction = struct {
    name: []const u8,
    since: u32,
    method: bool,
    return_type: []const u8,
    parameters: []const ApiParameter,
};

/// Captures the semantic version information returned by Neovim.
pub const ApiVersion = struct {
    major: i64,
    minor: i64,
    patch: i64,
    api_level: i64,
    api_compatible: i64,
    api_prerelease: bool,
    prerelease: bool,
    build: ?[]const u8,
};

/// Aggregated API metadata fetched from Neovim at startup.
pub const ApiInfo = struct {
    channel_id: i64,
    version: ApiVersion,
    functions: []const ApiFunction,

    pub fn findFunction(self: ApiInfo, name: []const u8) ?*const ApiFunction {
        for (self.functions, 0..) |_, idx| {
            if (std.mem.eql(u8, self.functions[idx].name, name)) {
                return &self.functions[idx];
            }
        }
        return null;
    }
};

pub const ClientInitError = std.mem.Allocator.Error || error{UnsupportedTransport};

pub const ClientError = ClientInitError || transport.Transport.ReadError || transport.Transport.WriteError || protocol.EncodeError || protocol.DecodeError || error{
    TransportNotInitialized,
    AlreadyConnected,
    NotConnected,
    Unimplemented,
    ConnectionClosed,
    UnexpectedMessage,
    NvimError,
    OutOfMemory,
};

const WindowsState = if (builtin.os.tag == .windows)
    struct { pipe: ?*transport.WindowsPipe = null }
else
    struct {};

/// High-level Neovim RPC client that wraps transports, requests, and API metadata.
pub const Client = struct {
    allocator: std.mem.Allocator,
    options: connection.ConnectionOptions,
    transport_kind: TransportKind = .none,
    transport_unix: ?*transport.UnixSocket = null,
    transport_tcp: ?*transport.TcpSocket = null,
    transport_stdio: ?*transport.Stdio = null,
    transport_child: ?*transport.ChildProcess = null,
    transport: transport.Transport = undefined,
    connected: bool = false,
    next_msgid: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    read_buffer: std.ArrayListUnmanaged(u8) = .{},
    api_arena: std.heap.ArenaAllocator,
    api_info: ?ApiInfo = null,
    windows: WindowsState = .{},

    /// Prepares a client with the requested connection options but does not open the transport yet.
    pub fn init(allocator: std.mem.Allocator, options: connection.ConnectionOptions) ClientInitError!Client {
        var client = Client{
            .allocator = allocator,
            .options = options,
            .api_arena = std.heap.ArenaAllocator.init(allocator),
        };

        try client.setupTransport();
        return client;
    }

    /// Lazily instantiates the transport implementation that matches the supplied options.
    fn setupTransport(self: *Client) ClientInitError!void {
        if (self.transport_kind != .none) {
            return;
        }

        if (self.options.spawn_process) {
            const child_ptr = try self.allocator.create(transport.ChildProcess);
            errdefer self.allocator.destroy(child_ptr);
            child_ptr.* = try transport.ChildProcess.init(self.allocator, self.options);
            self.transport = transport.Transport.init(child_ptr, &transport.ChildProcess.vtable);
            self.transport_child = child_ptr;
            self.transport_kind = .child_process;
            return;
        }

        if (self.options.use_stdio) {
            const stdio_ptr = try self.allocator.create(transport.Stdio);
            errdefer self.allocator.destroy(stdio_ptr);
            stdio_ptr.* = transport.Stdio.init();
            self.transport = transport.Transport.init(stdio_ptr, &transport.Stdio.vtable);
            self.transport_stdio = stdio_ptr;
            self.transport_kind = .stdio;
            return;
        }

        if (self.options.tcp_address) |host| {
            const port = self.options.tcp_port orelse return error.UnsupportedTransport;
            const tcp_ptr = try self.allocator.create(transport.TcpSocket);
            errdefer self.allocator.destroy(tcp_ptr);
            tcp_ptr.* = try transport.TcpSocket.init(self.allocator, host, port);
            self.transport = transport.Transport.init(tcp_ptr, &transport.TcpSocket.vtable);
            self.transport_tcp = tcp_ptr;
            self.transport_kind = .tcp_socket;
            return;
        }

        if (self.options.socket_path) |path| {
            if (builtin.os.tag == .windows) {
                const pipe_ptr = try self.allocator.create(transport.WindowsPipe);
                errdefer self.allocator.destroy(pipe_ptr);

                pipe_ptr.* = transport.WindowsPipe.init(self.allocator);
                self.transport = transport.Transport.init(pipe_ptr, &transport.WindowsPipe.vtable);
                self.transport_kind = .named_pipe;
                self.windows.pipe = pipe_ptr;
                return;
            } else {
                _ = path;
                const unix_ptr = try self.allocator.create(transport.UnixSocket);
                errdefer self.allocator.destroy(unix_ptr);

                unix_ptr.* = transport.UnixSocket.init(self.allocator);
                self.transport = transport.Transport.init(unix_ptr, &transport.UnixSocket.vtable);
                self.transport_unix = unix_ptr;
                self.transport_kind = .unix_socket;
                return;
            }
        }

        return error.UnsupportedTransport;
    }

    pub fn deinit(self: *Client) void {
        self.disconnect();
        self.api_arena.deinit();
        self.read_buffer.deinit(self.allocator);
        switch (self.transport_kind) {
            .unix_socket => if (self.transport_unix) |unix_ptr| {
                unix_ptr.deinit();
                self.allocator.destroy(unix_ptr);
            },
            .named_pipe => if (builtin.os.tag == .windows) {
                if (self.windows.pipe) |pipe_ptr| {
                    pipe_ptr.deinit();
                    self.allocator.destroy(pipe_ptr);
                }
            },
            .tcp_socket => if (self.transport_tcp) |tcp_ptr| {
                tcp_ptr.deinit();
                self.allocator.destroy(tcp_ptr);
            },
            .stdio => if (self.transport_stdio) |stdio_ptr| {
                stdio_ptr.deinit();
                self.allocator.destroy(stdio_ptr);
            },
            .child_process => if (self.transport_child) |child_ptr| {
                child_ptr.deinit();
                self.allocator.destroy(child_ptr);
            },
            .none => {},
        }
        self.transport_unix = null;
        self.transport_tcp = null;
        self.transport_stdio = null;
        self.transport_child = null;
        if (builtin.os.tag == .windows) {
            self.windows.pipe = null;
        }
        self.transport_kind = .none;
    }

    /// Connects the prepared transport and eagerly fetches API metadata unless disabled.
    pub fn connect(self: *Client) ClientError!void {
        if (self.connected) return error.AlreadyConnected;
        switch (self.transport_kind) {
            .unix_socket => {
                const path = self.options.socket_path orelse return error.TransportNotInitialized;
                (&self.transport).connect(path) catch return error.TransportNotInitialized;
            },
            .named_pipe => {
                const path = self.options.socket_path orelse return error.TransportNotInitialized;
                (&self.transport).connect(path) catch return error.TransportNotInitialized;
            },
            .tcp_socket => {
                (&self.transport).connect("") catch return error.TransportNotInitialized;
            },
            .stdio => {
                (&self.transport).connect("") catch return error.TransportNotInitialized;
            },
            .child_process => {
                (&self.transport).connect(self.options.nvim_path) catch return error.TransportNotInitialized;
            },
            .none => return error.TransportNotInitialized,
        }
        self.connected = true;
        self.read_buffer.clearRetainingCapacity();

        if (!self.options.skip_api_info) {
            try self.refreshApiInfo();
        }
    }

    pub fn disconnect(self: *Client) void {
        if (!self.connected) return;
        switch (self.transport_kind) {
            .unix_socket => (&self.transport).disconnect(),
            .named_pipe => (&self.transport).disconnect(),
            .tcp_socket => (&self.transport).disconnect(),
            .stdio => (&self.transport).disconnect(),
            .child_process => (&self.transport).disconnect(),
            .none => {},
        }
        self.connected = false;
        self.read_buffer.clearRetainingCapacity();
        _ = self.api_arena.reset(.free_all);
        self.api_info = null;
    }

    pub fn isConnected(self: *const Client) bool {
        return self.connected and switch (self.transport_kind) {
            .unix_socket => (&self.transport).isConnected(),
            .named_pipe => (&self.transport).isConnected(),
            .tcp_socket => (&self.transport).isConnected(),
            .stdio => (&self.transport).isConnected(),
            .child_process => (&self.transport).isConnected(),
            .none => false,
        };
    }

    pub fn getApiInfo(self: *const Client) ?ApiInfo {
        return self.api_info;
    }

    pub fn findApiFunction(self: *const Client, name: []const u8) ?*const ApiFunction {
        const info = self.api_info orelse return null;
        return info.findFunction(name);
    }

    pub fn refreshApiInfo(self: *Client) ClientError!void {
        const response = try self.request("nvim_get_api_info", &.{});
        defer response.free(self.allocator);
        self.loadApiInfo(response) catch |err| switch (err) {
            ApiParseError.OutOfMemory => return error.OutOfMemory,
            else => return error.NvimError,
        };
    }

    pub fn request(self: *Client, method: []const u8, params: []const msgpack.Payload) ClientError!msgpack.Payload {
        if (!self.connected) return error.NotConnected;

        const msgid = self.nextMessageId();

        // Clone the payloads so the caller keeps ownership of its arguments.
        var params_payload = try msgpack.Payload.arrPayload(params.len, self.allocator);
        defer params_payload.free(self.allocator);
        for (params, 0..) |param, index| {
            params_payload.arr[index] = try payload_utils.clonePayload(self.allocator, param);
        }

        const request_msg = protocol.message.Request{
            .msgid = msgid,
            .method = method,
            .params = params_payload,
        };

        const encoded = try protocol.encodeRequest(self.allocator, request_msg);
        defer self.allocator.free(encoded);

        try (&self.transport).write(encoded);

        return self.awaitResponse(msgid);
    }

    pub fn notify(self: *Client, method: []const u8, params: []const msgpack.Payload) ClientError!void {
        if (!self.connected) return error.NotConnected;

        // Notifications also duplicate params for the same ownership reason as requests.
        var params_payload = try msgpack.Payload.arrPayload(params.len, self.allocator);
        defer params_payload.free(self.allocator);
        for (params, 0..) |param, index| {
            params_payload.arr[index] = try payload_utils.clonePayload(self.allocator, param);
        }

        const notification = protocol.message.Notification{
            .method = method,
            .params = params_payload,
        };

        const encoded = try protocol.encodeNotification(self.allocator, notification);
        defer self.allocator.free(encoded);

        try (&self.transport).write(encoded);
    }

    pub fn nextMessageId(self: *Client) u32 {
        return self.next_msgid.fetchAdd(1, .monotonic);
    }

    /// Reads from the transport until the matching response arrives or the connection closes.
    fn awaitResponse(self: *Client, msgid: u32) ClientError!msgpack.Payload {
        while (true) {
            if (try self.processIncomingMessages(msgid)) |result| {
                return result;
            }

            var buffer: [4096]u8 = undefined;
            const read_bytes = (&self.transport).read(buffer[0..]) catch |err| {
                if (err == transport.Transport.ReadError.ConnectionClosed) {
                    self.connected = false;
                    return error.ConnectionClosed;
                }
                return err;
            };

            if (read_bytes == 0) {
                self.connected = false;
                return error.ConnectionClosed;
            }

            try self.read_buffer.appendSlice(self.allocator, buffer[0..read_bytes]);
        }
    }

    /// Decodes buffered messages and returns a response when it matches the awaited id.
    fn processIncomingMessages(self: *Client, expected_msgid: u32) ClientError!?msgpack.Payload {
        while (true) {
            const decoded_opt = try self.tryDecodeMessage();
            if (decoded_opt == null) return null;

            var decoded = decoded_opt.?;
            defer protocol.message.deinitMessage(&decoded.message, self.allocator);

            switch (decoded.message) {
                .Response => |resp| {
                    if (resp.msgid != expected_msgid) {
                        return error.UnexpectedMessage;
                    }

                    if (resp.@"error") |_| {
                        return error.NvimError;
                    }

                    if (resp.result) |res_payload| {
                        const cloned = try payload_utils.clonePayload(self.allocator, res_payload);
                        return cloned;
                    }

                    return msgpack.Payload.nilToPayload();
                },
                .Notification => {
                    continue;
                },
                .Request => {
                    return error.UnexpectedMessage;
                },
            }
        }
    }

    /// Attempts to parse a message from the accumulated read buffer, leaving partial data intact.
    fn tryDecodeMessage(self: *Client) ClientError!?protocol.decoder.DecodeResult {
        if (self.read_buffer.items.len == 0) return null;

        const decode_res = protocol.decode(self.allocator, self.read_buffer.items) catch |err| switch (err) {
            msgpack.MsGPackError.LENGTH_READING => return null,
            else => return err,
        };

        try self.read_buffer.replaceRange(self.allocator, 0, decode_res.bytes_read, &.{});
        return decode_res;
    }

    /// Rebuilds the cached API metadata from the payload returned by `nvim_get_api_info`.
    fn loadApiInfo(self: *Client, payload: msgpack.Payload) ApiParseError!void {
        _ = self.api_arena.reset(.free_all);
        const arena = self.api_arena.allocator();

        const root_arr = switch (payload) {
            .arr => payload.arr,
            else => return ApiParseError.InvalidFormat,
        };
        if (root_arr.len < 2) return ApiParseError.InvalidFormat;

        const channel_id = try payloadToI64(root_arr[0]);
        const metadata_payload = root_arr[1];

        const metadata_map = switch (metadata_payload) {
            .map => metadata_payload,
            else => return ApiParseError.InvalidFormat,
        };

        const version_payload = try mapGetRequired(metadata_map, "version");
        const functions_payload = try mapGetRequired(metadata_map, "functions");

        const version = try parseVersion(arena, version_payload);
        const functions = try parseFunctions(arena, functions_payload);

        self.api_info = ApiInfo{
            .channel_id = channel_id,
            .version = version,
            .functions = functions,
        };
    }
};

test "next message id increments" {
    var client = try Client.init(std.testing.allocator, .{ .socket_path = "/tmp/nvim.sock" });
    defer client.deinit();

    try std.testing.expectEqual(@as(u32, 0), client.nextMessageId());
    try std.testing.expectEqual(@as(u32, 1), client.nextMessageId());
}

fn payloadToI64(payload: msgpack.Payload) ApiParseError!i64 {
    return switch (payload) {
        .int => payload.int,
        .uint => |v| std.math.cast(i64, v) orelse return ApiParseError.InvalidFormat,
        else => ApiParseError.InvalidFormat,
    };
}

fn payloadToU32(payload: msgpack.Payload) ApiParseError!u32 {
    const value = try payloadToI64(payload);
    return std.math.cast(u32, value) orelse ApiParseError.InvalidFormat;
}

fn payloadToBool(payload: msgpack.Payload) ApiParseError!bool {
    return switch (payload) {
        .bool => payload.bool,
        else => ApiParseError.InvalidFormat,
    };
}

fn payloadToString(arena: std.mem.Allocator, payload: msgpack.Payload) ApiParseError![]const u8 {
    return switch (payload) {
        .str => |s| arena.dupe(u8, s.value()) catch ApiParseError.OutOfMemory,
        else => ApiParseError.InvalidFormat,
    };
}

fn mapGetOptional(map: msgpack.Payload, key: []const u8) ApiParseError!?msgpack.Payload {
    return map.mapGet(key) catch return ApiParseError.InvalidFormat;
}

fn mapGetRequired(map: msgpack.Payload, key: []const u8) ApiParseError!msgpack.Payload {
    const maybe = try mapGetOptional(map, key);
    return maybe orelse ApiParseError.MissingField;
}

/// Extracts the version block from the API metadata map, copying owned strings into the arena.
fn parseVersion(arena: std.mem.Allocator, payload: msgpack.Payload) ApiParseError!ApiVersion {
    const version_map = switch (payload) {
        .map => payload,
        else => return ApiParseError.InvalidFormat,
    };

    const major = try payloadToI64(try mapGetRequired(version_map, "major"));
    const minor = try payloadToI64(try mapGetRequired(version_map, "minor"));
    const patch = try payloadToI64(try mapGetRequired(version_map, "patch"));
    const api_level = try payloadToI64(try mapGetRequired(version_map, "api_level"));
    const api_compatible = try payloadToI64(try mapGetRequired(version_map, "api_compatible"));

    const api_prerelease = if (try mapGetOptional(version_map, "api_prerelease")) |value|
        try payloadToBool(value)
    else
        false;

    const prerelease = if (try mapGetOptional(version_map, "prerelease")) |value|
        try payloadToBool(value)
    else
        false;

    const build = if (try mapGetOptional(version_map, "build")) |value|
        try payloadToString(arena, value)
    else
        null;

    return ApiVersion{
        .major = major,
        .minor = minor,
        .patch = patch,
        .api_level = api_level,
        .api_compatible = api_compatible,
        .api_prerelease = api_prerelease,
        .prerelease = prerelease,
        .build = build,
    };
}

/// Parses and arena-allocates the array of API function descriptors.
fn parseFunctions(arena: std.mem.Allocator, payload: msgpack.Payload) ApiParseError![]const ApiFunction {
    const fn_arr = switch (payload) {
        .arr => payload.arr,
        else => return ApiParseError.InvalidFormat,
    };

    const functions = arena.alloc(ApiFunction, fn_arr.len) catch return ApiParseError.OutOfMemory;
    for (fn_arr, 0..) |function_payload, idx| {
        functions[idx] = try parseFunction(arena, function_payload);
    }

    return functions;
}

fn parseFunction(arena: std.mem.Allocator, payload: msgpack.Payload) ApiParseError!ApiFunction {
    const fn_map = switch (payload) {
        .map => payload,
        else => return ApiParseError.InvalidFormat,
    };

    const name = try payloadToString(arena, try mapGetRequired(fn_map, "name"));
    const return_type = try payloadToString(arena, try mapGetRequired(fn_map, "return_type"));
    const since = try payloadToU32(try mapGetRequired(fn_map, "since"));
    const method = try payloadToBool(try mapGetRequired(fn_map, "method"));
    const params_payload = try mapGetRequired(fn_map, "parameters");
    const params_arr = switch (params_payload) {
        .arr => params_payload.arr,
        else => return ApiParseError.InvalidFormat,
    };

    const parameters = arena.alloc(ApiParameter, params_arr.len) catch return ApiParseError.OutOfMemory;
    for (params_arr, 0..) |param_entry, idx| {
        const entry_arr = switch (param_entry) {
            .arr => param_entry.arr,
            else => return ApiParseError.InvalidFormat,
        };
        if (entry_arr.len < 2) return ApiParseError.InvalidFormat;
        parameters[idx] = ApiParameter{
            .type_name = try payloadToString(arena, entry_arr[0]),
            .name = try payloadToString(arena, entry_arr[1]),
        };
    }

    return ApiFunction{
        .name = name,
        .since = since,
        .method = method,
        .return_type = return_type,
        .parameters = parameters,
    };
}

const TestTransport = struct {
    allocator: std.mem.Allocator,
    written: std.ArrayListUnmanaged(u8),
    read_data: []u8,
    read_offset: usize = 0,
    connected: bool = true,

    fn init(allocator: std.mem.Allocator, data: []const u8) !TestTransport {
        const copy = try allocator.alloc(u8, data.len);
        @memcpy(copy, data);
        return TestTransport{
            .allocator = allocator,
            .written = .{},
            .read_data = copy,
        };
    }

    fn deinit(self: *TestTransport) void {
        self.written.deinit(self.allocator);
        self.allocator.free(self.read_data);
    }

    fn connect(tr: *transport.Transport, _: []const u8) anyerror!void {
        const self = tr.downcast(TestTransport);
        self.connected = true;
    }

    fn disconnect(tr: *transport.Transport) void {
        const self = tr.downcast(TestTransport);
        self.connected = false;
    }

    fn read(tr: *transport.Transport, buffer: []u8) transport.Transport.ReadError!usize {
        const self = tr.downcast(TestTransport);
        if (self.read_offset >= self.read_data.len) return 0;
        const remaining = self.read_data.len - self.read_offset;
        const amount = @min(buffer.len, remaining);
        @memcpy(buffer[0..amount], self.read_data[self.read_offset .. self.read_offset + amount]);
        self.read_offset += amount;
        return amount;
    }

    fn write(tr: *transport.Transport, data: []const u8) transport.Transport.WriteError!void {
        const self = tr.downcast(TestTransport);
        self.written.appendSlice(self.allocator, data) catch return transport.Transport.WriteError.UnexpectedError;
    }

    fn isConnected(tr: *transport.Transport) bool {
        const self = tr.downcastConst(TestTransport);
        return self.connected;
    }

    pub const vtable = transport.Transport.VTable{
        .connect = connect,
        .disconnect = disconnect,
        .read = read,
        .write = write,
        .is_connected = isConnected,
    };
};

fn buildSampleApiInfoPayload(allocator: std.mem.Allocator) !msgpack.Payload {
    var root = try msgpack.Payload.arrPayload(2, allocator);
    errdefer root.free(allocator);

    root.arr[0] = msgpack.Payload.intToPayload(3);

    var metadata = msgpack.Payload.mapPayload(allocator);
    errdefer metadata.free(allocator);

    var version = msgpack.Payload.mapPayload(allocator);
    errdefer version.free(allocator);
    try version.mapPut("major", msgpack.Payload.intToPayload(0));
    try version.mapPut("minor", msgpack.Payload.intToPayload(9));
    try version.mapPut("patch", msgpack.Payload.intToPayload(1));
    try version.mapPut("api_level", msgpack.Payload.intToPayload(12));
    try version.mapPut("api_compatible", msgpack.Payload.intToPayload(0));
    try version.mapPut("api_prerelease", msgpack.Payload.boolToPayload(true));
    try version.mapPut("prerelease", msgpack.Payload.boolToPayload(false));
    try version.mapPut("build", try msgpack.Payload.strToPayload("nightly", allocator));
    try metadata.mapPut("version", version);

    var functions = try msgpack.Payload.arrPayload(1, allocator);
    errdefer functions.free(allocator);

    var function_entry = msgpack.Payload.mapPayload(allocator);
    errdefer function_entry.free(allocator);
    try function_entry.mapPut("name", try msgpack.Payload.strToPayload("sample_fn", allocator));
    try function_entry.mapPut("return_type", try msgpack.Payload.strToPayload("String", allocator));
    try function_entry.mapPut("since", msgpack.Payload.intToPayload(1));
    try function_entry.mapPut("method", msgpack.Payload.boolToPayload(false));

    var params = try msgpack.Payload.arrPayload(2, allocator);
    errdefer params.free(allocator);

    var param0 = try msgpack.Payload.arrPayload(2, allocator);
    param0.arr[0] = try msgpack.Payload.strToPayload("Integer", allocator);
    param0.arr[1] = try msgpack.Payload.strToPayload("param1", allocator);
    params.arr[0] = param0;

    var param1 = try msgpack.Payload.arrPayload(2, allocator);
    param1.arr[0] = try msgpack.Payload.strToPayload("String", allocator);
    param1.arr[1] = try msgpack.Payload.strToPayload("param2", allocator);
    params.arr[1] = param1;

    try function_entry.mapPut("parameters", params);
    functions.arr[0] = function_entry;
    try metadata.mapPut("functions", functions);

    root.arr[1] = metadata;
    return root;
}

test "parseVersion extracts fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = std.testing.allocator;

    var version_payload = msgpack.Payload.mapPayload(allocator);
    defer version_payload.free(allocator);
    try version_payload.mapPut("major", msgpack.Payload.intToPayload(1));
    try version_payload.mapPut("minor", msgpack.Payload.intToPayload(2));
    try version_payload.mapPut("patch", msgpack.Payload.intToPayload(3));
    try version_payload.mapPut("api_level", msgpack.Payload.intToPayload(10));
    try version_payload.mapPut("api_compatible", msgpack.Payload.intToPayload(9));
    try version_payload.mapPut("api_prerelease", msgpack.Payload.boolToPayload(false));
    try version_payload.mapPut("prerelease", msgpack.Payload.boolToPayload(true));

    const version = try parseVersion(arena.allocator(), version_payload);
    try std.testing.expectEqual(@as(i64, 1), version.major);
    try std.testing.expectEqual(@as(i64, 2), version.minor);
    try std.testing.expect(version.build == null);
}

test "parseFunction missing parameters returns error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = std.testing.allocator;

    var fn_map = msgpack.Payload.mapPayload(allocator);
    defer fn_map.free(allocator);
    try fn_map.mapPut("name", try msgpack.Payload.strToPayload("foo", allocator));
    try fn_map.mapPut("return_type", try msgpack.Payload.strToPayload("void", allocator));
    try fn_map.mapPut("since", msgpack.Payload.intToPayload(0));
    try fn_map.mapPut("method", msgpack.Payload.boolToPayload(false));

    try std.testing.expectError(ApiParseError.MissingField, parseFunction(arena.allocator(), fn_map));
}

test "refreshApiInfo loads metadata" {
    const allocator = std.testing.allocator;
    var api_payload = try buildSampleApiInfoPayload(allocator);
    defer api_payload.free(allocator);

    const cloned = try payload_utils.clonePayload(allocator, api_payload);
    var response_msg = protocol.message.Response{
        .msgid = 0,
        .result = cloned,
    };
    const encoded_response = try protocol.encodeResponse(allocator, response_msg);
    defer allocator.free(encoded_response);
    if (response_msg.result) |*res| res.*.free(allocator);

    var test_transport = try TestTransport.init(allocator, encoded_response);
    defer test_transport.deinit();

    var client = Client{
        .allocator = allocator,
        .options = .{},
        .transport_kind = .unix_socket,
        .transport_unix = null,
        .transport = transport.Transport.init(&test_transport, &TestTransport.vtable),
        .connected = true,
        .next_msgid = std.atomic.Value(u32).init(0),
        .read_buffer = .{},
        .api_arena = std.heap.ArenaAllocator.init(allocator),
        .api_info = null,
    };
    defer client.deinit();

    try client.refreshApiInfo();

    const info = client.getApiInfo() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(i64, 3), info.channel_id);
    try std.testing.expectEqual(@as(i64, 0), info.version.major);
    try std.testing.expect(info.version.build != null);
    try std.testing.expectEqualStrings("nightly", info.version.build.?);
    try std.testing.expectEqual(@as(usize, 1), info.functions.len);
    try std.testing.expectEqualStrings("sample_fn", info.functions[0].name);
    try std.testing.expectEqual(@as(usize, 2), info.functions[0].parameters.len);
    try std.testing.expectEqualStrings("param1", info.functions[0].parameters[0].name);

    var decoded_req = try protocol.decode(allocator, test_transport.written.items);
    defer protocol.message.deinitMessage(&decoded_req.message, allocator);
    try std.testing.expectEqual(decoded_req.bytes_read, test_transport.written.items.len);
    switch (decoded_req.message) {
        .Request => |req| {
            try std.testing.expectEqualStrings("nvim_get_api_info", req.method);
            const params_len = try req.params.getArrLen();
            try std.testing.expectEqual(@as(usize, 0), params_len);
        },
        else => return error.TestExpectedEqual,
    }
}
