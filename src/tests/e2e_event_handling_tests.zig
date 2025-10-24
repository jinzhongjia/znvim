const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;

// Helper to create a test client with embedded Neovim
fn createTestClient(allocator: std.mem.Allocator) !znvim.Client {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 10000,
    });
    errdefer client.deinit();
    try client.connect();
    return client;
}

// Event collector structure to capture notifications
const EventCollector = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(CapturedEvent),
    mutex: std.Thread.Mutex,

    const CapturedEvent = struct {
        method: []const u8,
        params: msgpack.Value,
        timestamp: i64,

        fn deinit(self: *CapturedEvent, allocator: std.mem.Allocator) void {
            allocator.free(self.method);
            msgpack.free(self.params, allocator);
        }
    };

    fn init(allocator: std.mem.Allocator) EventCollector {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(CapturedEvent).initCapacity(allocator, 0) catch unreachable,
            .mutex = .{},
        };
    }

    fn deinit(self: *EventCollector) void {
        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.events.deinit(self.allocator);
    }

    fn addEvent(self: *EventCollector, method: []const u8, params: msgpack.Value) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const method_copy = try self.allocator.dupe(u8, method);
        errdefer self.allocator.free(method_copy);

        // Clone the params payload
        const params_copy = try clonePayload(self.allocator, params);
        errdefer msgpack.free(params_copy, self.allocator);

        try self.events.append(self.allocator, .{
            .method = method_copy,
            .params = params_copy,
            .timestamp = std.time.milliTimestamp(),
        });
    }

    fn getEventCount(self: *EventCollector) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.events.items.len;
    }

    fn findEvent(self: *EventCollector, method: []const u8) ?usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.events.items, 0..) |event, idx| {
            if (std.mem.eql(u8, event.method, method)) {
                return idx;
            }
        }
        return null;
    }
};

// Helper to deep clone a msgpack payload
fn clonePayload(allocator: std.mem.Allocator, payload: msgpack.Value) !msgpack.Value {
    switch (payload) {
        .nil => return msgpack.Value.nilToPayload(),
        .bool => |b| return msgpack.Value.boolToPayload(b),
        .int => |i| return msgpack.Value.intToPayload(i),
        .uint => |u| return msgpack.Value.uintToPayload(u),
        .float => |f| return msgpack.Value.floatToPayload(f),
        .str => |s| return try msgpack.string(allocator, s.value()),
        .bin => |b| return try msgpack.binary(allocator, b.value()),
        .arr => |arr| {
            var new_arr = try msgpack.Value.arrPayload(arr.len, allocator);
            errdefer new_arr.free(allocator);
            for (arr, 0..) |item, idx| {
                new_arr.arr[idx] = try clonePayload(allocator, item);
            }
            return new_arr;
        },
        .map => |map| {
            var new_map = msgpack.Value.mapPayload(allocator);
            errdefer new_map.free(allocator);
            var it = map.iterator();
            while (it.next()) |entry| {
                const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                errdefer allocator.free(key_copy);
                const value_copy = try clonePayload(allocator, entry.value_ptr.*);
                errdefer msgpack.free(value_copy, allocator);
                try new_map.map.put(key_copy, value_copy);
            }
            return new_map;
        },
        .ext => |e| {
            const data_copy = try allocator.dupe(u8, e.data);
            return msgpack.Value{
                .ext = .{
                    .type = e.type,
                    .data = data_copy,
                },
            };
        },
        .timestamp => |ts| {
            return msgpack.Value{ .timestamp = ts };
        },
    }
}

// Event handler callback for EventCollector
fn eventHandlerCallback(method: []const u8, params: msgpack.Value, userdata: ?*anyopaque) void {
    const collector: *EventCollector = @ptrCast(@alignCast(userdata.?));
    collector.addEvent(method, params) catch return;
}

// Helper to trigger event processing by making a dummy request
// This ensures any pending notifications are processed
fn processEvents(client: *znvim.Client) !void {
    const expr = try msgpack.string(client.allocator, "1");
    defer msgpack.free(expr, client.allocator);
    const result = try client.request("nvim_eval", &.{expr});
    defer msgpack.free(result, client.allocator);
}

