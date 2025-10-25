# Common Patterns

This document describes best practices and common design patterns for znvim.

## Pattern 1: Resource Management with RAII

Always use `defer` to ensure proper cleanup:

```zig
pub fn doWork(allocator: std.mem.Allocator) !void {
    // Initialize client
    var client = try znvim.Client.init(allocator, .{ .spawn_process = true });
    defer {
        client.disconnect();
        client.deinit();
    }
    
    try client.connect();
    
    // Work with client...
    // Cleanup happens automatically even if errors occur
}
```

## Pattern 2: Error Handling Wrapper

Create helper functions for common operations:

```zig
const ClientError = error{
    InitFailed,
    ConnectionFailed,
    RequestFailed,
};

fn createAndConnect(allocator: std.mem.Allocator, options: znvim.ConnectionOptions) !znvim.Client {
    var client = znvim.Client.init(allocator, options) catch {
        std.debug.print("Failed to initialize client\n", .{});
        return error.InitFailed;
    };
    errdefer client.deinit();
    
    client.connect() catch {
        std.debug.print("Failed to connect to Neovim\n", .{});
        client.deinit();
        return error.ConnectionFailed;
    };
    
    return client;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    var client = try createAndConnect(allocator, .{ .spawn_process = true });
    defer {
        client.disconnect();
        client.deinit();
    }
    
    // Use client...
}
```

## Pattern 3: Safe API Calls

Wrap API calls with error handling:

```zig
fn safeRequest(
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    method: []const u8,
    params: []const znvim.msgpack.Value,
) ?znvim.msgpack.Value {
    const result = client.request(method, params) catch |err| {
        std.debug.print("API call failed: {} - {s}\n", .{ err, method });
        return null;
    };
    
    return result;
}

// Usage
if (safeRequest(&client, allocator, "nvim_get_mode", &.{})) |result| {
    defer znvim.msgpack.free(result, allocator);
    // Handle result
} else {
    // Handle error
}
```

## Pattern 4: Builder Pattern for Complex Parameters

```zig
const BufferOptions = struct {
    listed: bool = true,
    scratch: bool = false,
    modifiable: bool = true,
    
    pub fn toMsgpack(self: BufferOptions, allocator: std.mem.Allocator) !znvim.msgpack.Value {
        var opts = znvim.msgpack.Value.mapPayload(allocator);
        errdefer opts.free(allocator);
        
        try opts.map.put("buflisted", znvim.msgpack.boolean(self.listed));
        try opts.map.put("buftype", 
            if (self.scratch) 
                try znvim.msgpack.string(allocator, "nofile")
            else 
                znvim.msgpack.nil()
        );
        try opts.map.put("modifiable", znvim.msgpack.boolean(self.modifiable));
        
        return opts;
    }
};

pub fn createBufferWithOptions(
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    options: BufferOptions,
) !i64 {
    const msgpack = znvim.msgpack;
    
    const create_params = [_]msgpack.Value{
        msgpack.boolean(options.listed),
        msgpack.boolean(options.scratch),
    };
    
    const buf_result = try client.request("nvim_create_buf", &create_params);
    defer msgpack.free(buf_result, allocator);
    
    const buf = switch (buf_result) {
        .int => buf_result.int,
        .uint => @as(i64, @intCast(buf_result.uint)),
        else => return error.UnexpectedType,
    };
    
    // Set additional options
    const opts = try options.toMsgpack(allocator);
    defer opts.free(allocator);
    
    // Apply options...
    
    return buf;
}

// Usage
const buf = try createBufferWithOptions(&client, allocator, .{
    .listed = false,
    .scratch = true,
    .modifiable = false,
});
```

## Pattern 5: Connection Pool

For applications needing multiple connections:

```zig
const ConnectionPool = struct {
    clients: []znvim.Client,
    allocator: std.mem.Allocator,
    next_index: std.atomic.Value(usize),
    mutex: std.Thread.Mutex,
    
    pub fn init(allocator: std.mem.Allocator, size: usize, options: znvim.ConnectionOptions) !ConnectionPool {
        const clients = try allocator.alloc(znvim.Client, size);
        errdefer allocator.free(clients);
        
        for (clients) |*client| {
            client.* = try znvim.Client.init(allocator, options);
            try client.connect();
        }
        
        return ConnectionPool{
            .clients = clients,
            .allocator = allocator,
            .next_index = std.atomic.Value(usize).init(0),
            .mutex = std.Thread.Mutex{},
        };
    }
    
    pub fn deinit(self: *ConnectionPool) void {
        for (self.clients) |*client| {
            client.disconnect();
            client.deinit();
        }
        self.allocator.free(self.clients);
    }
    
    pub fn acquire(self: *ConnectionPool) *znvim.Client {
        const index = self.next_index.fetchAdd(1, .monotonic) % self.clients.len;
        return &self.clients[index];
    }
    
    pub fn withClient(self: *ConnectionPool, comptime func: anytype, args: anytype) !@TypeOf(func).ReturnType {
        const client = self.acquire();
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return try @call(.auto, func, .{client} ++ args);
    }
};

// Usage
var pool = try ConnectionPool.init(allocator, 4, .{ .spawn_process = true });
defer pool.deinit();

const result = try pool.withClient(someFunction, .{ arg1, arg2 });
```

## Pattern 6: Retry Logic

Implement retry for transient errors:

```zig
fn requestWithRetry(
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    method: []const u8,
    params: []const znvim.msgpack.Value,
    max_retries: usize,
) !znvim.msgpack.Value {
    var attempt: usize = 0;
    var last_error: anyerror = undefined;
    
    while (attempt < max_retries) : (attempt += 1) {
        const result = client.request(method, params) catch |err| {
            last_error = err;
            
            // Retry on timeout or connection errors
            if (err == error.Timeout or err == error.ConnectionClosed) {
                if (attempt + 1 < max_retries) {
                    std.debug.print("Retry {}/{} after error: {}\n", .{ 
                        attempt + 1, max_retries, err 
                    });
                    
                    // Exponential backoff
                    const delay_ms = @as(u64, 100) * (@as(u64, 1) << @intCast(attempt));
                    std.Thread.sleep(delay_ms * std.time.ns_per_ms);
                    
                    // Try to reconnect
                    if (err == error.ConnectionClosed) {
                        client.connect() catch continue;
                    }
                    
                    continue;
                }
            }
            
            return err;
        };
        
        return result;
    }
    
    return last_error;
}
```

## Pattern 7: Batch Operations

Process multiple items efficiently:

```zig
fn batchSetBufferOptions(
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    buffers: []const i64,
    option_name: []const u8,
    option_value: znvim.msgpack.Value,
) !void {
    const msgpack = znvim.msgpack;
    
    for (buffers) |buf| {
        const opt_name = try msgpack.string(allocator, option_name);
        defer msgpack.free(opt_name, allocator);
        
        const params = [_]msgpack.Value{
            msgpack.int(buf),
            opt_name,
            option_value,
        };
        
        // Use notify for fire-and-forget
        try client.notify("nvim_buf_set_option", &params);
    }
}

// Usage
const buffers = [_]i64{ 1, 2, 3, 4 };
try batchSetBufferOptions(&client, allocator, &buffers, "modified", msgpack.boolean(false));
```

## Pattern 8: Configuration Management

Manage Neovim configuration:

```zig
const NvimConfig = struct {
    number: bool = true,
    relativenumber: bool = false,
    tabstop: i64 = 4,
    shiftwidth: i64 = 4,
    expandtab: bool = true,
    
    pub fn apply(self: NvimConfig, client: *znvim.Client, allocator: std.mem.Allocator) !void {
        const msgpack = znvim.msgpack;
        
        // Set number
        try self.setOption(client, allocator, "number", msgpack.boolean(self.number));
        
        // Set relativenumber
        try self.setOption(client, allocator, "relativenumber", msgpack.boolean(self.relativenumber));
        
        // Set tabstop
        try self.setOption(client, allocator, "tabstop", msgpack.int(self.tabstop));
        
        // Set shiftwidth
        try self.setOption(client, allocator, "shiftwidth", msgpack.int(self.shiftwidth));
        
        // Set expandtab
        try self.setOption(client, allocator, "expandtab", msgpack.boolean(self.expandtab));
    }
    
    fn setOption(
        self: NvimConfig,
        client: *znvim.Client,
        allocator: std.mem.Allocator,
        name: []const u8,
        value: znvim.msgpack.Value,
    ) !void {
        _ = self;
        const msgpack = znvim.msgpack;
        
        const opt_name = try msgpack.string(allocator, name);
        defer msgpack.free(opt_name, allocator);
        
        const params = [_]msgpack.Value{ opt_name, value };
        const result = try client.request("nvim_set_option", &params);
        defer msgpack.free(result, allocator);
    }
};

// Usage
const config = NvimConfig{
    .number = true,
    .relativenumber = true,
    .tabstop = 2,
    .expandtab = true,
};

try config.apply(&client, allocator);
```

