const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const msgpack = b.dependency(
        "zig-msgpack",
        .{ .target = target, .optimize = optimize },
    );

    const znvim = b.addModule("znvim", .{
        .root_source_file = b.path(b.pathJoin(&.{ "src", "znvim.zig" })),
        .imports = &.{.{
            .name = "msgpack",
            .module = msgpack.module("msgpack"),
        }},
    });

    const unit_tests = b.addTest(.{
        .root_source_file = b.path(b.pathJoin(&.{ "test", "test.zig" })),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.root_module.addImport("znvim", znvim);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.skip_foreign_checks = true;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const znvim_obj = b.addObject(.{
        .name = "znvim",
        .root_source_file = b.path(b.pathJoin(&.{ "src", "znvim.zig" })),
        .target = target,
        .optimize = optimize,
    });

    const docs_step = b.step("docs", "Generate docs");

    const docs_install = b.addInstallDirectory(.{
        .source_dir = znvim_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    docs_step.dependOn(&docs_install.step);

    // build main

    const exe = b.addExecutable(.{
        .name = "zig",
        .root_source_file = b.path(b.pathJoin(&.{ "test", "main.zig" })),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("znvim", znvim);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