// Test: Basic notification reception
test "basic event reception: capture simple notification" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var collector = EventCollector.init(allocator);
    defer collector.deinit();

    // Set event handler
    client.setEventHandler(eventHandlerCallback, &collector);
    defer client.setEventHandler(null, null);

    // Get channel ID
    const api_info = client.getApiInfo() orelse return error.NoApiInfo;
    const channel_id = api_info.channel_id;

    // Send a notification via lua
    const lua_code_str = try std.fmt.allocPrint(
        allocator,
        \\vim.rpcnotify({d}, "test_event", "hello", "world")
    ,
        .{channel_id},
    );
    defer allocator.free(lua_code_str);

    const lua_code = try msgpack.string(allocator, lua_code_str);
    defer msgpack.free(lua_code, allocator);

    const empty_arr = try msgpack.array(allocator, &.{});
    defer msgpack.free(empty_arr, allocator);

    _ = try client.request("nvim_exec_lua", &.{ lua_code, empty_arr });

    // Process events
    try processEvents(&client);

    // Verify we received the notification
    try std.testing.expect(collector.getEventCount() > 0);
    const event_idx = collector.findEvent("test_event");
    try std.testing.expect(event_idx != null);
}

// Test: Buffer attach events
// NOTE: nvim_buf_attach with 'on_lines' option only works from Lua, not external RPC clients
// See: https://neovim.io/doc/user/api.html#nvim_buf_attach()
// Error: "Invalid key: 'on_lines' is only allowed from Lua"
test "buffer events: nvim_buf_attach receives nvim_buf_lines_event" {
    return error.SkipZigTest; // Not supported from RPC
}

// Test: Multiple buffer events
// NOTE: Same limitation as above - buffer attach events only work from Lua
test "buffer events: multiple changes generate multiple events" {
    return error.SkipZigTest; // Not supported from RPC
}

// Test: Custom notification via lua
test "custom notification: receive via lua rpcnotify" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var collector = EventCollector.init(allocator);
    defer collector.deinit();

    client.setEventHandler(eventHandlerCallback, &collector);
    defer client.setEventHandler(null, null);

    const api_info = client.getApiInfo() orelse return error.NoApiInfo;
    const channel_id = api_info.channel_id;

    const lua_code = try std.fmt.allocPrint(
        allocator,
        \\vim.rpcnotify({d}, "custom_event", "param1", 42)
    ,
        .{channel_id},
    );
    defer allocator.free(lua_code);

    const lua_str = try msgpack.string(allocator, lua_code);
    defer msgpack.free(lua_str, allocator);

    const empty_arr = try msgpack.array(allocator, &.{});
    defer msgpack.free(empty_arr, allocator);

    _ = try client.request("nvim_exec_lua", &.{ lua_str, empty_arr });

    try processEvents(&client);

    try std.testing.expect(collector.getEventCount() > 0);
    const event_idx = collector.findEvent("custom_event");
    try std.testing.expect(event_idx != null);

    if (event_idx) |idx| {
        const event = collector.events.items[idx];
        const params = try msgpack.expectArray(event.params);
        try std.testing.expect(params.len >= 2);
        try std.testing.expectEqualStrings("param1", try msgpack.expectString(params[0]));
        try std.testing.expectEqual(@as(i64, 42), try msgpack.expectI64(params[1]));
    }
}

// Test: Concurrent events
test "concurrent events: multiple event sources" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var collector = EventCollector.init(allocator);
    defer collector.deinit();

    client.setEventHandler(eventHandlerCallback, &collector);
    defer client.setEventHandler(null, null);

    // Send multiple custom notifications from different "sources"
    const api_info = client.getApiInfo() orelse return error.NoApiInfo;

    // Send event from "source 1"
    const lua_code1 = try std.fmt.allocPrint(
        allocator,
        \\vim.rpcnotify({d}, "event_source_1", "data1")
    ,
        .{api_info.channel_id},
    );
    defer allocator.free(lua_code1);

    const lua_str1 = try msgpack.string(allocator, lua_code1);
    defer msgpack.free(lua_str1, allocator);

    const empty_arr1 = try msgpack.array(allocator, &.{});
    defer msgpack.free(empty_arr1, allocator);

    _ = try client.request("nvim_exec_lua", &.{ lua_str1, empty_arr1 });

    // Send event from "source 2"
    const lua_code2 = try std.fmt.allocPrint(
        allocator,
        \\vim.rpcnotify({d}, "event_source_2", "data2")
    ,
        .{api_info.channel_id},
    );
    defer allocator.free(lua_code2);

    const lua_str2 = try msgpack.string(allocator, lua_code2);
    defer msgpack.free(lua_str2, allocator);

    const empty_arr2 = try msgpack.array(allocator, &.{});
    defer msgpack.free(empty_arr2, allocator);

    _ = try client.request("nvim_exec_lua", &.{ lua_str2, empty_arr2 });

    // Wait and process events
    std.Thread.sleep(100 * std.time.ns_per_ms);
    try processEvents(&client);

    // Should have received events from both sources
    try std.testing.expect(collector.getEventCount() >= 2);

    // Verify both event types were received
    const idx1 = collector.findEvent("event_source_1");
    const idx2 = collector.findEvent("event_source_2");
    try std.testing.expect(idx1 != null);
    try std.testing.expect(idx2 != null);
}

