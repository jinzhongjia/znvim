const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const msgpack = b.dependency(
        "zig-msgpack",
        .{ .target = target, .optimize = optimize },
    );

    const znvim = b.addModule("znvim", .{
        .root_source_file = b.path("src/znvim.zig"),
        .imports = &.{.{
            .name = "msgpack",
            .module = msgpack.module("msgpack"),
        }},
    });

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("test/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.root_module.addImport("znvim", znvim);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.skip_foreign_checks = true;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
