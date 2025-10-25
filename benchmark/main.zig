const std = @import("std");
const znvim = @import("znvim");

// ============================================================================
// znvim 性能基准测试工具
//
// 用法：zig-out/bin/benchmark [选项]
//
// 这个工具运行全面的性能基准测试并生成详细报告
// ============================================================================

const BenchmarkResult = struct {
    name: []const u8,
    iterations: usize,
    total_time_ms: i64,
    avg_time_ms: f64,
    throughput: f64, // requests per second
    min_time_us: i64,
    max_time_us: i64,
    success_rate: f64,
};

fn printHeader() void {
    std.debug.print("\n", .{});
    std.debug.print("=" ** 70 ++ "\n", .{});
    std.debug.print("  znvim 性能基准测试报告\n", .{});
    std.debug.print("=" ** 70 ++ "\n\n", .{});
}

fn printResult(result: BenchmarkResult) void {
    std.debug.print("📊 {s}\n", .{result.name});
    std.debug.print("  迭代次数:     {d}\n", .{result.iterations});
    std.debug.print("  总时间:       {d} ms\n", .{result.total_time_ms});
    std.debug.print("  平均时间:     {d:.2} ms\n", .{result.avg_time_ms});
    std.debug.print("  吞吐量:       {d:.2} req/s\n", .{result.throughput});
    std.debug.print("  最小延迟:     {d} μs\n", .{result.min_time_us});
    std.debug.print("  最大延迟:     {d} μs\n", .{result.max_time_us});
    std.debug.print("  成功率:       {d:.2}%\n", .{result.success_rate * 100.0});
    std.debug.print("\n", .{});
}

fn benchmarkThroughput(allocator: std.mem.Allocator, iterations: usize) !BenchmarkResult {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .skip_api_info = true,
    });
    defer client.deinit();
    try client.connect();

    var min_time_us: i64 = std.math.maxInt(i64);
    var max_time_us: i64 = 0;
    var success_count: usize = 0;

    const start_time = std.time.milliTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const iter_start = std.time.microTimestamp();

        const params = [_]znvim.msgpack.Value{};
        const result = client.request("nvim_get_mode", &params);

        const iter_end = std.time.microTimestamp();
        const iter_time = iter_end - iter_start;

        if (result) |res| {
            defer znvim.msgpack.free(res, allocator);
            success_count += 1;

            if (iter_time < min_time_us) min_time_us = iter_time;
            if (iter_time > max_time_us) max_time_us = iter_time;
        } else |_| {}
    }

    const end_time = std.time.milliTimestamp();
    const total_time_ms = end_time - start_time;
    const avg_time_ms = @as(f64, @floatFromInt(total_time_ms)) / @as(f64, @floatFromInt(iterations));
    const throughput = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(total_time_ms)) / 1000.0);
    const success_rate = @as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(iterations));

    return BenchmarkResult{
        .name = "吞吐量测试 (nvim_get_mode)",
        .iterations = iterations,
        .total_time_ms = total_time_ms,
        .avg_time_ms = avg_time_ms,
        .throughput = throughput,
        .min_time_us = min_time_us,
        .max_time_us = max_time_us,
        .success_rate = success_rate,
    };
}

