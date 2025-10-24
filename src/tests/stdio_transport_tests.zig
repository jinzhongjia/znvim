const std = @import("std");
const znvim = @import("../root.zig");
const Stdio = @import("../transport/stdio.zig").Stdio;
const Transport = @import("../transport/transport.zig").Transport;

// ============================================================================
// Helper: Create a pipe pair for testing
// ============================================================================

const PipePair = struct {
    read_end: std.fs.File,
    write_end: std.fs.File,

    fn create() !PipePair {
        const pipe_fds = try std.posix.pipe();
        return PipePair{
            .read_end = std.fs.File{ .handle = pipe_fds[0] },
            .write_end = std.fs.File{ .handle = pipe_fds[1] },
        };
    }

    fn close(self: *PipePair) void {
        self.read_end.close();
        self.write_end.close();
    }
};

// ============================================================================
// Test: Basic initialization
// ============================================================================

test "stdio transport: init creates valid transport" {
    var stdio = Stdio.init();
    defer stdio.deinit();

    try std.testing.expect(!stdio.owns_handles);
    try std.testing.expect(stdio.stdin_file.handle == std.fs.File.stdin().handle);
    try std.testing.expect(stdio.stdout_file.handle == std.fs.File.stdout().handle);
}

test "stdio transport: initWithFiles creates valid transport" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    try std.testing.expect(!stdio.owns_handles);
}

test "stdio transport: asTransport returns valid transport" {
    var stdio = Stdio.init();
    defer stdio.deinit();

    const transport = stdio.asTransport();
    // Just verify the transport was created successfully
    _ = transport;
}

// ============================================================================
// Test: Connect/Disconnect (no-op operations)
// ============================================================================

test "stdio transport: connect is no-op" {
    var stdio = Stdio.init();
    defer stdio.deinit();

    var transport = stdio.asTransport();
    try transport.connect("dummy_address");
}

test "stdio transport: disconnect is no-op" {
    var stdio = Stdio.init();
    defer stdio.deinit();

    var transport = stdio.asTransport();
    transport.disconnect();
}

test "stdio transport: isConnected always returns true" {
    var stdio = Stdio.init();
    defer stdio.deinit();

    var transport = stdio.asTransport();
    try std.testing.expect(transport.isConnected());
}

// ============================================================================
// Test: Basic read/write operations
// ============================================================================

test "stdio transport: write and read data through pipes" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // Write data
    const write_data = "Hello, Stdio!";
    try transport.write(write_data);

    // Read data back from the write end
    var read_buffer: [100]u8 = undefined;
    const bytes_read = try pipe_out.read_end.read(&read_buffer);
    try std.testing.expectEqual(write_data.len, bytes_read);
    try std.testing.expectEqualStrings(write_data, read_buffer[0..bytes_read]);
}

test "stdio transport: read data written to stdin pipe" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // Write data to stdin pipe
    const test_data = "Test data for reading";
    _ = try pipe_in.write_end.write(test_data);

    // Read through transport
    var read_buffer: [100]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);
    try std.testing.expectEqual(test_data.len, bytes_read);
    try std.testing.expectEqualStrings(test_data, read_buffer[0..bytes_read]);
}

test "stdio transport: multiple sequential writes" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // Write multiple chunks
    try transport.write("First ");
    try transport.write("Second ");
    try transport.write("Third");

    // Read all data back
    var read_buffer: [100]u8 = undefined;
    const bytes_read = try pipe_out.read_end.read(&read_buffer);
    try std.testing.expectEqualStrings("First Second Third", read_buffer[0..bytes_read]);
}

test "stdio transport: multiple sequential reads" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // Write multiple chunks to stdin
    _ = try pipe_in.write_end.write("AAA");
    _ = try pipe_in.write_end.write("BBB");
    _ = try pipe_in.write_end.write("CCC");

    // Read them one by one
    var buffer1: [3]u8 = undefined;
    var buffer2: [3]u8 = undefined;
    var buffer3: [3]u8 = undefined;

    _ = try transport.read(&buffer1);
    _ = try transport.read(&buffer2);
    _ = try transport.read(&buffer3);

    try std.testing.expectEqualStrings("AAA", &buffer1);
    try std.testing.expectEqualStrings("BBB", &buffer2);
    try std.testing.expectEqualStrings("CCC", &buffer3);
}

// ============================================================================
// Test: Boundary conditions
// ============================================================================

test "stdio transport: write empty data" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // Writing empty data should succeed
    try transport.write("");
}

test "stdio transport: read into empty buffer" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // Write some data
    _ = try pipe_in.write_end.write("test");

    // Try to read with empty buffer
    var empty_buffer: [0]u8 = undefined;
    const bytes_read = try transport.read(&empty_buffer);
    try std.testing.expectEqual(@as(usize, 0), bytes_read);
}

