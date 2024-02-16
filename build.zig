const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const msgpack = b.dependency("zig-msgpack", .{});
    const znvim = b.addModule("znvim", .{
        .root_source_file = .{
            .path = "src/znvim.zig",
        },
        .imports = &.{
            .{
                .name = "msgpack",
                .module = msgpack.module("msgpack"),
            },
        },
    });

    const exe = b.addExecutable(.{
        .name = "znvim",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("znvim", znvim);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
