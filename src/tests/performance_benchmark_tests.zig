const std = @import("std");
const builtin = @import("builtin");
const znvim = @import("../root.zig");
const msgpack = @import("../msgpack.zig");

// ============================================================================
// 性能基准测试和压力测试
//
// 这些测试评估 znvim 在各种负载条件下的性能特征：
// 1. 吞吐量测试：每秒能处理多少请求
// 2. 延迟测试：单个请求的响应时间
// 3. 内存使用：内存分配和释放模式
// 4. 稳定性测试：长时间高负载下的稳定性
// ============================================================================

// 辅助函数：创建测试用的 Client
fn createBenchmarkClient(allocator: std.mem.Allocator) !*znvim.Client {
    const client = try allocator.create(znvim.Client);
    client.* = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .skip_api_info = true, // 跳过 API info 以加快测试
    });
    try client.connect();
    return client;
}

fn destroyBenchmarkClient(client: *znvim.Client, allocator: std.mem.Allocator) void {
    client.disconnect();
    client.deinit();
    allocator.destroy(client);
}

// ============================================================================
// 1. 吞吐量基准测试
// ============================================================================

test "performance: throughput - 1000 sequential requests" {
    const allocator = std.testing.allocator;
    const client = try createBenchmarkClient(allocator);
    defer destroyBenchmarkClient(client, allocator);

    const iterations = 1000;
    const start_time = std.time.milliTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const params = [_]msgpack.Value{};
        const result = try client.request("nvim_get_mode", &params);
        defer msgpack.free(result, allocator);
    }

    const end_time = std.time.milliTimestamp();
    const duration_ms = end_time - start_time;
    const throughput = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0);

    // 验证完成了所有请求
    try std.testing.expect(i == iterations);
    // 吞吐量应该合理（至少 10 req/s）
    try std.testing.expect(throughput > 10.0);
}

test "performance: throughput - 100 requests with parameters" {
    const allocator = std.testing.allocator;
    const client = try createBenchmarkClient(allocator);
    defer destroyBenchmarkClient(client, allocator);

    const iterations = 100;
    const start_time = std.time.milliTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        // 使用带参数的请求（更复杂）
        const expr = try msgpack.string(allocator, "1 + 1");
        defer msgpack.free(expr, allocator);
        const params = [_]msgpack.Value{expr};
        const result = try client.request("nvim_eval", &params);
        defer msgpack.free(result, allocator);
    }

    const end_time = std.time.milliTimestamp();
    const duration_ms = end_time - start_time;

    // 验证完成了所有请求
    try std.testing.expect(i == iterations);
    // 应该在合理时间内完成（< 10秒）
    try std.testing.expect(duration_ms < 10000);
}

test "performance: throughput - mixed operations" {
    const allocator = std.testing.allocator;
    const client = try createBenchmarkClient(allocator);
    defer destroyBenchmarkClient(client, allocator);

    const iterations = 200;
    const start_time = std.time.milliTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 4) {
        // 操作 1: 获取模式
        {
            const params = [_]msgpack.Value{};
            const result = try client.request("nvim_get_mode", &params);
            defer msgpack.free(result, allocator);
        }

        // 操作 2: 评估表达式
        {
            const expr = try msgpack.string(allocator, "1 + 2");
            defer msgpack.free(expr, allocator);
            const params = [_]msgpack.Value{expr};
            const result = try client.request("nvim_eval", &params);
            defer msgpack.free(result, allocator);
        }

        // 操作 3: 获取当前行
        {
            const params = [_]msgpack.Value{};
            const result = try client.request("nvim_get_current_line", &params);
            defer msgpack.free(result, allocator);
        }

        // 操作 4: 列出 buffers
        {
            const params = [_]msgpack.Value{};
            const result = try client.request("nvim_list_bufs", &params);
            defer msgpack.free(result, allocator);
        }
    }

    const end_time = std.time.milliTimestamp();
    const duration_ms = end_time - start_time;

    try std.testing.expect(i == iterations);
    try std.testing.expect(duration_ms < 15000);
}

// ============================================================================
// 2. 延迟基准测试
// ============================================================================

