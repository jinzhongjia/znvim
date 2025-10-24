const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = @import("../msgpack.zig");

// 辅助函数：创建测试用的 Client
fn createTestClient(allocator: std.mem.Allocator) !*znvim.Client {
    const client = try allocator.create(znvim.Client);
    client.* = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
    });
    try client.connect();
    return client;
}

// 辅助函数：清理 Client
fn destroyTestClient(client: *znvim.Client, allocator: std.mem.Allocator) void {
    client.disconnect();
    client.deinit();
    allocator.destroy(client);
}

// ============================================================================
// 1. 探索 Neovim 错误格式
// ============================================================================

test "nvim error: explore error structure from invalid buffer" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    // 使用无效的 buffer handle 触发错误
    const invalid_buf = msgpack.int(99999);
    defer msgpack.free(invalid_buf, allocator);

    const params = [_]msgpack.Value{invalid_buf};

    // nvim_buf_is_valid 对无效的 buffer 返回 false，而不是错误
    const result = try client.request("nvim_buf_is_valid", &params);
    defer msgpack.free(result, allocator);

    const is_valid = try msgpack.expectBool(result);
    try std.testing.expect(!is_valid);
}

test "nvim error: explore error structure from invalid command" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    // 执行无效的命令
    const cmd = try msgpack.string(allocator, "this_is_an_invalid_command");
    defer msgpack.free(cmd, allocator);

    const params = [_]msgpack.Value{cmd};

    const result = client.request("nvim_command", &params);
    try std.testing.expectError(error.NvimError, result);
}

test "nvim error: explore error structure from invalid eval" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    // 执行无效的表达式
    const expr = try msgpack.string(allocator, "undefined_variable");
    defer msgpack.free(expr, allocator);

    const params = [_]msgpack.Value{expr};

    const result = client.request("nvim_eval", &params);
    try std.testing.expectError(error.NvimError, result);
}

// ============================================================================
// 2. 测试基本错误处理（当前实现）
// ============================================================================

test "nvim error: invalid buffer handle returns false not error" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    const invalid_buf = msgpack.int(99999);
    defer msgpack.free(invalid_buf, allocator);

    const params = [_]msgpack.Value{invalid_buf};

    // nvim_buf_is_valid 对无效 buffer 返回 false，不是错误
    const result = try client.request("nvim_buf_is_valid", &params);
    defer msgpack.free(result, allocator);

    const is_valid = try msgpack.expectBool(result);
    try std.testing.expect(!is_valid);
}

test "nvim error: invalid method name returns error" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    const params = [_]msgpack.Value{};

    const result = client.request("nonexistent_method", &params);
    try std.testing.expectError(error.NvimError, result);
}

test "nvim error: wrong parameter count returns error" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    // nvim_command 需要 1 个参数，我们传 0 个
    const params = [_]msgpack.Value{};

    const result = client.request("nvim_command", &params);
    try std.testing.expectError(error.NvimError, result);
}

test "nvim error: wrong parameter type returns error" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    // nvim_command 需要 string，我们传 int
    const wrong_type = msgpack.int(123);
    defer msgpack.free(wrong_type, allocator);

    const params = [_]msgpack.Value{wrong_type};

    const result = client.request("nvim_command", &params);
    try std.testing.expectError(error.NvimError, result);
}

test "nvim error: invalid command syntax returns error" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    const invalid_cmd = try msgpack.string(allocator, "invalid command syntax >>>>");
    defer msgpack.free(invalid_cmd, allocator);

    const params = [_]msgpack.Value{invalid_cmd};

    const result = client.request("nvim_command", &params);
    try std.testing.expectError(error.NvimError, result);
}

test "nvim error: undefined variable in eval returns error" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    // 使用真正会导致错误的表达式
    const invalid_expr = try msgpack.string(allocator, "nonexistent_vim_variable_12345");
    defer msgpack.free(invalid_expr, allocator);

    const params = [_]msgpack.Value{invalid_expr};

    const result = client.request("nvim_eval", &params);
    try std.testing.expectError(error.NvimError, result);
}

test "nvim error: invalid window handle returns false not error" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    const invalid_win = msgpack.int(99999);
    defer msgpack.free(invalid_win, allocator);

    const params = [_]msgpack.Value{invalid_win};

    // nvim_win_is_valid 对无效窗口返回 false，不是错误
    const result = try client.request("nvim_win_is_valid", &params);
    defer msgpack.free(result, allocator);

    const is_valid = try msgpack.expectBool(result);
    try std.testing.expect(!is_valid);
}

