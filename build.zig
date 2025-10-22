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
        .{ .name = "simple_spawn", .path = "examples/simple_spawn.zig" },
        .{ .name = "api_lookup", .path = "examples/api_lookup.zig" },
        .{ .name = "buffer_lines", .path = "examples/buffer_lines.zig" },
        .{ .name = "eval_expression", .path = "examples/eval_expression.zig" },
        .{ .name = "print_api", .path = "examples/print_api.zig" },
        .{ .name = "run_command", .path = "examples/run_command.zig" },
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
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