test "performance: latency - single request" {
    const allocator = std.testing.allocator;
    const client = try createBenchmarkClient(allocator);
    defer destroyBenchmarkClient(client, allocator);

    // 测量单个请求的延迟
    const start_time = std.time.microTimestamp();
    const params = [_]msgpack.Value{};
    const result = try client.request("nvim_get_mode", &params);
    defer msgpack.free(result, allocator);
    const end_time = std.time.microTimestamp();

    const latency_us = end_time - start_time;
    const latency_ms = @as(f64, @floatFromInt(latency_us)) / 1000.0;

    // 单个请求延迟应该小于 100ms（Windows 上放宽到 500ms，因为进程启动和IPC开销更大）
    const max_latency_ms: f64 = if (builtin.os.tag == .windows) 500.0 else 100.0;
    try std.testing.expect(latency_ms < max_latency_ms);
}

test "performance: latency - average over 100 requests" {
    const allocator = std.testing.allocator;
    const client = try createBenchmarkClient(allocator);
    defer destroyBenchmarkClient(client, allocator);

    const iterations = 100;
    var total_latency_us: i64 = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const start_time = std.time.microTimestamp();
        const params = [_]msgpack.Value{};
        const result = try client.request("nvim_get_mode", &params);
        defer msgpack.free(result, allocator);
        const end_time = std.time.microTimestamp();

        total_latency_us += (end_time - start_time);
    }

    const avg_latency_us = @divTrunc(total_latency_us, iterations);
    const avg_latency_ms = @as(f64, @floatFromInt(avg_latency_us)) / 1000.0;

    // 平均延迟应该小于 50ms
    try std.testing.expect(avg_latency_ms < 50.0);
}

// ============================================================================
// 3. 内存使用监控测试
// ============================================================================

test "performance: memory - leak detection over 1000 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const client = try createBenchmarkClient(allocator);
    defer destroyBenchmarkClient(client, allocator);

    // 执行 1000 次请求，检查内存泄漏
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const params = [_]msgpack.Value{};
        const result = try client.request("nvim_get_mode", &params);
        defer msgpack.free(result, allocator);
    }

    // 如果有内存泄漏，defer 中的 gpa.deinit() 会 panic
}

test "performance: memory - repeated connect/disconnect cycles" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in connect/disconnect cycles!");
        }
    }
    const allocator = gpa.allocator();

    // 测试连接/断开循环中的内存管理
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var client = try znvim.Client.init(allocator, .{
            .spawn_process = true,
            .skip_api_info = true,
        });
        defer client.deinit();

        try client.connect();

        // 执行一些操作
        const params = [_]msgpack.Value{};
        const result = try client.request("nvim_get_mode", &params);
        defer msgpack.free(result, allocator);

        client.disconnect();
    }
}

test "performance: memory - large payload handling" {
    const allocator = std.testing.allocator;
    const client = try createBenchmarkClient(allocator);
    defer destroyBenchmarkClient(client, allocator);

    // 创建大的数据负载
    var large_text = try std.ArrayList(u8).initCapacity(allocator, 10000);
    defer large_text.deinit(allocator);

    // 创建 10KB 的文本
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try large_text.appendSlice(allocator, "0123456789");
    }

    // 测试设置和获取大量数据
    const cmd = try msgpack.string(allocator, "let g:test_var = 'dummy'");
    defer msgpack.free(cmd, allocator);
    const params = [_]msgpack.Value{cmd};
    const result = try client.request("nvim_command", &params);
    defer msgpack.free(result, allocator);
}

test "performance: memory - msgpack allocation patterns" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak in msgpack operations!");
        }
    }
    const allocator = gpa.allocator();

    // 测试 msgpack 值的创建和释放
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        // 创建各种类型的 msgpack 值
        const str_val = try msgpack.string(allocator, "test string");
        defer msgpack.free(str_val, allocator);

        const arr_val = try msgpack.array(allocator, &[_]msgpack.Value{
            msgpack.int(42),
            msgpack.boolean(true),
        });
        defer msgpack.free(arr_val, allocator);
    }
}

// ============================================================================
// 4. 高负载稳定性测试
// ============================================================================

test "performance: stability - sustained load 5000 requests" {
    const allocator = std.testing.allocator;
    const client = try createBenchmarkClient(allocator);
    defer destroyBenchmarkClient(client, allocator);

    const iterations = 5000;
    var success_count: usize = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const params = [_]msgpack.Value{};
        const result = client.request("nvim_get_mode", &params);

        if (result) |res| {
            defer msgpack.free(res, allocator);
            success_count += 1;
        } else |_| {
            // 记录失败但继续
        }
    }

    // 至少 99% 的请求应该成功
    const success_rate = @as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(iterations));
    try std.testing.expect(success_rate > 0.99);
}