## Pattern 9: Type-Safe Buffer Wrapper

Create a wrapper for buffer operations:

```zig
const Buffer = struct {
    handle: i64,
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    
    pub fn init(handle: i64, client: *znvim.Client, allocator: std.mem.Allocator) Buffer {
        return .{
            .handle = handle,
            .client = client,
            .allocator = allocator,
        };
    }
    
    pub fn getLines(self: Buffer, start: i64, end: i64) ![]znvim.msgpack.Value {
        const msgpack = znvim.msgpack;
        
        const params = [_]msgpack.Value{
            msgpack.int(self.handle),
            msgpack.int(start),
            msgpack.int(end),
            msgpack.boolean(false),
        };
        
        const result = try self.client.request("nvim_buf_get_lines", &params);
        // Caller must free result
        
        return try msgpack.expectArray(result);
    }
    
    pub fn setLines(self: Buffer, start: i64, end: i64, lines: []const []const u8) !void {
        const msgpack = znvim.msgpack;
        
        var lines_list = std.ArrayList(msgpack.Value).init(self.allocator);
        defer {
            for (lines_list.items) |line| {
                msgpack.free(line, self.allocator);
            }
            lines_list.deinit();
        }
        
        for (lines) |line| {
            const line_val = try msgpack.string(self.allocator, line);
            try lines_list.append(line_val);
        }
        
        const lines_array = try msgpack.array(self.allocator, lines_list.items);
        defer msgpack.free(lines_array, self.allocator);
        
        const params = [_]msgpack.Value{
            msgpack.int(self.handle),
            msgpack.int(start),
            msgpack.int(end),
            msgpack.boolean(false),
            lines_array,
        };
        
        const result = try self.client.request("nvim_buf_set_lines", &params);
        defer msgpack.free(result, self.allocator);
    }
    
    pub fn getName(self: Buffer) ![]const u8 {
        const msgpack = znvim.msgpack;
        
        const params = [_]msgpack.Value{ msgpack.int(self.handle) };
        const result = try self.client.request("nvim_buf_get_name", &params);
        defer msgpack.free(result, self.allocator);
        
        return try msgpack.expectString(result);
    }
    
    pub fn lineCount(self: Buffer) !i64 {
        const msgpack = znvim.msgpack;
        
        const params = [_]msgpack.Value{ msgpack.int(self.handle) };
        const result = try self.client.request("nvim_buf_line_count", &params);
        defer msgpack.free(result, self.allocator);
        
        return switch (result) {
            .int => result.int,
            .uint => @as(i64, @intCast(result.uint)),
            else => error.UnexpectedType,
        };
    }
};

// Usage
const buf_result = try client.request("nvim_get_current_buf", &.{});
defer znvim.msgpack.free(buf_result, allocator);

const buf_handle = switch (buf_result) {
    .int => buf_result.int,
    .uint => @as(i64, @intCast(buf_result.uint)),
    else => return error.UnexpectedType,
};

const buffer = Buffer.init(buf_handle, &client, allocator);

const count = try buffer.lineCount();
std.debug.print("Buffer has {} lines\n", .{count});

try buffer.setLines(0, 0, &.{ "New first line", "New second line" });
```

## Pattern 10: Command Queue

Queue commands for batch execution:

```zig
const CommandQueue = struct {
    commands: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) CommandQueue {
        return .{
            .commands = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *CommandQueue) void {
        for (self.commands.items) |cmd| {
            self.allocator.free(cmd);
        }
        self.commands.deinit();
    }
    
    pub fn add(self: *CommandQueue, command: []const u8) !void {
        const cmd_copy = try self.allocator.dupe(u8, command);
        try self.commands.append(cmd_copy);
    }
    
    pub fn execute(self: *CommandQueue, client: *znvim.Client) !void {
        const msgpack = znvim.msgpack;
        
        for (self.commands.items) |cmd| {
            const cmd_val = try msgpack.string(self.allocator, cmd);
            defer msgpack.free(cmd_val, self.allocator);
            
            const params = [_]msgpack.Value{cmd_val};
            try client.notify("nvim_command", &params);
        }
        
        std.debug.print("Executed {} commands\n", .{self.commands.items.len});
    }
};

// Usage
var queue = CommandQueue.init(allocator);
defer queue.deinit();

try queue.add("tabnew");
try queue.add("split");
try queue.add("vsplit");

try queue.execute(&client);
```