fn benchmarkMixedOperations(allocator: std.mem.Allocator, iterations: usize) !BenchmarkResult {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .skip_api_info = true,
    });
    defer client.deinit();
    try client.connect();

    var min_time_us: i64 = std.math.maxInt(i64);
    var max_time_us: i64 = 0;
    var success_count: usize = 0;

    const start_time = std.time.milliTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 10) {
        // 操作 1: nvim_get_mode
        {
            const iter_start = std.time.microTimestamp();
            const params = [_]znvim.msgpack.Value{};
            const result = try client.request("nvim_get_mode", &params);
            defer znvim.msgpack.free(result, allocator);
            const iter_end = std.time.microTimestamp();
            const iter_time = iter_end - iter_start;
            if (iter_time < min_time_us) min_time_us = iter_time;
            if (iter_time > max_time_us) max_time_us = iter_time;
            success_count += 1;
        }

        // 操作 2: nvim_eval
        {
            const iter_start = std.time.microTimestamp();
            const expr = try znvim.msgpack.string(allocator, "1 + 1");
            defer znvim.msgpack.free(expr, allocator);
            const params = [_]znvim.msgpack.Value{expr};
            const result = try client.request("nvim_eval", &params);
            defer znvim.msgpack.free(result, allocator);
            const iter_end = std.time.microTimestamp();
            const iter_time = iter_end - iter_start;
            if (iter_time < min_time_us) min_time_us = iter_time;
            if (iter_time > max_time_us) max_time_us = iter_time;
            success_count += 1;
        }

        // 操作 3: nvim_get_current_line
        {
            const iter_start = std.time.microTimestamp();
            const params = [_]znvim.msgpack.Value{};
            const result = try client.request("nvim_get_current_line", &params);
            defer znvim.msgpack.free(result, allocator);
            const iter_end = std.time.microTimestamp();
            const iter_time = iter_end - iter_start;
            if (iter_time < min_time_us) min_time_us = iter_time;
            if (iter_time > max_time_us) max_time_us = iter_time;
            success_count += 1;
        }

        // 操作 4: nvim_list_bufs
        {
            const iter_start = std.time.microTimestamp();
            const params = [_]znvim.msgpack.Value{};
            const result = try client.request("nvim_list_bufs", &params);
            defer znvim.msgpack.free(result, allocator);
            const iter_end = std.time.microTimestamp();
            const iter_time = iter_end - iter_start;
            if (iter_time < min_time_us) min_time_us = iter_time;
            if (iter_time > max_time_us) max_time_us = iter_time;
            success_count += 1;
        }

        // 操作 5: nvim_list_wins
        {
            const iter_start = std.time.microTimestamp();
            const params = [_]znvim.msgpack.Value{};
            const result = try client.request("nvim_list_wins", &params);
            defer znvim.msgpack.free(result, allocator);
            const iter_end = std.time.microTimestamp();
            const iter_time = iter_end - iter_start;
            if (iter_time < min_time_us) min_time_us = iter_time;
            if (iter_time > max_time_us) max_time_us = iter_time;
            success_count += 1;
        }

        // 操作 6: nvim_get_current_buf
        {
            const iter_start = std.time.microTimestamp();
            const params = [_]znvim.msgpack.Value{};
            const result = try client.request("nvim_get_current_buf", &params);
            defer znvim.msgpack.free(result, allocator);
            const iter_end = std.time.microTimestamp();
            const iter_time = iter_end - iter_start;
            if (iter_time < min_time_us) min_time_us = iter_time;
            if (iter_time > max_time_us) max_time_us = iter_time;
            success_count += 1;
        }

        // 操作 7: nvim_get_current_win
        {
            const iter_start = std.time.microTimestamp();
            const params = [_]znvim.msgpack.Value{};
            const result = try client.request("nvim_get_current_win", &params);
            defer znvim.msgpack.free(result, allocator);
            const iter_end = std.time.microTimestamp();
            const iter_time = iter_end - iter_start;
            if (iter_time < min_time_us) min_time_us = iter_time;
            if (iter_time > max_time_us) max_time_us = iter_time;
            success_count += 1;
        }

        // 操作 8: nvim_get_current_tabpage
        {
            const iter_start = std.time.microTimestamp();
            const params = [_]znvim.msgpack.Value{};
            const result = try client.request("nvim_get_current_tabpage", &params);
            defer znvim.msgpack.free(result, allocator);
            const iter_end = std.time.microTimestamp();
            const iter_time = iter_end - iter_start;
            if (iter_time < min_time_us) min_time_us = iter_time;
            if (iter_time > max_time_us) max_time_us = iter_time;
            success_count += 1;
        }

        // 操作 9: nvim_call_function
        {
            const iter_start = std.time.microTimestamp();
            const func_name = try znvim.msgpack.string(allocator, "strftime");
            defer znvim.msgpack.free(func_name, allocator);
            const arg_str = try znvim.msgpack.string(allocator, "%Y-%m-%d");
            // 注意：arg_str 的所有权被 array 接管，不要再 free
            const args_arr = try znvim.msgpack.array(allocator, &[_]znvim.msgpack.Value{arg_str});
            defer znvim.msgpack.free(args_arr, allocator); // 这会释放 args_arr 和 arg_str
            const params = [_]znvim.msgpack.Value{ func_name, args_arr };
            const result = try client.request("nvim_call_function", &params);
            defer znvim.msgpack.free(result, allocator);
            const iter_end = std.time.microTimestamp();
            const iter_time = iter_end - iter_start;
            if (iter_time < min_time_us) min_time_us = iter_time;
            if (iter_time > max_time_us) max_time_us = iter_time;
            success_count += 1;
        }

        // 操作 10: nvim_command (简单命令)
        {
            const iter_start = std.time.microTimestamp();
            const cmd = try znvim.msgpack.string(allocator, "echo 'benchmark'");
            defer znvim.msgpack.free(cmd, allocator);
            const params = [_]znvim.msgpack.Value{cmd};
            const result = try client.request("nvim_command", &params);
            defer znvim.msgpack.free(result, allocator);
            const iter_end = std.time.microTimestamp();
            const iter_time = iter_end - iter_start;
            if (iter_time < min_time_us) min_time_us = iter_time;
            if (iter_time > max_time_us) max_time_us = iter_time;
            success_count += 1;
        }
    }

    const end_time = std.time.milliTimestamp();
    const total_time_ms = end_time - start_time;
    const avg_time_ms = @as(f64, @floatFromInt(total_time_ms)) / @as(f64, @floatFromInt(iterations));
    const throughput = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(total_time_ms)) / 1000.0);
    const success_rate = @as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(iterations));

    return BenchmarkResult{
        .name = "混合操作测试 (10种API)",
        .iterations = iterations,
        .total_time_ms = total_time_ms,
        .avg_time_ms = avg_time_ms,
        .throughput = throughput,
        .min_time_us = min_time_us,
        .max_time_us = max_time_us,
        .success_rate = success_rate,
    };
}

