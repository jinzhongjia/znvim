const std = @import("std");
const znvim = @import("znvim");
const File = std.fs.File;
const ChildProcess = std.ChildProcess;
const allocator = std.testing.allocator;
const expect = std.testing.expect;

const args = [_][]const u8{ "nvim", "--embed" };

const ClientFileType = znvim.DefaultClientType(struct {}, .file);

test "basic embed connect" {
    var nvim = try create_nvim_process();

    const client = try ClientFileType.init(
        nvim.stdin.?,
        nvim.stdout.?,
        allocator,
        true,
    );
    defer client.deinit();
    _ = try nvim.kill();
}

test "call with reader" {
    var nvim = try create_nvim_process();

    const client = try ClientFileType.init(
        nvim.stdin.?,
        nvim.stdout.?,
        allocator,
        true,
    );
    defer client.deinit();

    const reader = try client.call_with_reader(.nvim_get_current_buf, .{}, allocator);
    const res = try reader.read_ext(allocator);
    defer allocator.free(res.data);

    _ = try nvim.kill();
}

test "call" {
    var nvim = try create_nvim_process();

    const client = try ClientFileType.init(
        nvim.stdin.?,
        nvim.stdout.?,
        allocator,
        true,
    );
    defer client.deinit();

    const buffer = try client.call(.nvim_get_current_buf, .{}, allocator);
    defer allocator.free(buffer.data);

    _ = try nvim.kill();
}

test "call with writer (get reader with writer)" {
    var nvim = try create_nvim_process();

    const client = try ClientFileType.init(
        nvim.stdin.?,
        nvim.stdout.?,
        allocator,
        true,
    );
    defer client.deinit();

    const writer = try client.call_with_writer(.nvim_get_current_buf);
    try writer.write_array_header(0);

    const reader = try client.get_reader_with_writer(writer, allocator);
    const res = try reader.read_ext(allocator);
    allocator.free(res.data);

    _ = try nvim.kill();
}

test "call with writer (get result with writer)" {
    var nvim = try create_nvim_process();

    const client = try ClientFileType.init(
        nvim.stdin.?,
        nvim.stdout.?,
        allocator,
        true,
    );
    defer client.deinit();

    const writer = try client.call_with_writer(.nvim_get_current_buf);
    try writer.write_array_header(0);

    const buffer = try client.get_result_with_writer(znvim.Buffer, writer, allocator);
    defer allocator.free(buffer.data);

    _ = try nvim.kill();
}

fn create_nvim_process() !ChildProcess {
    var nvim = ChildProcess.init(&args, allocator);

    // set to use pipe
    nvim.stdin_behavior = .Pipe;
    // set to use pipe
    nvim.stdout_behavior = .Pipe;
    // set ignore
    nvim.stderr_behavior = .Ignore;

    // try spwan
    try nvim.spawn();

    return nvim;
}