## Pattern 11: State Synchronization

Keep local state synchronized with Neovim:

```zig
const EditorState = struct {
    current_buffer: i64,
    current_window: i64,
    current_mode: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn sync(self: *EditorState, client: *znvim.Client) !void {
        const msgpack = znvim.msgpack;
        
        // Get current buffer
        const buf_result = try client.request("nvim_get_current_buf", &.{});
        defer msgpack.free(buf_result, self.allocator);
        
        self.current_buffer = switch (buf_result) {
            .int => buf_result.int,
            .uint => @as(i64, @intCast(buf_result.uint)),
            else => return error.UnexpectedType,
        };
        
        // Get current window
        const win_result = try client.request("nvim_get_current_win", &.{});
        defer msgpack.free(win_result, self.allocator);
        
        self.current_window = switch (win_result) {
            .int => win_result.int,
            .uint => @as(i64, @intCast(win_result.uint)),
            else => return error.UnexpectedType,
        };
        
        // Get mode
        const mode_result = try client.request("nvim_get_mode", &.{});
        defer msgpack.free(mode_result, self.allocator);
        
        const mode_map = try msgpack.expectMap(mode_result);
        var it = mode_map.iterator();
        while (it.next()) |entry| {
            if (std.mem.eql(u8, entry.key_ptr.*, "mode")) {
                const mode_str = try msgpack.expectString(entry.value_ptr.*);
                // Store mode (need to copy)
                if (self.current_mode.len > 0) {
                    self.allocator.free(self.current_mode);
                }
                self.current_mode = try self.allocator.dupe(u8, mode_str);
                break;
            }
        }
    }
    
    pub fn deinit(self: *EditorState) void {
        if (self.current_mode.len > 0) {
            self.allocator.free(self.current_mode);
        }
    }
};
```

## Pattern 12: Lua Integration Helper

Simplify Lua code execution:

```zig
const LuaHelper = struct {
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    
    pub fn exec(self: LuaHelper, code: []const u8) !znvim.msgpack.Value {
        const msgpack = znvim.msgpack;
        
        const code_val = try msgpack.string(self.allocator, code);
        defer msgpack.free(code_val, self.allocator);
        
        const empty_args = [_]msgpack.Value{};
        const args_array = try msgpack.array(self.allocator, &empty_args);
        defer msgpack.free(args_array, self.allocator);
        
        const params = [_]msgpack.Value{ code_val, args_array };
        return try self.client.request("nvim_exec_lua", &params);
    }
    
    pub fn call(
        self: LuaHelper,
        func_name: []const u8,
        args: []const znvim.msgpack.Value,
    ) !znvim.msgpack.Value {
        const msgpack = znvim.msgpack;
        
        const code = try std.fmt.allocPrint(self.allocator, "return {s}(...)", .{func_name});
        defer self.allocator.free(code);
        
        const code_val = try msgpack.string(self.allocator, code);
        defer msgpack.free(code_val, self.allocator);
        
        const args_array = try msgpack.array(self.allocator, args);
        defer msgpack.free(args_array, self.allocator);
        
        const params = [_]msgpack.Value{ code_val, args_array };
        return try self.client.request("nvim_exec_lua", &params);
    }
};

// Usage
const lua = LuaHelper{ .client = &client, .allocator = allocator };

// Execute code
const result1 = try lua.exec("return vim.fn.getcwd()");
defer znvim.msgpack.free(result1, allocator);

// Call function
const args = [_]znvim.msgpack.Value{ znvim.msgpack.int(10), znvim.msgpack.int(20) };
const result2 = try lua.call("math.max", &args);
defer znvim.msgpack.free(result2, allocator);
```

## Pattern 13: Health Check

Monitor connection health:

```zig
fn healthCheck(client: *znvim.Client, allocator: std.mem.Allocator) !bool {
    // Try a simple request
    const result = client.request("nvim_get_mode", &.{}) catch |err| {
        std.debug.print("Health check failed: {}\n", .{err});
        return false;
    };
    defer znvim.msgpack.free(result, allocator);
    
    return true;
}

// Usage in main loop
while (running) {
    if (!try healthCheck(&client, allocator)) {
        std.debug.print("Connection unhealthy, attempting reconnect...\n", .{});
        
        client.disconnect();
        client.connect() catch |err| {
            std.debug.print("Reconnect failed: {}\n", .{err});
            std.Thread.sleep(5000 * std.time.ns_per_ms);
            continue;
        };
        
        std.debug.print("Reconnected successfully\n", .{});
    }
    
    // Do work...
    std.Thread.sleep(1000 * std.time.ns_per_ms);
}
```

## Pattern 14: Testing Helpers

Create helpers for testing:

```zig
const TestHelper = struct {
    client: znvim.Client,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !TestHelper {
        var client = try znvim.Client.init(allocator, .{
            .spawn_process = true,
            .skip_api_info = true,
        });
        try client.connect();
        
        return TestHelper{
            .client = client,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *TestHelper) void {
        self.client.disconnect();
        self.client.deinit();
    }
    
    pub fn eval(self: *TestHelper, expr: []const u8) !znvim.msgpack.Value {
        const msgpack = znvim.msgpack;
        
        const expr_val = try msgpack.string(self.allocator, expr);
        defer msgpack.free(expr_val, self.allocator);
        
        const params = [_]msgpack.Value{expr_val};
        return try self.client.request("nvim_eval", &params);
    }
    
    pub fn command(self: *TestHelper, cmd: []const u8) !void {
        const msgpack = znvim.msgpack;
        
        const cmd_val = try msgpack.string(self.allocator, cmd);
        defer msgpack.free(cmd_val, self.allocator);
        
        const params = [_]msgpack.Value{cmd_val};
        try self.client.notify("nvim_command", &params);
    }
};

// Usage in tests
test "buffer operations" {
    var helper = try TestHelper.init(std.testing.allocator);
    defer helper.deinit();
    
    const result = try helper.eval("1 + 1");
    defer znvim.msgpack.free(result, std.testing.allocator);
    
    const value = try znvim.msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 2), value);
}
```

## Best Practices Summary

### Memory Management
- ✅ Always use `defer` for cleanup
- ✅ Use `errdefer` for error paths
- ✅ Understand MessagePack ownership rules
- ✅ Use Arena allocator for batch operations
- ✅ Free all MessagePack values

### Performance
- ✅ Skip API info when not needed
- ✅ Use `notify` instead of `request` when possible
- ✅ Batch operations in Lua scripts
- ✅ Use connection pooling for high concurrency
- ✅ Choose appropriate connection method

### Error Handling
- ✅ Handle all error cases explicitly
- ✅ Implement retry logic for transient errors
- ✅ Use health checks for long-running apps
- ✅ Log errors for debugging
- ✅ Provide fallback behavior

### Code Organization
- ✅ Create wrapper types for domain objects
- ✅ Use helper functions for common operations
- ✅ Separate concerns (connection, business logic, UI)
- ✅ Make code testable
- ✅ Document public APIs

## Anti-Patterns to Avoid

### ❌ Don't: Double-free MessagePack values

```zig
// WRONG - double free
const elem = try msgpack.string(allocator, "text");
defer msgpack.free(elem, allocator);  // Will crash!
const arr = try msgpack.array(allocator, &.{elem});
defer msgpack.free(arr, allocator);
```

### ❌ Don't: Ignore errors

```zig
// WRONG - ignoring errors
_ = client.request("nvim_command", &params);  // Error silently ignored

// CORRECT - handle errors
client.request("nvim_command", &params) catch |err| {
    std.debug.print("Command failed: {}\n", .{err});
    return err;
};
```

### ❌ Don't: Forget to free responses

```zig
// WRONG - memory leak
const result = try client.request("nvim_get_mode", &.{});
// Forgot to free!

// CORRECT
const result = try client.request("nvim_get_mode", &.{});
defer msgpack.free(result, allocator);
```

### ❌ Don't: Block UI thread

```zig
// WRONG - blocking UI
while (true) {
    const result = try client.request("some_api", &params);
    defer msgpack.free(result, allocator);
    // UI is frozen!
}

// CORRECT - use separate thread or non-blocking approach
const thread = try std.Thread.spawn(.{}, workerFunc, .{&client});
defer thread.join();
```

## Next Steps

- [Advanced Usage](04-advanced.md) - Performance optimization
- [Code Examples](05-examples.md) - More practical examples

---

[Back to Index](README.md)

