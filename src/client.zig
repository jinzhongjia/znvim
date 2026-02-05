const std = @import("std");
const msgpack = @import("msgpack");
const zio = @import("zio");
const connection = @import("connection.zig");
const protocol = @import("protocol/msgpack_rpc.zig");
const payload_utils = @import("protocol/payload_utils.zig");
const zio_transport = @import("zio_transport.zig");
const builtin = @import("builtin");

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

pub const ClientError = ClientInitError || protocol.EncodeError || protocol.DecodeError || error{
    TransportNotInitialized,
    AlreadyConnected,
    NotConnected,
    Unimplemented,
    ConnectionClosed,
    UnexpectedMessage,
    NvimError,
    OutOfMemory,
    Timeout,
};

// ============================================================================
// Async Support Types
// ============================================================================

/// Completion handle for pending requests in async mode.
/// Used to signal when a response arrives for a specific request.
pub const PendingRequest = struct {
    /// Signaled when response arrives
    event: std.Thread.ResetEvent = .{},
    /// Response payload (set by reader task)
    result: ?msgpack.Payload = null,
    /// Error if request failed
    err: ?anyerror = null,
    /// Allocator for cleanup
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PendingRequest {
        return .{ .allocator = allocator };
    }

    /// Wait for the response (blocks the calling thread).
    pub fn wait(self: *PendingRequest) !msgpack.Payload {
        self.event.wait();
        if (self.err) |e| return e;
        return self.result orelse error.NoResult;
    }

    /// Complete the request with a successful result.
    pub fn complete(self: *PendingRequest, result: msgpack.Payload) void {
        self.result = result;
        self.event.set();
    }

    /// Fail the request with an error.
    pub fn fail(self: *PendingRequest, err: anyerror) void {
        self.err = err;
        self.event.set();
    }

    /// Reset for reuse.
    pub fn reset(self: *PendingRequest) void {
        self.event.reset();
        self.result = null;
        self.err = null;
    }
};

/// Event handler callback type for notifications.
///
/// IMPORTANT: The `params` payload is only valid for the duration of the handler call.
/// If you need to store the payload for later use, you MUST clone it using your own allocator.
pub const EventHandler = *const fn (
    method: []const u8,
    params: msgpack.Payload,
    userdata: ?*anyopaque,
) void;

