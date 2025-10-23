const std = @import("std");
const znvim = @import("../root.zig");
const Client = znvim.Client;
const ApiInfo = znvim.ApiInfo;
const ApiFunction = znvim.ApiFunction;
const ApiParameter = znvim.ApiParameter;
const msgpack = znvim.msgpack;

// Tests for ApiInfo and related functionality

test "ApiInfo findFunction locates existing function" {
    const allocator = std.testing.allocator;

    const functions = try allocator.alloc(ApiFunction, 3);
    defer allocator.free(functions);

    functions[0] = ApiFunction{
        .name = "nvim_get_mode",
        .since = 1,
        .method = false,
        .return_type = "Dictionary",
        .parameters = &.{},
    };

    functions[1] = ApiFunction{
        .name = "nvim_buf_set_lines",
        .since = 1,
        .method = true,
        .return_type = "void",
        .parameters = &.{},
    };

    functions[2] = ApiFunction{
        .name = "nvim_get_api_info",
        .since = 1,
        .method = false,
        .return_type = "Array",
        .parameters = &.{},
    };

    const api_info = ApiInfo{
        .channel_id = 1,
        .version = .{
            .major = 0,
            .minor = 10,
            .patch = 0,
            .api_level = 12,
            .api_compatible = 0,
            .api_prerelease = false,
            .prerelease = false,
            .build = null,
        },
        .functions = functions,
    };

    // Find existing function
    const found = api_info.findFunction("nvim_get_mode");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("nvim_get_mode", found.?.name);

    // Find method function
    const found_method = api_info.findFunction("nvim_buf_set_lines");
    try std.testing.expect(found_method != null);
    try std.testing.expectEqual(true, found_method.?.method);
}

test "ApiInfo findFunction returns null for unknown function" {
    const allocator = std.testing.allocator;

    const functions = try allocator.alloc(ApiFunction, 1);
    defer allocator.free(functions);

    functions[0] = ApiFunction{
        .name = "nvim_get_mode",
        .since = 1,
        .method = false,
        .return_type = "Dictionary",
        .parameters = &.{},
    };

    const api_info = ApiInfo{
        .channel_id = 1,
        .version = .{
            .major = 0,
            .minor = 10,
            .patch = 0,
            .api_level = 12,
            .api_compatible = 0,
            .api_prerelease = false,
            .prerelease = false,
            .build = null,
        },
        .functions = functions,
    };

    const found = api_info.findFunction("nonexistent_function");
    try std.testing.expect(found == null);
}

test "ApiInfo findFunction with empty function list" {
    const functions = &[_]ApiFunction{};

    const api_info = ApiInfo{
        .channel_id = 1,
        .version = .{
            .major = 0,
            .minor = 10,
            .patch = 0,
            .api_level = 12,
            .api_compatible = 0,
            .api_prerelease = false,
            .prerelease = false,
            .build = null,
        },
        .functions = functions,
    };

    const found = api_info.findFunction("any_function");
    try std.testing.expect(found == null);
}

test "ApiInfo findFunction with empty string" {
    const allocator = std.testing.allocator;

    const functions = try allocator.alloc(ApiFunction, 1);
    defer allocator.free(functions);

    functions[0] = ApiFunction{
        .name = "nvim_get_mode",
        .since = 1,
        .method = false,
        .return_type = "Dictionary",
        .parameters = &.{},
    };

    const api_info = ApiInfo{
        .channel_id = 1,
        .version = .{
            .major = 0,
            .minor = 10,
            .patch = 0,
            .api_level = 12,
            .api_compatible = 0,
            .api_prerelease = false,
            .prerelease = false,
            .build = null,
        },
        .functions = functions,
    };

    const found = api_info.findFunction("");
    try std.testing.expect(found == null);
}

test "Client findApiFunction delegates to ApiInfo" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .skip_api_info = true,
    });
    defer client.deinit();

    // Without API info
    const not_found = client.findApiFunction("any_function");
    try std.testing.expect(not_found == null);
}

test "Client getApiInfo returns null when not loaded" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .skip_api_info = true,
    });
    defer client.deinit();

    const info = client.getApiInfo();
    try std.testing.expect(info == null);
}
