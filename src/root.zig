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

test "nvim api integration tests" {
    _ = @import("tests/nvim_api_tests.zig");
}

test "nvim api extended tests" {
    _ = @import("tests/nvim_api_extended_tests.zig");
}

test "nvim api extmark tests" {
    _ = @import("tests/nvim_api_extmark_tests.zig");
}

test "nvim api keymap tests" {
    _ = @import("tests/nvim_api_keymap_tests.zig");
}

test "nvim api more tests" {
    _ = @import("tests/nvim_api_more_tests.zig");
}

test "nvim api additional tests" {
    _ = @import("tests/nvim_api_additional_tests.zig");
}

test "nvim api final tests" {
    _ = @import("tests/nvim_api_final_tests.zig");
}

test "nvim api ui and context tests" {
    _ = @import("tests/nvim_api_ui_context_tests.zig");
}

test "nvim api io and events tests" {
    _ = @import("tests/nvim_api_io_events_tests.zig");
}

test "nvim api highlight and marks tests" {
    _ = @import("tests/nvim_api_highlight_marks_tests.zig");
}

test "nvim api lsp tests" {
    _ = @import("tests/nvim_api_lsp_tests.zig");
}

test "nvim api misc tests" {
    _ = @import("tests/nvim_api_misc_tests.zig");
}

test "nvim api buffer tests" {
    _ = @import("tests/nvim_api_buffer_tests.zig");
}

test "nvim api batch tests" {
    _ = @import("tests/nvim_api_batch_tests.zig");
}

test "nvim api window tests" {
    _ = @import("tests/nvim_api_window_tests.zig");
}

test "nvim api tabpage tests" {
    _ = @import("tests/nvim_api_tabpage_tests.zig");
}

test "nvim api complete tests" {
    _ = @import("tests/nvim_api_complete_tests.zig");
}

test "nvim api final push tests" {
    _ = @import("tests/nvim_api_final_push_tests.zig");
}

test "windows pipe integration tests" {
    _ = @import("tests/windows_pipe_integration_tests.zig");
}

test "client windows tests" {
    _ = @import("tests/client_windows_tests.zig");
}

test "error recovery tests" {
    _ = @import("tests/error_recovery_tests.zig");
}

test "boundary condition tests" {
    _ = @import("tests/boundary_tests.zig");
}

test "concurrency tests" {
    _ = @import("tests/concurrency_tests.zig");
}

test "concurrent shared client tests" {
    _ = @import("tests/concurrent_shared_client_tests.zig");
}

test "manual fuzzing tests" {
    _ = @import("tests/fuzz_manual_tests.zig");
}

test "client error path tests" {
    _ = @import("tests/client_error_tests.zig");
}

test "api info tests" {
    _ = @import("tests/api_info_tests.zig");
}

test "client setup tests" {
    _ = @import("tests/client_setup_tests.zig");
}

test "client unix tests" {
    _ = @import("tests/client_unix_tests.zig");
}

test "e2e concurrent tests" {
    _ = @import("tests/e2e_concurrent_tests.zig");
}

test "e2e fault recovery tests" {
    _ = @import("tests/e2e_fault_recovery_tests.zig");
}

test "e2e workflow tests" {
    _ = @import("tests/e2e_workflow_tests.zig");
}

test "e2e long running tests" {
    _ = @import("tests/e2e_long_running_tests.zig");
}

test "e2e large data tests" {
    _ = @import("tests/e2e_large_data_tests.zig");
}