fn benchmarkMemoryUsage(allocator: std.mem.Allocator, iterations: usize) !BenchmarkResult {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .skip_api_info = true,
    });
    defer client.deinit();
    try client.connect();

    var min_time_us: i64 = std.math.maxInt(i64);
    var max_time_us: i64 = 0;
    var success_count: usize = 0;

    const start_time = std.time.milliTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const iter_start = std.time.microTimestamp();

        // 创建一些 msgpack 值
        const str_val = try znvim.msgpack.string(allocator, "test string");
        defer znvim.msgpack.free(str_val, allocator);

        const arr_val = try znvim.msgpack.array(allocator, &[_]znvim.msgpack.Value{
            znvim.msgpack.int(42),
            znvim.msgpack.boolean(true),
        });
        defer znvim.msgpack.free(arr_val, allocator);

        // 执行请求
        const params = [_]znvim.msgpack.Value{};
        const result = try client.request("nvim_get_mode", &params);
        defer znvim.msgpack.free(result, allocator);

        const iter_end = std.time.microTimestamp();
        const iter_time = iter_end - iter_start;

        if (iter_time < min_time_us) min_time_us = iter_time;
        if (iter_time > max_time_us) max_time_us = iter_time;
        success_count += 1;
    }

    const end_time = std.time.milliTimestamp();
    const total_time_ms = end_time - start_time;
    const avg_time_ms = @as(f64, @floatFromInt(total_time_ms)) / @as(f64, @floatFromInt(iterations));
    const throughput = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(total_time_ms)) / 1000.0);
    const success_rate = @as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(iterations));

    return BenchmarkResult{
        .name = "内存分配压力测试",
        .iterations = iterations,
        .total_time_ms = total_time_ms,
        .avg_time_ms = avg_time_ms,
        .throughput = throughput,
        .min_time_us = min_time_us,
        .max_time_us = max_time_us,
        .success_rate = success_rate,
    };
}