/// High-level Neovim RPC client using zio-based async I/O.
pub const Client = struct {
    allocator: std.mem.Allocator,
    options: connection.ConnectionOptions,

    // ===== ZIO Runtime Management =====
    /// The active zio runtime (owned or external)
    zio_runtime: ?*zio.Runtime = null,
    /// Whether we own the runtime (and need to deinit it)
    owns_runtime: bool = false,
    /// Signal to stop runtime thread
    shutdown: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    // ===== Connection State =====
    /// zio network stream (for socket-based connections)
    zio_stream: ?zio.net.Stream = null,
    /// Child process connection (for spawn_process mode)
    child_conn: ?zio_transport.ChildProcessConnection = null,
    /// Stdio connection (for use_stdio mode)
    stdio_conn: ?zio_transport.StdioConnection = null,

    // ===== Common State =====
    connected: bool = false,
    next_msgid: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    read_buffer: std.ArrayListUnmanaged(u8) = .{},
    api_arena: std.heap.ArenaAllocator,
    api_info: ?ApiInfo = null,

    // ===== Request/Response Management =====
    /// Mutex to protect concurrent request/response handling
    mutex: std.Thread.Mutex = .{},
    /// Map of msgid -> pending request completion (for async mode)
    pending: std.AutoHashMapUnmanaged(u32, *PendingRequest) = .{},

    // ===== Event Handling =====
    event_handler: ?EventHandler = null,
    event_userdata: ?*anyopaque = null,

    /// Prepares a client with the requested connection options but does not open the connection yet.
    pub fn init(allocator: std.mem.Allocator, options: connection.ConnectionOptions) ClientInitError!Client {
        return Client{
            .allocator = allocator,
            .options = options,
            .api_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *Client) void {
        self.disconnect();
        self.api_arena.deinit();
        self.read_buffer.deinit(self.allocator);

        // Clean up pending requests
        var pending_iter = self.pending.iterator();
        while (pending_iter.next()) |entry| {
            entry.value_ptr.*.fail(error.ConnectionClosed);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.pending.deinit(self.allocator);

        // Clean up zio resources
        self.cleanupZioResources();
    }

    /// Clean up zio-specific resources
    fn cleanupZioResources(self: *Client) void {
        self.shutdown.store(true, .release);

        if (self.zio_stream) |stream| {
            if (self.zio_runtime) |rt| {
                stream.close(rt);
            }
            self.zio_stream = null;
        }

        if (self.child_conn) |*conn| {
            conn.close();
            self.child_conn = null;
        }

        if (self.stdio_conn) |*conn| {
            conn.close();
            self.stdio_conn = null;
        }

        if (self.owns_runtime) {
            if (self.zio_runtime) |rt| {
                rt.deinit();
            }
            self.owns_runtime = false;
        }

        self.zio_runtime = null;
    }

    // =========================================================================
    // ZIO Runtime Management
    // =========================================================================

    /// Ensure the zio runtime is initialized and running.
    fn ensureZioRuntime(self: *Client) !void {
        if (self.zio_runtime != null) return;

        switch (self.options.runtime_mode) {
            .external => {
                self.zio_runtime = self.options.zio_runtime orelse return error.TransportNotInitialized;
                self.owns_runtime = false;
            },
            .owned_background_thread => {
                self.zio_runtime = zio.Runtime.init(self.allocator, .{}) catch return error.OutOfMemory;
                self.owns_runtime = true;
                self.shutdown.store(false, .release);
            },
        }
    }

    // =========================================================================
    // Connection Methods
    // =========================================================================

    /// Connects to Neovim and eagerly fetches API metadata unless disabled.
    pub fn connect(self: *Client) ClientError!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.connected) return error.AlreadyConnected;

        // Connect based on options (in priority order)
        if (self.options.spawn_process) {
            // Child process: use std.process spawn + pipe I/O
            self.child_conn = zio_transport.spawnChildProcess(self.allocator, self.options.nvim_path) catch
                return error.TransportNotInitialized;
        } else if (self.options.use_stdio) {
            // Stdio: use stdin/stdout
            self.stdio_conn = zio_transport.StdioConnection.init();
        } else if (self.options.tcp_address) |host| {
            // TCP: use zio network stream
            try self.ensureZioRuntime();
            const rt = self.zio_runtime orelse return error.TransportNotInitialized;
            const port = self.options.tcp_port orelse return error.UnsupportedTransport;
            const conn = zio_transport.connectTcp(rt, host, port) catch
                return error.TransportNotInitialized;
            self.zio_stream = conn.stream;
        } else if (self.options.socket_path) |path| {
            // Unix socket: use zio network stream
            if (comptime zio.net.has_unix_sockets) {
                try self.ensureZioRuntime();
                const rt = self.zio_runtime orelse return error.TransportNotInitialized;
                const conn = zio_transport.connectUnixSocket(rt, path) catch
                    return error.TransportNotInitialized;
                self.zio_stream = conn.stream;
            } else {
                // Windows named pipe - not yet supported
                return error.UnsupportedTransport;
            }
        } else {
            return error.UnsupportedTransport;
        }

        self.connected = true;
        self.read_buffer.clearRetainingCapacity();

        if (!self.options.skip_api_info) {
            try self.refreshApiInfo();
        }
    }

    pub fn disconnect(self: *Client) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.connected) return;

        if (self.zio_stream) |stream| {
            if (self.zio_runtime) |rt| {
                stream.close(rt);
            }
            self.zio_stream = null;
        }

        if (self.child_conn) |*conn| {
            conn.close();
            self.child_conn = null;
        }

        if (self.stdio_conn) |*conn| {
            conn.close();
            self.stdio_conn = null;
        }

        self.connected = false;
        self.read_buffer.clearRetainingCapacity();
        _ = self.api_arena.reset(.free_all);
        self.api_info = null;
    }

    pub fn isConnected(self: *const Client) bool {
        if (!self.connected) return false;
        return self.zio_stream != null or self.child_conn != null or self.stdio_conn != null;
    }

    // =========================================================================
    // Message I/O
    // =========================================================================

    /// Read data from the connection into the read buffer.
    fn readFromConnection(self: *Client, buffer: []u8) !usize {
        if (self.zio_stream) |stream| {
            const rt = self.zio_runtime orelse return error.NotConnected;
            return stream.read(rt, buffer, .none) catch |err| {
                std.log.err("zio stream read error: {}", .{err});
                return error.ConnectionClosed;
            };
        } else if (self.child_conn) |*conn| {
            return conn.read(buffer) catch |err| {
                std.log.err("child process read error: {}", .{err});
                return error.ConnectionClosed;
            };
        } else if (self.stdio_conn) |*conn| {
            return conn.read(buffer) catch |err| {
                std.log.err("stdio read error: {}", .{err});
                return error.ConnectionClosed;
            };
        }
        return error.NotConnected;
    }

    /// Write data to the connection.
    fn writeToConnection(self: *Client, data: []const u8) !void {
        if (self.zio_stream) |stream| {
            const rt = self.zio_runtime orelse return error.NotConnected;
            stream.writeAll(rt, data, .none) catch |err| {
                std.log.err("zio stream write error: {}", .{err});
                return error.ConnectionClosed;
            };
        } else if (self.child_conn) |*conn| {
            conn.writeAll(data) catch |err| {
                std.log.err("child process write error: {}", .{err});
                return error.ConnectionClosed;
            };
        } else if (self.stdio_conn) |*conn| {
            conn.writeAll(data) catch |err| {
                std.log.err("stdio write error: {}", .{err});
                return error.ConnectionClosed;
            };
        } else {
            return error.NotConnected;
        }
    }

    /// Wait for a response with the given msgid.
    fn awaitResponse(self: *Client, msgid: u32) ClientError!msgpack.Payload {
        while (true) {
            if (try self.processIncomingMessages(msgid)) |result| {
                return result;
            }

            var buffer: [4096]u8 = undefined;
            const read_bytes = self.readFromConnection(buffer[0..]) catch {
                self.connected = false;
                return error.ConnectionClosed;
            };

            if (read_bytes == 0) {
                self.connected = false;
                return error.ConnectionClosed;
            }

            try self.read_buffer.appendSlice(self.allocator, buffer[0..read_bytes]);
        }
    }

    /// Process incoming messages from the buffer and dispatch responses.
    fn processIncomingMessages(self: *Client, expected_msgid: u32) ClientError!?msgpack.Payload {
        while (true) {
            const decoded_opt = try self.tryDecodeMessage();
            if (decoded_opt == null) {
                return null;
            }

            var decoded = decoded_opt.?;
            defer protocol.message.deinitMessage(&decoded.message, self.allocator);

            switch (decoded.message) {
                .Response => |resp| {
                    if (resp.msgid == expected_msgid) {
                        if (resp.@"error") |_| {
                            return error.NvimError;
                        }

                        if (resp.result) |res_payload| {
                            const cloned = try payload_utils.clonePayload(self.allocator, res_payload);
                            return cloned;
                        }

                        return msgpack.Payload.nilToPayload();
                    }

                    // Check if there's a pending request for this msgid
                    if (self.pending.get(resp.msgid)) |pending| {
                        if (resp.@"error") |_| {
                            pending.fail(error.NvimError);
                        } else if (resp.result) |res_payload| {
                            const cloned = payload_utils.clonePayload(self.allocator, res_payload) catch {
                                pending.fail(error.OutOfMemory);
                                continue;
                            };
                            pending.complete(cloned);
                        } else {
                            pending.complete(msgpack.Payload.nilToPayload());
                        }
                        _ = self.pending.remove(resp.msgid);
                        continue;
                    }

                    std.log.warn("Received response for unknown msgid: {}", .{resp.msgid});
                    continue;
                },
                .Notification => |notif| {
                    if (self.event_handler) |handler| {
                        handler(notif.method, notif.params, self.event_userdata);
                    }
                    continue;
                },
                .Request => {
                    std.log.warn("Received unexpected server request", .{});
                    continue;
                },
            }
        }
    }

    /// Attempts to parse a message from the accumulated read buffer.
    fn tryDecodeMessage(self: *Client) ClientError!?protocol.decoder.DecodeResult {
        if (self.read_buffer.items.len == 0) return null;

        const decode_res = protocol.decode(self.allocator, self.read_buffer.items) catch |err| switch (err) {
            msgpack.MsgPackError.LengthReading => return null,
            else => return err,
        };

        try self.read_buffer.replaceRange(self.allocator, 0, decode_res.bytes_read, &.{});
        return decode_res;
    }

    // =========================================================================
    // Request/Response API
    // =========================================================================

    pub fn request(self: *Client, method: []const u8, params: []const msgpack.Payload) ClientError!msgpack.Payload {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.requestLocked(method, params);
    }

    /// Internal request implementation without locking (assumes caller holds lock)
    fn requestLocked(self: *Client, method: []const u8, params: []const msgpack.Payload) ClientError!msgpack.Payload {
        if (!self.connected) return error.NotConnected;

        const msgid = self.nextMessageId();

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

        try self.writeToConnection(encoded);

        return self.awaitResponse(msgid);
    }

    pub fn notify(self: *Client, method: []const u8, params: []const msgpack.Payload) ClientError!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.connected) return error.NotConnected;

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

        try self.writeToConnection(encoded);
    }

    /// Set event handler for receiving notifications from Neovim.
    pub fn setEventHandler(self: *Client, handler: ?EventHandler, userdata: ?*anyopaque) void {
        self.event_handler = handler;
        self.event_userdata = userdata;
    }

    pub fn nextMessageId(self: *Client) u32 {
        return self.next_msgid.fetchAdd(1, .monotonic);
    }

    // =========================================================================
    // Async API (for callers already inside zio fiber)
    // =========================================================================

    /// Async request task that can be awaited.
    pub const RequestTask = struct {
        client: *Client,
        pending: *PendingRequest,
        msgid: u32,

        pub fn wait(self: RequestTask) !msgpack.Payload {
            return self.pending.wait();
        }

        pub fn cancel(self: RequestTask) void {
            self.client.mutex.lock();
            defer self.client.mutex.unlock();

            if (self.client.pending.get(self.msgid)) |_| {
                _ = self.client.pending.remove(self.msgid);
                self.pending.fail(error.Canceled);
            }
        }
    };

    /// Send a request asynchronously and return a task that can be awaited.
    pub fn requestAsync(self: *Client, method: []const u8, params: []const msgpack.Payload) !RequestTask {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.connected) return error.NotConnected;

        const msgid = self.nextMessageId();

        const pending = try self.allocator.create(PendingRequest);
        errdefer self.allocator.destroy(pending);
        pending.* = PendingRequest.init(self.allocator);

        try self.pending.put(self.allocator, msgid, pending);
        errdefer _ = self.pending.remove(msgid);

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

        try self.writeToConnection(encoded);

        return RequestTask{
            .client = self,
            .pending = pending,
            .msgid = msgid,
        };
    }

    // =========================================================================
    // API Metadata
    // =========================================================================

    pub fn getApiInfo(self: *const Client) ?ApiInfo {
        return self.api_info;
    }

    pub fn findApiFunction(self: *const Client, name: []const u8) ?*const ApiFunction {
        const info = self.api_info orelse return null;
        return info.findFunction(name);
    }

    pub fn refreshApiInfo(self: *Client) ClientError!void {
        const response = try self.requestLocked("nvim_get_api_info", &.{});
        defer response.free(self.allocator);
        self.loadApiInfo(response) catch |err| switch (err) {
            ApiParseError.OutOfMemory => return error.OutOfMemory,
            else => return error.NvimError,
        };
    }

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

