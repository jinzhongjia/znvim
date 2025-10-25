# Code Examples

This document provides real-world, runnable znvim code examples.

## Example 1: Simple File Editor

Create a simple program to edit files:

```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Start embedded Neovim
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
    });
    defer {
        client.disconnect();
        client.deinit();
    }
    
    try client.connect();

    const msgpack = znvim.msgpack;

    // 1. Create new buffer
    const create_buf_params = [_]msgpack.Value{
        msgpack.boolean(false),  // listed
        msgpack.boolean(true),   // scratch
    };
    const buf_result = try client.request("nvim_create_buf", &create_buf_params);
    defer msgpack.free(buf_result, allocator);
    
    const buf = switch (buf_result) {
        .int => buf_result.int,
        .uint => @as(i64, @intCast(buf_result.uint)),
        else => return error.UnexpectedType,
    };

    std.debug.print("Created buffer: {}\n", .{buf});

    // 2. Set buffer content
    const line1 = try msgpack.string(allocator, "# Welcome to znvim");
    const line2 = try msgpack.string(allocator, "");
    const line3 = try msgpack.string(allocator, "This is an example using Zig and Neovim.");
    const line4 = try msgpack.string(allocator, "");
    const line5 = try msgpack.string(allocator, "## Features");
    const line6 = try msgpack.string(allocator, "- Create buffers");
    const line7 = try msgpack.string(allocator, "- Set content");
    const line8 = try msgpack.string(allocator, "- Save files");

    const lines = [_]msgpack.Value{ line1, line2, line3, line4, line5, line6, line7, line8 };
    const lines_array = try msgpack.array(allocator, &lines);
    defer msgpack.free(lines_array, allocator);

    const set_lines_params = [_]msgpack.Value{
        msgpack.int(buf),
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
        lines_array,
    };

    const set_result = try client.request("nvim_buf_set_lines", &set_lines_params);
    defer msgpack.free(set_result, allocator);

    // 3. Set buffer name (file path)
    const buf_name = try msgpack.string(allocator, "example.md");
    defer msgpack.free(buf_name, allocator);

    const name_params = [_]msgpack.Value{
        msgpack.int(buf),
        buf_name,
    };

    const name_result = try client.request("nvim_buf_set_name", &name_params);
    defer msgpack.free(name_result, allocator);

    // 4. Save buffer
    const write_cmd = try msgpack.string(allocator, "write");
    defer msgpack.free(write_cmd, allocator);

    const cmd_params = [_]msgpack.Value{write_cmd};
    try client.notify("nvim_command", &cmd_params);

    std.debug.print("File saved as example.md\n", .{});
}
```

## Example 2: Interactive REPL

Build a Neovim REPL:

```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .skip_api_info = true,
    });
    defer {
        client.disconnect();
        client.deinit();
    }
    
    try client.connect();

    const msgpack = znvim.msgpack;
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Neovim REPL - Enter expressions, type 'quit' to exit\n", .{});

    var input_buffer: [1024]u8 = undefined;

    while (true) {
        try stdout.print("> ", .{});

        const input = (try stdin.readUntilDelimiterOrEof(&input_buffer, '\n')) orelse break;
        const trimmed = std.mem.trim(u8, input, &std.ascii.whitespace);

        if (trimmed.len == 0) continue;
        if (std.mem.eql(u8, trimmed, "quit")) break;

        // Evaluate expression
        const expr = try msgpack.string(allocator, trimmed);
        defer msgpack.free(expr, allocator);

        const params = [_]msgpack.Value{expr};
        const result = client.request("nvim_eval", &params) catch |err| {
            try stdout.print("Error: {}\n", .{err});
            continue;
        };
        defer msgpack.free(result, allocator);

        // Print result
        switch (result) {
            .nil => try stdout.print("nil\n", .{}),
            .bool => |b| try stdout.print("{}\n", .{b}),
            .int => |i| try stdout.print("{}\n", .{i}),
            .uint => |u| try stdout.print("{}\n", .{u}),
            .float => |f| try stdout.print("{d}\n", .{f}),
            .str => |s| try stdout.print("{s}\n", .{s.value()}),
            .arr => |a| try stdout.print("[Array, length: {}]\n", .{a.len}),
            .map => |m| try stdout.print("[Map, size: {}]\n", .{m.count()}),
            else => try stdout.print("{}\n", .{result}),
        }
    }

    try stdout.print("Goodbye!\n", .{});
}
```