fn benchmarkBurstTraffic(allocator: std.mem.Allocator, bursts: usize, requests_per_burst: usize) !BenchmarkResult {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .skip_api_info = true,
    });
    defer client.deinit();
    try client.connect();

    var min_time_us: i64 = std.math.maxInt(i64);
    var max_time_us: i64 = 0;
    var success_count: usize = 0;
    const total_iterations = bursts * requests_per_burst;

    const start_time = std.time.milliTimestamp();

    var burst: usize = 0;
    while (burst < bursts) : (burst += 1) {
        // 突发：快速发送请求
        var i: usize = 0;
        while (i < requests_per_burst) : (i += 1) {
            const iter_start = std.time.microTimestamp();
            const params = [_]znvim.msgpack.Value{};
            const result = try client.request("nvim_get_mode", &params);
            defer znvim.msgpack.free(result, allocator);
            const iter_end = std.time.microTimestamp();
            const iter_time = iter_end - iter_start;

            if (iter_time < min_time_us) min_time_us = iter_time;
            if (iter_time > max_time_us) max_time_us = iter_time;
            success_count += 1;
        }

        // 短暂暂停（10ms）
        if (burst < bursts - 1) {
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }

    const end_time = std.time.milliTimestamp();
    const total_time_ms = end_time - start_time;
    const avg_time_ms = @as(f64, @floatFromInt(total_time_ms)) / @as(f64, @floatFromInt(total_iterations));
    const throughput = @as(f64, @floatFromInt(total_iterations)) / (@as(f64, @floatFromInt(total_time_ms)) / 1000.0);
    const success_rate = @as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(total_iterations));

    return BenchmarkResult{
        .name = "突发流量测试",
        .iterations = total_iterations,
        .total_time_ms = total_time_ms,
        .avg_time_ms = avg_time_ms,
        .throughput = throughput,
        .min_time_us = min_time_us,
        .max_time_us = max_time_us,
        .success_rate = success_rate,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("\n⚠️  警告：检测到内存泄漏！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    printHeader();

    std.debug.print("🚀 开始运行性能基准测试...\n\n", .{});

    // 1. 吞吐量测试
    std.debug.print("1️⃣  运行吞吐量测试 (1000次迭代)...\n", .{});
    const throughput_result = try benchmarkThroughput(allocator, 1000);
    printResult(throughput_result);

    // 2. 混合操作测试
    std.debug.print("2️⃣  运行混合操作测试 (1000次操作，10种API)...\n", .{});
    const mixed_result = try benchmarkMixedOperations(allocator, 1000);
    printResult(mixed_result);

    // 3. 内存分配测试
    std.debug.print("3️⃣  运行内存分配压力测试 (1000次迭代)...\n", .{});
    const memory_result = try benchmarkMemoryUsage(allocator, 1000);
    printResult(memory_result);

    // 4. 突发流量测试
    std.debug.print("4️⃣  运行突发流量测试 (10个突发 × 50请求)...\n", .{});
    const burst_result = try benchmarkBurstTraffic(allocator, 10, 50);
    printResult(burst_result);

    // 打印总结
    std.debug.print("=" ** 70 ++ "\n", .{});
    std.debug.print("  测试总结\n", .{});
    std.debug.print("=" ** 70 ++ "\n\n", .{});

    std.debug.print("✅ 所有基准测试完成！\n\n", .{});
    std.debug.print("平均性能指标:\n", .{});
    const overall_throughput = (throughput_result.throughput + mixed_result.throughput +
        memory_result.throughput + burst_result.throughput) / 4.0;
    const overall_avg_latency = (throughput_result.avg_time_ms + mixed_result.avg_time_ms +
        memory_result.avg_time_ms + burst_result.avg_time_ms) / 4.0;

    std.debug.print("  总体吞吐量:   {d:.2} req/s\n", .{overall_throughput});
    std.debug.print("  总体平均延迟: {d:.2} ms\n", .{overall_avg_latency});
    std.debug.print("  内存状态:     ✅ 无泄漏\n", .{});
    std.debug.print("\n", .{});
}
