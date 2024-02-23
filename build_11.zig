const std = @import("std");
const Build = std.Build;
const CrossTarget  = std.zig.CrossTarget;
const Module = Build.Module;
const OptimizeMode = std.builtin.OptimizeMode;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // get msgpack
    const msgpack = b.dependency("zig-msgpack", .{});

    // create module
    const znvim = b.addModule("znvim", .{
        .source_file = .{
            .path = "src/znvim.zig",
        },
        .dependencies = &.{
            .{
                .name = "msgpack",
                .module = msgpack.module("msgpack"),
            },
        },
    });

    create_exe(b, target, optimize, znvim);
}

fn create_exe(b: *Build, target: CrossTarget, optimize: OptimizeMode, znvim: *Module) void {
    const exe = b.addExecutable(.{
        .name = "znvim",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("znvim", znvim);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