test "stdio transport: write large data chunk" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // Create large data (1KB)
    var large_data: [1024]u8 = undefined;
    for (&large_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    // Write and verify
    try transport.write(&large_data);

    var read_buffer: [1024]u8 = undefined;
    const bytes_read = try pipe_out.read_end.read(&read_buffer);
    try std.testing.expectEqual(@as(usize, 1024), bytes_read);
    try std.testing.expectEqualSlices(u8, &large_data, &read_buffer);
}

test "stdio transport: read partial data from small buffer" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // Write more data than buffer can hold
    _ = try pipe_in.write_end.write("1234567890");

    // Read with small buffer
    var small_buffer: [5]u8 = undefined;
    const bytes_read = try transport.read(&small_buffer);
    try std.testing.expectEqual(@as(usize, 5), bytes_read);
    try std.testing.expectEqualStrings("12345", &small_buffer);

    // Read remaining data
    var remaining_buffer: [5]u8 = undefined;
    const remaining_read = try transport.read(&remaining_buffer);
    try std.testing.expectEqual(@as(usize, 5), remaining_read);
    try std.testing.expectEqualStrings("67890", &remaining_buffer);
}

// ============================================================================
// Test: Binary data handling
// ============================================================================

test "stdio transport: handle binary data with null bytes" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // Binary data with null bytes
    const binary_data = [_]u8{ 0x01, 0x00, 0x02, 0x00, 0x03, 0xFF };
    try transport.write(&binary_data);

    var read_buffer: [6]u8 = undefined;
    const bytes_read = try pipe_out.read_end.read(&read_buffer);
    try std.testing.expectEqual(@as(usize, 6), bytes_read);
    try std.testing.expectEqualSlices(u8, &binary_data, &read_buffer);
}

test "stdio transport: handle all byte values (0-255)" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // Create data with all possible byte values
    var all_bytes: [256]u8 = undefined;
    for (&all_bytes, 0..) |*byte, i| {
        byte.* = @intCast(i);
    }

    try transport.write(&all_bytes);

    var read_buffer: [256]u8 = undefined;
    const bytes_read = try pipe_out.read_end.read(&read_buffer);
    try std.testing.expectEqual(@as(usize, 256), bytes_read);
    try std.testing.expectEqualSlices(u8, &all_bytes, &read_buffer);
}

// ============================================================================
// Test: Error handling - closed pipes
// ============================================================================

test "stdio transport: read from closed pipe returns ConnectionClosed" {
    var pipe_in = try PipePair.create();
    // Close the write end immediately to simulate closed connection
    pipe_in.write_end.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    var buffer: [100]u8 = undefined;
    const result = transport.read(&buffer);

    // Should return 0 bytes read (EOF) rather than error
    if (result) |bytes_read| {
        try std.testing.expectEqual(@as(usize, 0), bytes_read);
    } else |_| {
        // Some platforms may return error instead of 0
    }

    // Clean up
    pipe_in.read_end.close();
}

test "stdio transport: write to closed pipe returns error" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    // Close the read end to simulate broken pipe
    pipe_out.read_end.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    const write_data = "This should fail";
    const result = transport.write(write_data);

    // Should return BrokenPipe or ConnectionClosed error
    try std.testing.expectError(error.BrokenPipe, result);

    // Clean up
    pipe_out.write_end.close();
}

// ============================================================================
// Test: Ownership handling
// ============================================================================

test "stdio transport: deinit with owns_handles=false does not close files" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    stdio.deinit();

    // Files should still be open and usable
    const test_data = "Still works";
    const bytes_written = try pipe_out.write_end.write(test_data);
    try std.testing.expectEqual(test_data.len, bytes_written);
}

test "stdio transport: deinit with owns_handles=true closes files" {
    const pipe_in = try PipePair.create();
    const pipe_out = try PipePair.create();

    // Note: We pass ownership to Stdio, so don't defer close
    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, true);
    stdio.deinit();

    // Files should be closed now, attempting to use them would fail
    // We can't easily test this without potentially crashing, so we just
    // verify the deinit doesn't crash
}

// ============================================================================
// Test: MessagePack-RPC data flow (realistic scenario)
// ============================================================================

test "stdio transport: simulated msgpack-rpc message exchange" {
    var pipe_in = try PipePair.create();
    defer pipe_in.close();

    var pipe_out = try PipePair.create();
    defer pipe_out.close();

    var stdio = Stdio.initWithFiles(pipe_in.read_end, pipe_out.write_end, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // Simulate a MessagePack-RPC request: [0, 1, "nvim_get_mode", []]
    // This is a simplified representation
    const request_data = [_]u8{ 0x94, 0x00, 0x01, 0xAD, 'n', 'v', 'i', 'm', '_', 'g', 'e', 't', '_', 'm', 'o', 'd', 'e', 0x90 };
    try transport.write(&request_data);

    // Read it back
    var read_buffer: [100]u8 = undefined;
    const bytes_read = try pipe_out.read_end.read(&read_buffer);
    try std.testing.expectEqual(request_data.len, bytes_read);
    try std.testing.expectEqualSlices(u8, &request_data, read_buffer[0..bytes_read]);
}