test "nvim error: invalid tabpage handle returns false not error" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    const invalid_tab = msgpack.int(99999);
    defer msgpack.free(invalid_tab, allocator);

    const params = [_]msgpack.Value{invalid_tab};

    // nvim_tabpage_is_valid 对无效标签页返回 false，不是错误
    const result = try client.request("nvim_tabpage_is_valid", &params);
    defer msgpack.free(result, allocator);

    const is_valid = try msgpack.expectBool(result);
    try std.testing.expect(!is_valid);
}

test "nvim error: buffer operation on invalid buffer" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    const invalid_buf = msgpack.int(-1);
    defer msgpack.free(invalid_buf, allocator);

    const start = msgpack.int(0);
    defer msgpack.free(start, allocator);

    const end = msgpack.int(1);
    defer msgpack.free(end, allocator);

    const strict = msgpack.boolean(true);
    defer msgpack.free(strict, allocator);

    const params = [_]msgpack.Value{ invalid_buf, start, end, strict };

    const result = client.request("nvim_buf_get_lines", &params);
    try std.testing.expectError(error.NvimError, result);
}

test "nvim error: set option with invalid value" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    const option_name = try msgpack.string(allocator, "tabstop");
    defer msgpack.free(option_name, allocator);

    // tabstop 不能为负数
    const invalid_value = msgpack.int(-1);
    defer msgpack.free(invalid_value, allocator);

    const params = [_]msgpack.Value{ option_name, invalid_value };

    const result = client.request("nvim_set_option_value", &params);
    try std.testing.expectError(error.NvimError, result);
}

// ============================================================================
// 3. 边界情况测试
// ============================================================================

test "nvim error: empty method name" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    const params = [_]msgpack.Value{};

    const result = client.request("", &params);
    try std.testing.expectError(error.NvimError, result);
}

test "nvim error: method with special characters" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    const params = [_]msgpack.Value{};

    const result = client.request("nvim_$#@_invalid", &params);
    try std.testing.expectError(error.NvimError, result);
}

test "nvim error: extremely long method name" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    const long_name = "nvim_" ++ "a" ** 1000;
    const params = [_]msgpack.Value{};

    // 超长方法名可能导致连接关闭或 NvimError
    const result = client.request(long_name, &params);
    if (result) |_| {
        unreachable; // 不应该成功
    } else |err| {
        // 接受 NvimError 或 ConnectionClosed
        try std.testing.expect(err == error.NvimError or err == error.ConnectionClosed);
    }
}

// ============================================================================
// 4. 多个连续错误测试
// ============================================================================

test "nvim error: multiple consecutive errors" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    // 第一个测试：nvim_buf_is_valid 返回 false 而不是错误
    {
        const invalid_buf = msgpack.int(99999);
        defer msgpack.free(invalid_buf, allocator);
        const params = [_]msgpack.Value{invalid_buf};
        const result = try client.request("nvim_buf_is_valid", &params);
        defer msgpack.free(result, allocator);
        const is_valid = try msgpack.expectBool(result);
        try std.testing.expect(!is_valid);
    }

    // 第二个错误
    {
        const params = [_]msgpack.Value{};
        const result = client.request("nonexistent_method", &params);
        try std.testing.expectError(error.NvimError, result);
    }

    // 第三个错误
    {
        const invalid_cmd = try msgpack.string(allocator, "invalid_cmd");
        defer msgpack.free(invalid_cmd, allocator);
        const params = [_]msgpack.Value{invalid_cmd};
        const result = client.request("nvim_command", &params);
        try std.testing.expectError(error.NvimError, result);
    }

    // 确保在多个错误后仍然可以正常请求
    {
        const params = [_]msgpack.Value{};
        const result = try client.request("nvim_get_mode", &params);
        defer msgpack.free(result, allocator);
        // 应该成功
    }
}

test "nvim error: error followed by success" {
    const allocator = std.testing.allocator;
    const client = try createTestClient(allocator);
    defer destroyTestClient(client, allocator);

    // 先触发错误
    {
        const params = [_]msgpack.Value{};
        const result = client.request("nonexistent_method", &params);
        try std.testing.expectError(error.NvimError, result);
    }

    // 然后正常请求应该成功
    {
        const params = [_]msgpack.Value{};
        const result = try client.request("nvim_get_mode", &params);
        defer msgpack.free(result, allocator);

        // 验证返回值是 map 类型
        try std.testing.expect(result == .map);
        try std.testing.expect(result.map.count() > 0);
    }
}