// Test: Event handler can be changed
test "event handler: can be updated or removed" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var collector1 = EventCollector.init(allocator);
    defer collector1.deinit();

    var collector2 = EventCollector.init(allocator);
    defer collector2.deinit();

    // Set first handler
    client.setEventHandler(eventHandlerCallback, &collector1);

    const api_info = client.getApiInfo() orelse return error.NoApiInfo;

    // Send event 1
    const lua1 = try std.fmt.allocPrint(
        allocator,
        \\vim.rpcnotify({d}, "event1", 1)
    ,
        .{api_info.channel_id},
    );
    defer allocator.free(lua1);

    const lua_str1 = try msgpack.string(allocator, lua1);
    defer msgpack.free(lua_str1, allocator);

    const empty_arr1 = try msgpack.array(allocator, &.{});
    defer msgpack.free(empty_arr1, allocator);

    _ = try client.request("nvim_exec_lua", &.{ lua_str1, empty_arr1 });
    try processEvents(&client);

    // Change to second handler
    client.setEventHandler(eventHandlerCallback, &collector2);

    // Send event 2
    const lua2 = try std.fmt.allocPrint(
        allocator,
        \\vim.rpcnotify({d}, "event2", 2)
    ,
        .{api_info.channel_id},
    );
    defer allocator.free(lua2);

    const lua_str2 = try msgpack.string(allocator, lua2);
    defer msgpack.free(lua_str2, allocator);

    const empty_arr2 = try msgpack.array(allocator, &.{});
    defer msgpack.free(empty_arr2, allocator);

    _ = try client.request("nvim_exec_lua", &.{ lua_str2, empty_arr2 });
    try processEvents(&client);

    // Remove handler
    client.setEventHandler(null, null);

    // Send event 3 (should not be captured)
    const lua3 = try std.fmt.allocPrint(
        allocator,
        \\vim.rpcnotify({d}, "event3", 3)
    ,
        .{api_info.channel_id},
    );
    defer allocator.free(lua3);

    const lua_str3 = try msgpack.string(allocator, lua3);
    defer msgpack.free(lua_str3, allocator);

    const empty_arr3 = try msgpack.array(allocator, &.{});
    defer msgpack.free(empty_arr3, allocator);

    _ = try client.request("nvim_exec_lua", &.{ lua_str3, empty_arr3 });
    try processEvents(&client);

    // Verify: collector1 got event1, collector2 got event2, event3 was not captured
    try std.testing.expect(collector1.findEvent("event1") != null);
    try std.testing.expect(collector1.findEvent("event2") == null);
    try std.testing.expect(collector2.findEvent("event1") == null);
    try std.testing.expect(collector2.findEvent("event2") != null);
    try std.testing.expect(collector2.findEvent("event3") == null);
}

// Test: High frequency events
test "high frequency events: handle multiple rapid notifications" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var collector = EventCollector.init(allocator);
    defer collector.deinit();

    client.setEventHandler(eventHandlerCallback, &collector);
    defer client.setEventHandler(null, null);

    const api_info = client.getApiInfo() orelse return error.NoApiInfo;
    const event_count = 20;

    // Send many events via lua loop
    const lua_code = try std.fmt.allocPrint(
        allocator,
        \\for i = 1, {d} do
        \\  vim.rpcnotify({d}, "rapid_event", i)
        \\end
    ,
        .{ event_count, api_info.channel_id },
    );
    defer allocator.free(lua_code);

    const lua_str = try msgpack.string(allocator, lua_code);
    defer msgpack.free(lua_str, allocator);

    const empty_arr = try msgpack.array(allocator, &.{});
    defer msgpack.free(empty_arr, allocator);

    _ = try client.request("nvim_exec_lua", &.{ lua_str, empty_arr });

    // Process events multiple times to catch all
    var attempts: usize = 0;
    while (attempts < 5) : (attempts += 1) {
        try processEvents(&client);
        if (collector.getEventCount() >= event_count) break;
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }

    // Should have received most events (allow some tolerance)
    const received = collector.getEventCount();
    try std.testing.expect(received >= event_count * 80 / 100);
}