// ============================================================================
// Helper Functions
// ============================================================================

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

fn mapGetRequired(map: msgpack.Payload, key: []const u8) ApiParseError!msgpack.Payload {
    return switch (map) {
        .map => |m| m.get(key) orelse ApiParseError.MissingField,
        else => ApiParseError.InvalidFormat,
    };
}

fn mapGetOptional(map: msgpack.Payload, key: []const u8) ?msgpack.Payload {
    return switch (map) {
        .map => |m| m.get(key),
        else => null,
    };
}

fn parseVersion(arena: std.mem.Allocator, version_payload: msgpack.Payload) ApiParseError!ApiVersion {
    return ApiVersion{
        .major = try payloadToI64(try mapGetRequired(version_payload, "major")),
        .minor = try payloadToI64(try mapGetRequired(version_payload, "minor")),
        .patch = try payloadToI64(try mapGetRequired(version_payload, "patch")),
        .api_level = try payloadToI64(try mapGetRequired(version_payload, "api_level")),
        .api_compatible = try payloadToI64(try mapGetRequired(version_payload, "api_compatible")),
        .api_prerelease = try payloadToBool(try mapGetRequired(version_payload, "api_prerelease")),
        .prerelease = mapGetOptional(version_payload, "prerelease") != null and
            (try payloadToBool(mapGetOptional(version_payload, "prerelease").?)),
        .build = if (mapGetOptional(version_payload, "build")) |b|
            (payloadToString(arena, b) catch null)
        else
            null,
    };
}