## Example 3: Code Formatter

Use Neovim's built-in formatting:

```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn formatFile(allocator: std.mem.Allocator, file_path: []const u8) !void {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
    });
    defer {
        client.disconnect();
        client.deinit();
    }
    
    try client.connect();

    const msgpack = znvim.msgpack;

    // 1. Read file
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(file_content);

    // 2. Create buffer
    const create_params = [_]msgpack.Value{
        msgpack.boolean(false),
        msgpack.boolean(true),
    };
    const buf_result = try client.request("nvim_create_buf", &create_params);
    defer msgpack.free(buf_result, allocator);
    
    const buf = switch (buf_result) {
        .int => buf_result.int,
        .uint => @as(i64, @intCast(buf_result.uint)),
        else => return error.UnexpectedType,
    };

    // 3. Split content into lines
    var lines_list = std.ArrayList(msgpack.Value).init(allocator);
    defer {
        for (lines_list.items) |line| {
            msgpack.free(line, allocator);
        }
        lines_list.deinit();
    }

    var line_it = std.mem.split(u8, file_content, "\n");
    while (line_it.next()) |line| {
        const line_val = try msgpack.string(allocator, line);
        try lines_list.append(line_val);
    }

    const lines_array = try msgpack.array(allocator, lines_list.items);
    defer msgpack.free(lines_array, allocator);

    // 4. Set buffer content
    const set_params = [_]msgpack.Value{
        msgpack.int(buf),
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
        lines_array,
    };

    const set_result = try client.request("nvim_buf_set_lines", &set_params);
    defer msgpack.free(set_result, allocator);

    // 5. Format using Vim command
    const format_cmd = try msgpack.string(allocator, "normal! gg=G");
    defer msgpack.free(format_cmd, allocator);

    const cmd_params = [_]msgpack.Value{format_cmd};
    try client.notify("nvim_command", &cmd_params);

    // 6. Get formatted content
    const get_params = [_]msgpack.Value{
        msgpack.int(buf),
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    };

    const get_result = try client.request("nvim_buf_get_lines", &get_params);
    defer msgpack.free(get_result, allocator);

    const formatted_lines = try msgpack.expectArray(get_result);

    // 7. Write back to file
    const out_file = try std.fs.cwd().createFile(file_path, .{});
    defer out_file.close();

    for (formatted_lines, 0..) |line, i| {
        const line_str = try msgpack.expectString(line);
        try out_file.writeAll(line_str);
        if (i < formatted_lines.len - 1) {
            try out_file.writeAll("\n");
        }
    }

    std.debug.print("File formatted: {s}\n", .{file_path});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <file_path>\n", .{args[0]});
        return;
    }

    try formatFile(allocator, args[1]);
}
```

## Example 4: Multi-Buffer Manager

Manage multiple buffers:

```zig
const std = @import("std");
const znvim = @import("znvim");

const BufferManager = struct {
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    
    pub fn init(client: *znvim.Client, allocator: std.mem.Allocator) BufferManager {
        return .{
            .client = client,
            .allocator = allocator,
        };
    }
    
    pub fn listBuffers(self: *BufferManager) !void {
        const msgpack = znvim.msgpack;
        
        const bufs_result = try self.client.request("nvim_list_bufs", &.{});
        defer msgpack.free(bufs_result, self.allocator);
        
        const bufs = try msgpack.expectArray(bufs_result);
        
        std.debug.print("Total {} buffers:\n", .{bufs.len});
        
        for (bufs, 0..) |buf_val, i| {
            const buf = switch (buf_val) {
                .int => buf_val.int,
                .uint => @as(i64, @intCast(buf_val.uint)),
                else => continue,
            };
            
            // Get buffer name
            const name_params = [_]msgpack.Value{ msgpack.int(buf) };
            const name_result = try self.client.request("nvim_buf_get_name", &name_params);
            defer msgpack.free(name_result, self.allocator);
            
            const name = try msgpack.expectString(name_result);
            
            // Get line count
            const count_params = [_]msgpack.Value{ msgpack.int(buf) };
            const count_result = try self.client.request("nvim_buf_line_count", &count_params);
            defer msgpack.free(count_result, self.allocator);
            
            const line_count = switch (count_result) {
                .int => count_result.int,
                .uint => @as(i64, @intCast(count_result.uint)),
                else => 0,
            };
            
            std.debug.print("  {}. Buffer {}: {s} ({} lines)\n", .{
                i + 1,
                buf,
                name,
                line_count,
            });
        }
    }
    
    pub fn closeUnmodifiedBuffers(self: *BufferManager) !void {
        const msgpack = znvim.msgpack;
        
        const bufs_result = try self.client.request("nvim_list_bufs", &.{});
        defer msgpack.free(bufs_result, self.allocator);
        
        const bufs = try msgpack.expectArray(bufs_result);
        var closed_count: usize = 0;
        
        for (bufs) |buf_val| {
            const buf = switch (buf_val) {
                .int => buf_val.int,
                .uint => @as(i64, @intCast(buf_val.uint)),
                else => continue,
            };
            
            // Check if modified
            const opt_name = try msgpack.string(self.allocator, "modified");
            defer msgpack.free(opt_name, self.allocator);
            
            const opt_params = [_]msgpack.Value{
                msgpack.int(buf),
                opt_name,
            };
            
            const opt_result = try self.client.request("nvim_buf_get_option", &opt_params);
            defer msgpack.free(opt_result, self.allocator);
            
            const is_modified = try msgpack.expectBool(opt_result);
            
            if (!is_modified) {
                // Delete unmodified buffer
                var del_opts = msgpack.Value.mapPayload(self.allocator);
                defer del_opts.free(self.allocator);
                
                try del_opts.map.put("force", msgpack.boolean(true));
                
                const del_params = [_]msgpack.Value{
                    msgpack.int(buf),
                    del_opts,
                };
                
                const del_result = try self.client.request("nvim_buf_delete", &del_params);
                defer msgpack.free(del_result, self.allocator);
                
                closed_count += 1;
            }
        }
        
        std.debug.print("Closed {} unmodified buffers\n", .{closed_count});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
    });
    defer {
        client.disconnect();
        client.deinit();
    }
    
    try client.connect();

    var manager = BufferManager.init(&client, allocator);
    
    try manager.listBuffers();
    try manager.closeUnmodifiedBuffers();
    try manager.listBuffers();
}
```

## Example 5: Workspace Window Setup

Set up a development workspace with multiple windows:

```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn setupWorkspace(allocator: std.mem.Allocator, client: *znvim.Client) !void {
    const msgpack = znvim.msgpack;

    // Create horizontal split
    const split_cmd = try msgpack.string(allocator, "split");
    defer msgpack.free(split_cmd, allocator);
    try client.notify("nvim_command", &[_]msgpack.Value{split_cmd});

    // Create vertical split
    const vsplit_cmd = try msgpack.string(allocator, "vsplit");
    defer msgpack.free(vsplit_cmd, allocator);
    try client.notify("nvim_command", &[_]msgpack.Value{vsplit_cmd});

    // Get all windows
    const wins_result = try client.request("nvim_list_wins", &.{});
    defer msgpack.free(wins_result, allocator);
    
    const wins = try msgpack.expectArray(wins_result);
    std.debug.print("Created {} windows\n", .{wins.len});

    // Set different buffer for each window
    for (wins, 0..) |win_val, i| {
        const win = switch (win_val) {
            .int => win_val.int,
            .uint => @as(i64, @intCast(win_val.uint)),
            else => continue,
        };

        // Create new buffer
        const create_params = [_]msgpack.Value{
            msgpack.boolean(true),
            msgpack.boolean(false),
        };
        const buf_result = try client.request("nvim_create_buf", &create_params);
        defer msgpack.free(buf_result, allocator);
        
        const buf = switch (buf_result) {
            .int => buf_result.int,
            .uint => @as(i64, @intCast(buf_result.uint)),
            else => continue,
        };

        // Set window to display this buffer
        const set_buf_params = [_]msgpack.Value{
            msgpack.int(win),
            msgpack.int(buf),
        };
        const set_result = try client.request("nvim_win_set_buf", &set_buf_params);
        defer msgpack.free(set_result, allocator);

        // Write content to buffer
        const content = try std.fmt.allocPrint(allocator, "Window {} - Buffer {}", .{ i + 1, buf });
        defer allocator.free(content);

        const line = try msgpack.string(allocator, content);
        const lines_arr = [_]msgpack.Value{line};
        const lines_array = try msgpack.array(allocator, &lines_arr);
        defer msgpack.free(lines_array, allocator);

        const lines_params = [_]msgpack.Value{
            msgpack.int(buf),
            msgpack.int(0),
            msgpack.int(-1),
            msgpack.boolean(false),
            lines_array,
        };

        const lines_result = try client.request("nvim_buf_set_lines", &lines_params);
        defer msgpack.free(lines_result, allocator);
    }

    std.debug.print("Workspace setup complete\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
    });
    defer {
        client.disconnect();
        client.deinit();
    }
    
    try client.connect();

    try setupWorkspace(allocator, &client);
    
    // Keep program running to view results
    std.debug.print("Press Enter to exit...\n", .{});
    _ = try std.io.getStdIn().reader().readByte();
}
```