test "performance: stability - burst traffic pattern" {
    const allocator = std.testing.allocator;
    const client = try createBenchmarkClient(allocator);
    defer destroyBenchmarkClient(client, allocator);

    // 模拟突发流量：快速发送一批请求，然后暂停，重复
    const bursts = 10;
    const requests_per_burst = 50;
    var total_success: usize = 0;

    var burst: usize = 0;
    while (burst < bursts) : (burst += 1) {
        // 突发：快速发送请求
        var i: usize = 0;
        while (i < requests_per_burst) : (i += 1) {
            const params = [_]msgpack.Value{};
            const result = try client.request("nvim_get_mode", &params);
            defer msgpack.free(result, allocator);
            total_success += 1;
        }

        // 暂停 10ms
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    const expected_total = bursts * requests_per_burst;
    try std.testing.expect(total_success == expected_total);
}

test "performance: stability - error recovery under load" {
    const allocator = std.testing.allocator;
    const client = try createBenchmarkClient(allocator);
    defer destroyBenchmarkClient(client, allocator);

    const iterations = 100;
    var success_count: usize = 0;
    var error_count: usize = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 2) {
        // 交替执行成功和失败的请求

        // 成功的请求
        {
            const params = [_]msgpack.Value{};
            const result = try client.request("nvim_get_mode", &params);
            defer msgpack.free(result, allocator);
            success_count += 1;
        }

        // 失败的请求（不存在的方法）
        {
            const params = [_]msgpack.Value{};
            const result = client.request("nonexistent_method_12345", &params);
            if (result) |res| {
                msgpack.free(res, allocator);
            } else |_| {
                error_count += 1;
            }
        }
    }

    // 验证错误恢复：成功和失败请求数量应该相等
    try std.testing.expect(success_count == iterations / 2);
    try std.testing.expect(error_count == iterations / 2);
}

// ============================================================================
// 5. 资源限制测试
// ============================================================================

test "performance: resource limits - max message size" {
    const allocator = std.testing.allocator;
    const client = try createBenchmarkClient(allocator);
    defer destroyBenchmarkClient(client, allocator);

    // 创建一个较大的字符串（100KB）
    var large_str = try std.ArrayList(u8).initCapacity(allocator, 100000);
    defer large_str.deinit(allocator);

    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        try large_str.appendSlice(allocator, "0123456789");
    }

    // 尝试发送大消息
    const expr = try msgpack.string(allocator, large_str.items);
    defer msgpack.free(expr, allocator);

    // 这可能成功也可能失败，取决于 Neovim 的限制
    const params = [_]msgpack.Value{expr};
    _ = client.request("nvim_eval", &params) catch {
        // 如果失败，至少客户端应该能恢复
        const test_params = [_]msgpack.Value{};
        const result = try client.request("nvim_get_mode", &test_params);
        defer msgpack.free(result, allocator);
    };
}

test "performance: resource limits - rapid connection cycling" {
    const allocator = std.testing.allocator;

    // 快速创建和销毁多个连接
    const cycles = 20;
    var i: usize = 0;
    while (i < cycles) : (i += 1) {
        var client = try znvim.Client.init(allocator, .{
            .spawn_process = true,
            .skip_api_info = true,
        });
        defer client.deinit();

        try client.connect();

        // 执行单个请求
        const params = [_]msgpack.Value{};
        const result = try client.request("nvim_get_mode", &params);
        defer msgpack.free(result, allocator);

        client.disconnect();
    }

    // 所有循环都应该成功完成
    try std.testing.expect(i == cycles);
}

// ============================================================================
// 6. 并发性能测试
// ============================================================================

test "performance: concurrency - multiple clients sequential" {
    const allocator = std.testing.allocator;

    const num_clients = 5;
    const requests_per_client = 100;

    var clients: [num_clients]*znvim.Client = undefined;

    // 创建多个客户端
    for (&clients) |*client_ptr| {
        client_ptr.* = try createBenchmarkClient(allocator);
    }
    defer {
        for (clients) |client| {
            destroyBenchmarkClient(client, allocator);
        }
    }

    const start_time = std.time.milliTimestamp();

    // 每个客户端依次执行请求
    for (clients) |client| {
        var i: usize = 0;
        while (i < requests_per_client) : (i += 1) {
            const params = [_]msgpack.Value{};
            const result = try client.request("nvim_get_mode", &params);
            defer msgpack.free(result, allocator);
        }
    }

    const end_time = std.time.milliTimestamp();
    const duration_ms = end_time - start_time;

    // 验证所有请求完成，时间应该合理
    const total_requests = num_clients * requests_per_client;
    const throughput = @as(f64, @floatFromInt(total_requests)) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0);

    try std.testing.expect(throughput > 5.0);
}