fn parseFunctions(arena: std.mem.Allocator, functions_payload: msgpack.Payload) ApiParseError![]const ApiFunction {
    const funcs_arr = switch (functions_payload) {
        .arr => functions_payload.arr,
        else => return ApiParseError.InvalidFormat,
    };

    var functions = arena.alloc(ApiFunction, funcs_arr.len) catch return ApiParseError.OutOfMemory;
    for (funcs_arr, 0..) |func_payload, i| {
        functions[i] = try parseSingleFunction(arena, func_payload);
    }
    return functions;
}

fn parseSingleFunction(arena: std.mem.Allocator, func_payload: msgpack.Payload) ApiParseError!ApiFunction {
    const name = try payloadToString(arena, try mapGetRequired(func_payload, "name"));
    const since = try payloadToU32(try mapGetRequired(func_payload, "since"));
    const method = try payloadToBool(try mapGetRequired(func_payload, "method"));
    const return_type = try payloadToString(arena, try mapGetRequired(func_payload, "return_type"));

    const params_payload = try mapGetRequired(func_payload, "parameters");
    const params_arr = switch (params_payload) {
        .arr => params_payload.arr,
        else => return ApiParseError.InvalidFormat,
    };

    var parameters = arena.alloc(ApiParameter, params_arr.len) catch return ApiParseError.OutOfMemory;
    for (params_arr, 0..) |param_payload, i| {
        parameters[i] = try parseParameter(arena, param_payload);
    }

    return ApiFunction{
        .name = name,
        .since = since,
        .method = method,
        .return_type = return_type,
        .parameters = parameters,
    };
}

fn parseParameter(arena: std.mem.Allocator, param_payload: msgpack.Payload) ApiParseError!ApiParameter {
    const param_arr = switch (param_payload) {
        .arr => param_payload.arr,
        else => return ApiParseError.InvalidFormat,
    };
    if (param_arr.len < 2) return ApiParseError.InvalidFormat;

    return ApiParameter{
        .type_name = try payloadToString(arena, param_arr[0]),
        .name = try payloadToString(arena, param_arr[1]),
    };
}

// ============================================================================
// Tests
// ============================================================================

test "next message id increments" {
    var client = try Client.init(std.testing.allocator, .{ .socket_path = "/tmp/nvim.sock" });
    defer client.deinit();

    try std.testing.expectEqual(@as(u32, 0), client.nextMessageId());
    try std.testing.expectEqual(@as(u32, 1), client.nextMessageId());
}