## Example 6: Find and Replace

Global find and replace across buffers:

```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn findAndReplace(
    allocator: std.mem.Allocator,
    client: *znvim.Client,
    search: []const u8,
    replace: []const u8,
) !usize {
    const msgpack = znvim.msgpack;

    // Get all buffers
    const bufs_result = try client.request("nvim_list_bufs", &.{});
    defer msgpack.free(bufs_result, allocator);
    
    const bufs = try msgpack.expectArray(bufs_result);
    var total_replacements: usize = 0;

    for (bufs) |buf_val| {
        const buf = switch (buf_val) {
            .int => buf_val.int,
            .uint => @as(i64, @intCast(buf_val.uint)),
            else => continue,
        };

        // Get all lines from buffer
        const get_params = [_]msgpack.Value{
            msgpack.int(buf),
            msgpack.int(0),
            msgpack.int(-1),
            msgpack.boolean(false),
        };

        const lines_result = try client.request("nvim_buf_get_lines", &get_params);
        defer msgpack.free(lines_result, allocator);

        const lines = try msgpack.expectArray(lines_result);
        
        // Perform replacement
        var new_lines = std.ArrayList(msgpack.Value).init(allocator);
        defer {
            for (new_lines.items) |line| {
                msgpack.free(line, allocator);
            }
            new_lines.deinit();
        }

        var changed = false;
        for (lines) |line_val| {
            const line = try msgpack.expectString(line_val);
            
            if (std.mem.indexOf(u8, line, search)) |_| {
                const new_line = try std.mem.replaceOwned(u8, allocator, line, search, replace);
                defer allocator.free(new_line);
                
                const new_line_val = try msgpack.string(allocator, new_line);
                try new_lines.append(new_line_val);
                
                changed = true;
                total_replacements += std.mem.count(u8, line, search);
            } else {
                const line_copy = try msgpack.string(allocator, line);
                try new_lines.append(line_copy);
            }
        }

        // If changed, update buffer
        if (changed) {
            const new_lines_array = try msgpack.array(allocator, new_lines.items);
            defer msgpack.free(new_lines_array, allocator);

            const set_params = [_]msgpack.Value{
                msgpack.int(buf),
                msgpack.int(0),
                msgpack.int(-1),
                msgpack.boolean(false),
                new_lines_array,
            };

            const set_result = try client.request("nvim_buf_set_lines", &set_params);
            defer msgpack.free(set_result, allocator);
        }
    }

    return total_replacements;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
    });
    defer {
        client.disconnect();
        client.deinit();
    }
    
    try client.connect();

    const count = try findAndReplace(allocator, &client, "TODO", "DONE");
    std.debug.print("Total {} replacements\n", .{count});
}
```

## More Examples

Check the `examples/` directory in the repository for more complete programs:

- `simple_spawn.zig` - Basic process spawning
- `buffer_lines.zig` - Buffer operations
- `eval_expression.zig` - Expression evaluation
- `print_api.zig` - Print API information
- `run_command.zig` - Execute Vim commands
- `api_lookup.zig` - API lookup utility
- `batch_file_processing.zig` - Batch file processing
- `event_handling.zig` - Event handling
- `live_linter.zig` - Real-time code checking

## Next Steps

- [Common Patterns](06-patterns.md) - Best practices and design patterns
- [Advanced Usage](04-advanced.md) - Performance optimization

---

[Back to Index](README.md) | [Previous: Advanced](04-advanced.md) | [Next: Patterns](06-patterns.md)

