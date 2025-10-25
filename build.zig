const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const msgpack_dep = b.dependency("zig_msgpack", .{
        .target = target,
        .optimize = optimize,
    });
    const msgpack_module = msgpack_dep.module("msgpack");

    const mod = b.addModule("znvim", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("msgpack", msgpack_module);

    const example_sources = [_]struct {
        name: []const u8,
        path: []const u8,
    }{
        // 基础示例
        .{ .name = "simple_spawn", .path = "examples/simple_spawn.zig" },
        .{ .name = "api_info", .path = "examples/api_info.zig" },
        .{ .name = "buffer_lines", .path = "examples/buffer_lines.zig" },
        .{ .name = "eval_expression", .path = "examples/eval_expression.zig" },
        .{ .name = "print_api", .path = "examples/print_api.zig" },
        .{ .name = "run_command", .path = "examples/run_command.zig" },
        .{ .name = "event_handling", .path = "examples/event_handling.zig" },
        .{ .name = "batch_file_processing", .path = "examples/batch_file_processing.zig" },
        .{ .name = "live_linter", .path = "examples/live_linter.zig" },
        // 生产环境示例（支持所有平台和连接方式）
        .{ .name = "code_formatter", .path = "examples/code_formatter.zig" },
        .{ .name = "batch_search_replace", .path = "examples/batch_search_replace.zig" },
        .{ .name = "remote_edit_session", .path = "examples/remote_edit_session.zig" },
        .{ .name = "code_statistics", .path = "examples/code_statistics.zig" },
    };

    const examples_step = b.step("examples", "Build examples");

    inline for (example_sources) |example| {
        const exe_module = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = target,
            .optimize = optimize,
        });
        exe_module.addImport("znvim", mod);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = exe_module,
        });

        const install = b.addInstallArtifact(exe, .{});
        examples_step.dependOn(&install.step);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    mod_tests.linkLibC();
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    // Benchmark executable
    const benchmark_module = b.createModule(.{
        .root_source_file = b.path("benchmark/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    benchmark_module.addImport("znvim", mod);

    const benchmark_exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = benchmark_module,
    });

    const install_benchmark = b.addInstallArtifact(benchmark_exe, .{});
    const benchmark_step = b.step("benchmark", "Build and install benchmark tool");
    benchmark_step.dependOn(&install_benchmark.step);

    // Run benchmark
    const run_benchmark = b.addRunArtifact(benchmark_exe);
    run_benchmark.step.dependOn(&install_benchmark.step);

    const run_benchmark_step = b.step("run-benchmark", "Run performance benchmarks");
    run_benchmark_step.dependOn(&run_benchmark.step);

    // 文档生成
    const docs_obj = b.addObject(.{
        .name = "znvim",
        .root_module = mod,
    });

    const install_docs = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .install_subdir = "docs",
        .source_dir = docs_obj.getEmittedDocs(),
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);
}
