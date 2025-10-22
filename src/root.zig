//! znvim - A Zig library for communicating with Neovim
//! Provides MessagePack-RPC helpers, transports, and runtime API metadata.

const std = @import("std");
const client_mod = @import("client.zig");
const connection_mod = @import("connection.zig");
const protocol_mod = @import("protocol/mod.zig");
const transport_mod = @import("transport/mod.zig");

pub const Client = client_mod.Client;
pub const ClientError = client_mod.ClientError;
pub const ClientInitError = client_mod.ClientInitError;

pub const ApiInfo = client_mod.ApiInfo;
pub const ApiVersion = client_mod.ApiVersion;
pub const ApiFunction = client_mod.ApiFunction;
pub const ApiParameter = client_mod.ApiParameter;

pub const ConnectionOptions = connection_mod.ConnectionOptions;

pub const transport = transport_mod;
pub const protocol = protocol_mod;
pub const msgpack = @import("msgpack.zig");

pub const Request = protocol_mod.message.Request;
pub const Response = protocol_mod.message.Response;
pub const Notification = protocol_mod.message.Notification;
pub const AnyMessage = protocol_mod.message.AnyMessage;

pub const msgpack_rpc = protocol_mod.msgpack_rpc;

pub fn connect(allocator: std.mem.Allocator, options: ConnectionOptions) !Client {
    var client = try Client.init(allocator, options);
    errdefer client.deinit();
    try client.connect();
    return client;
}

test "client module tests" {
    _ = @import("client.zig");
}

test "transport module tests" {
    _ = @import("tests/transport_tests.zig");
}

test "msgpack module tests" {
    _ = @import("tests/msgpack_tests.zig");
}

test "transport unit tests" {
    _ = @import("tests/transport_unit_tests.zig");
}

test "connection module tests" {
    _ = @import("tests/connection_tests.zig");
}

test "protocol unit tests" {
    _ = @import("tests/protocol_unit_tests.zig");
}

test "memory leak tests" {
    _ = @import("tests/memory_leak_test.zig");
}
