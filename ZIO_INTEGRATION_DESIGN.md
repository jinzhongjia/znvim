# ZIO Integration Design Document

**Document Version**: 1.0.0  
**Date**: 2026-02-05  
**Status**: Draft  
**Author**: AI Assistant  

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Background and Motivation](#2-background-and-motivation)
3. [Current Architecture Analysis](#3-current-architecture-analysis)
4. [Target Architecture](#4-target-architecture)
5. [Detailed Design](#5-detailed-design)
6. [API Changes](#6-api-changes)
7. [Implementation Plan](#7-implementation-plan)
8. [Risk Assessment](#8-risk-assessment)
9. [Testing Strategy](#9-testing-strategy)
10. [Migration Guide](#10-migration-guide)

---

## 1. Executive Summary

This document describes the architectural redesign of znvim to integrate with [zio](https://github.com/lalinsky/zio), a high-performance async I/O framework for Zig. The goal is to replace the current synchronous blocking I/O model with zio's fiber-based async I/O while maintaining backward compatibility with existing APIs.

### Key Benefits

| Benefit | Description |
|---------|-------------|
| **True Async I/O** | Leverage io_uring (Linux), IOCP (Windows), kqueue (macOS) |
| **High Concurrency** | Handle thousands of concurrent requests efficiently |
| **Maintained API** | Existing `request()`/`notify()` APIs remain unchanged |
| **Cross-platform** | Consistent async behavior across all supported platforms |

### Estimated Effort

**Large (3+ days)** - Major refactoring of transport and client layers.

---

## 2. Background and Motivation

### Current Limitations

The current znvim implementation uses **synchronous blocking I/O**:

```zig
// Current implementation - blocks the calling thread
pub fn request(self: *Client, method: []const u8, params: []const msgpack.Value) !msgpack.Value {
    // ... encode and send request ...
    try (&self.transport).write(encoded);  // Blocking write
    return self.awaitResponse(msgid);       // Blocking read loop
}

fn awaitResponse(self: *Client, msgid: u32) !msgpack.Value {
    while (true) {  // Blocking loop
        // ... read from transport ...
        const read_bytes = (&self.transport).read(buffer[0..]);  // Blocking
        // ...
    }
}
```

**Problems:**
1. Each `request()` call blocks the entire thread until response arrives
2. Cannot handle multiple concurrent requests efficiently
3. No true multiplexing - one request at a time per connection
4. Thread-per-connection model doesn't scale

### Why zio?

zio provides:

1. **Fiber/Coroutine Runtime**: Lightweight green threads (similar to Go goroutines)
2. **Platform-native Async I/O**: io_uring, IOCP, kqueue, epoll support
3. **Synchronous-looking Code**: Async operations appear blocking but yield to scheduler
4. **Structured Concurrency**: Task groups for managing concurrent operations
5. **std.Io Integration**: Works with standard library Reader/Writer interfaces

---

## 3. Current Architecture Analysis

### Architecture Diagram

```
┌─────────────────────────────────────────────┐
│            Application Code                  │
├─────────────────────────────────────────────┤
│         Client Layer (client.zig)            │
│  - Synchronous request/response             │
│  - Mutex for thread safety                   │
│  - awaitResponse() blocking loop            │
├─────────────────────────────────────────────┤
│       Transport Layer (VTable pattern)       │
│  - UnixSocket, TcpSocket, WindowsPipe       │
│  - Stdio, ChildProcess                      │
│  - Blocking read()/write()                   │
└─────────────────────────────────────────────┘
```

### Key Components

| Component | File | Description |
|-----------|------|-------------|
| `Client` | `src/client.zig` | Main RPC client (788 LOC) |
| `Transport` | `src/transport/transport.zig` | VTable abstraction (64 LOC) |
| `UnixSocket` | `src/transport/unix_socket.zig` | Unix domain socket |
| `TcpSocket` | `src/transport/tcp_socket.zig` | TCP/IP (280 LOC) |
| `WindowsPipe` | `src/transport/windows_pipe.zig` | Named pipes (460 LOC) |
| `ChildProcess` | `src/transport/child_process.zig` | nvim --embed spawning |

### Current Request Flow

```
Application Thread
       │
       ▼
┌──────────────────┐
│ client.request() │
│                  │
│ 1. Lock mutex    │
│ 2. Encode msg    │
│ 3. Write (block) │◄──────────────┐
│ 4. awaitResponse │               │
│    └─► read loop │ BLOCKING      │
│        (block)   │◄──────────────┘
│ 5. Decode result │
│ 6. Unlock mutex  │
│ 7. Return        │
└──────────────────┘
```

---

## 4. Target Architecture

### High-Level Design

```
┌────────────────────────────────────────────────────────────────┐
│                      Application Thread(s)                      │
│                                                                 │
│  client.request() ─────────► submit + wait on completion       │
│  client.requestAsync() ────► return Task (for zio callers)     │
└───────────────────────────────│─────────────────────────────────┘
                                │
                    ┌───────────▼───────────┐
                    │   Cross-thread Queue   │
                    │   (pending requests)   │
                    └───────────┬───────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│                     zio Runtime Thread                          │
│  ┌────────────────────────────────────────────────────────┐    │
│  │                    Session                              │    │
│  │  ┌─────────────────┐    ┌───────────────────────────┐  │    │
│  │  │   Writer Fiber   │    │    Reader Fiber           │  │    │
│  │  │                 │    │    (long-running)         │  │    │
│  │  │ - Dequeue req   │    │ - Decode responses        │  │    │
│  │  │ - Encode msgpck │    │ - Match msgid → pending   │  │    │
│  │  │ - async write   │    │ - Signal completion       │  │    │
│  │  │                 │    │ - Handle notifications    │  │    │
│  │  └────────┬────────┘    └───────────┬───────────────┘  │    │
│  │           │                         │                   │    │
│  │           └─────────┬───────────────┘                   │    │
│  │                     ▼                                   │    │
│  │            ┌────────────────┐                           │    │
│  │            │ zio.net.Stream │                           │    │
│  │            └────────────────┘                           │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  Event Loop: io_uring (Linux) / IOCP (Windows) / kqueue (macOS)│
└─────────────────────────────────────────────────────────────────┘
```

### Design Principles

1. **Lazy Runtime Initialization**: zio Runtime created in `connect()`, not `init()`
2. **Background Thread**: Runtime runs on dedicated thread, never blocks callers
3. **Synchronous Facade**: `request()` submits work and blocks caller using `ResetEvent`
4. **Async Option**: `requestAsync()` for callers already inside zio fiber
5. **Single Reader**: One long-lived reader fiber handles all incoming messages
6. **Pending Map**: `msgid → Completion` map for request/response matching

---

## 5. Detailed Design

### 5.1 New Data Structures

```zig
/// Completion handle for pending requests
const PendingRequest = struct {
    /// Signaled when response arrives
    event: std.Thread.ResetEvent = .{},
    /// Response payload (set by reader fiber)
    result: ?msgpack.Payload = null,
    /// Error if request failed
    err: ?anyerror = null,
    /// Allocator for cleanup
    allocator: std.mem.Allocator,
    
    pub fn wait(self: *PendingRequest) !msgpack.Payload {
        self.event.wait();
        if (self.err) |e| return e;
        return self.result orelse error.NoResult;
    }
    
    pub fn complete(self: *PendingRequest, result: msgpack.Payload) void {
        self.result = result;
        self.event.set();
    }
    
    pub fn fail(self: *PendingRequest, err: anyerror) void {
        self.err = err;
        self.event.set();
    }
};

/// Request to be sent (queued for writer fiber)
const SendRequest = struct {
    msgid: u32,
    method: []const u8,
    params: msgpack.Payload,
    pending: *PendingRequest,
};
```

### 5.2 Updated ConnectionOptions

```zig
pub const ConnectionOptions = struct {
    // Existing fields (unchanged)
    socket_path: ?[]const u8 = null,
    tcp_address: ?[]const u8 = null,
    tcp_port: ?u16 = null,
    use_stdio: bool = false,
    spawn_process: bool = false,
    nvim_path: []const u8 = "nvim",
    timeout_ms: u32 = 5000,
    skip_api_info: bool = false,
    
    // NEW: zio runtime configuration
    /// External runtime to use (null = create internal)
    zio_runtime: ?*zio.Runtime = null,
    
    /// Runtime management mode
    runtime_mode: RuntimeMode = .owned_background_thread,
    
    /// Number of worker threads for internal runtime
    worker_threads: ?u16 = null,  // null = auto-detect
    
    pub const RuntimeMode = enum {
        /// Client creates and manages its own runtime on background thread
        owned_background_thread,
        /// Use externally provided runtime (caller must ensure it's running)
        external,
    };
};
```

### 5.3 Updated Client Structure

```zig
pub const Client = struct {
    allocator: std.mem.Allocator,
    options: connection.ConnectionOptions,
    
    // ===== zio Runtime Management =====
    /// The active runtime (owned or external)
    runtime: ?*zio.Runtime = null,
    /// Owned runtime instance (if runtime_mode == .owned_background_thread)
    owned_runtime: ?zio.Runtime = null,
    /// Background thread running the owned runtime
    runtime_thread: ?std.Thread = null,
    /// Signal to stop runtime thread
    shutdown: std.atomic.Value(bool) = .init(false),
    
    // ===== Connection State =====
    /// zio network stream
    stream: ?zio.net.Stream = null,
    /// Child process handle (for spawn_process mode)
    child_process: ?std.process.Child = null,
    /// Connection status
    connected: bool = false,
    
    // ===== Request/Response Management =====
    /// Protects pending map
    pending_mu: std.Thread.Mutex = .{},
    /// Map of msgid -> pending request completion
    pending: std.AutoHashMapUnmanaged(u32, *PendingRequest) = .{},
    /// Atomic message ID counter
    next_msgid: std.atomic.Value(u32) = .init(0),
    /// Queue for outgoing requests
    send_queue: zio.Channel(SendRequest) = undefined,
    
    // ===== API Metadata (unchanged) =====
    api_arena: std.heap.ArenaAllocator,
    api_info: ?ApiInfo = null,
    
    // ===== Event Handling (unchanged) =====
    event_handler: ?EventHandler = null,
    event_userdata: ?*anyopaque = null,
    
    // ===== Public API =====
    
    /// Initialize client (lightweight, no runtime created yet)
    pub fn init(allocator: std.mem.Allocator, options: ConnectionOptions) !Client;
    
    /// Connect to Neovim (creates runtime, establishes connection)
    pub fn connect(self: *Client) !void;
    
    /// Disconnect and cleanup
    pub fn disconnect(self: *Client) void;
    
    /// Cleanup all resources
    pub fn deinit(self: *Client) void;
    
    /// Synchronous request (blocks caller, safe from any non-runtime thread)
    pub fn request(self: *Client, method: []const u8, params: []const msgpack.Value) !msgpack.Value;
    
    /// Asynchronous request (for callers inside zio fiber)
    pub fn requestAsync(self: *Client, method: []const u8, params: []const msgpack.Value) RequestTask;
    
    /// Fire-and-forget notification
    pub fn notify(self: *Client, method: []const u8, params: []const msgpack.Value) !void;
    
    // ... other existing methods unchanged ...
};
```

### 5.4 Connection Establishment

```zig
pub fn connect(self: *Client) !void {
    if (self.connected) return error.AlreadyConnected;
    
    // Step 1: Ensure runtime exists
    try self.ensureRuntime();
    
    // Step 2: Establish connection based on options
    if (self.options.spawn_process) {
        try self.spawnChildProcess();
    } else if (self.options.socket_path) |path| {
        try self.connectUnixSocket(path);
    } else if (self.options.tcp_address) |host| {
        const port = self.options.tcp_port orelse return error.MissingPort;
        try self.connectTcp(host, port);
    } else if (self.options.use_stdio) {
        try self.connectStdio();
    } else {
        return error.NoConnectionMethod;
    }
    
    // Step 3: Start reader fiber
    try self.startReaderFiber();
    
    // Step 4: Fetch API info (unless skipped)
    if (!self.options.skip_api_info) {
        try self.refreshApiInfo();
    }
    
    self.connected = true;
}

fn ensureRuntime(self: *Client) !void {
    if (self.runtime != null) return;
    
    switch (self.options.runtime_mode) {
        .external => {
            self.runtime = self.options.zio_runtime orelse return error.NoExternalRuntime;
        },
        .owned_background_thread => {
            // Create owned runtime
            self.owned_runtime = try zio.Runtime.init(self.allocator, .{
                .num_threads = self.options.worker_threads,
            });
            self.runtime = &self.owned_runtime.?;
            
            // Start background thread to run the runtime
            self.runtime_thread = try std.Thread.spawn(.{}, runRuntimeThread, .{self});
        },
    }
}

fn runRuntimeThread(self: *Client) void {
    // This thread drives the zio event loop
    while (!self.shutdown.load(.acquire)) {
        self.runtime.?.tick() catch |err| {
            std.log.err("Runtime tick error: {}", .{err});
        };
    }
}
```

### 5.5 Reader Fiber Implementation

```zig
fn startReaderFiber(self: *Client) !void {
    // Spawn reader fiber in the runtime
    try self.runtime.?.spawn(readerFiberMain, .{self});
}

fn readerFiberMain(self: *Client) void {
    var read_buffer: [8192]u8 = undefined;
    var reader = self.stream.?.reader(&read_buffer);
    var msg_buffer = std.ArrayList(u8).init(self.allocator);
    defer msg_buffer.deinit();
    
    while (!self.shutdown.load(.acquire)) {
        // Read data (async - yields to scheduler when waiting)
        const data = reader.interface.readSome() catch |err| {
            if (err == error.EndOfStream) break;
            self.failAllPending(err);
            return;
        };
        
        msg_buffer.appendSlice(data) catch {
            self.failAllPending(error.OutOfMemory);
            return;
        };
        
        // Try to decode complete messages
        while (true) {
            const decode_result = protocol.decode(self.allocator, msg_buffer.items) catch |err| {
                if (err == msgpack.MsgPackError.LengthReading) break;  // Need more data
                self.failAllPending(err);
                return;
            };
            
            // Remove decoded bytes from buffer
            msg_buffer.replaceRange(0, decode_result.bytes_read, &.{}) catch unreachable;
            
            // Handle the message
            self.handleMessage(decode_result.message) catch |err| {
                std.log.err("Message handling error: {}", .{err});
            };
        }
    }
}

fn handleMessage(self: *Client, message: protocol.AnyMessage) !void {
    switch (message) {
        .Response => |resp| {
            self.pending_mu.lock();
            defer self.pending_mu.unlock();
            
            if (self.pending.get(resp.msgid)) |pending| {
                if (resp.@"error") |_| {
                    pending.fail(error.NvimError);
                } else if (resp.result) |result| {
                    const cloned = try payload_utils.clonePayload(self.allocator, result);
                    pending.complete(cloned);
                } else {
                    pending.complete(msgpack.Payload.nilToPayload());
                }
                _ = self.pending.remove(resp.msgid);
            }
        },
        .Notification => |notif| {
            if (self.event_handler) |handler| {
                handler(notif.method, notif.params, self.event_userdata);
            }
        },
        .Request => {
            // Server-initiated requests (rare, log for now)
            std.log.warn("Received unexpected server request", .{});
        },
    }
}
```

### 5.6 Request Implementation

```zig
/// Synchronous request - blocks caller thread
pub fn request(self: *Client, method: []const u8, params: []const msgpack.Value) !msgpack.Value {
    if (!self.connected) return error.NotConnected;
    
    // Detect if called from runtime thread (would deadlock)
    if (self.isOnRuntimeThread()) {
        return error.CalledFromRuntimeThread;
    }
    
    const msgid = self.next_msgid.fetchAdd(1, .monotonic);
    
    // Create pending request
    var pending = try self.allocator.create(PendingRequest);
    defer self.allocator.destroy(pending);
    pending.* = .{ .allocator = self.allocator };
    
    // Register in pending map
    {
        self.pending_mu.lock();
        defer self.pending_mu.unlock();
        try self.pending.put(self.allocator, msgid, pending);
    }
    errdefer {
        self.pending_mu.lock();
        defer self.pending_mu.unlock();
        _ = self.pending.remove(msgid);
    }
    
    // Encode and send request
    const params_payload = try self.cloneParams(params);
    const request_msg = protocol.message.Request{
        .msgid = msgid,
        .method = method,
        .params = params_payload,
    };
    const encoded = try protocol.encodeRequest(self.allocator, request_msg);
    defer self.allocator.free(encoded);
    
    // Write to stream (done by writer fiber or directly)
    try self.sendData(encoded);
    
    // Wait for response (blocks this thread, not the runtime)
    return pending.wait();
}

/// Async request - returns a Task for zio callers
pub const RequestTask = struct {
    pending: *PendingRequest,
    
    pub fn wait(self: RequestTask) !msgpack.Value {
        // In zio context, this yields instead of blocking
        return self.pending.waitAsync();
    }
};

pub fn requestAsync(self: *Client, method: []const u8, params: []const msgpack.Value) !RequestTask {
    // Similar to request() but returns Task instead of blocking
    // ...
}
```

### 5.7 ChildProcess with zio

```zig
fn spawnChildProcess(self: *Client) !void {
    // Use std.process for spawning (cross-platform)
    var child = std.process.Child.init(.{
        .argv = &.{ self.options.nvim_path, "--embed" },
        .stdin_behavior = .pipe,
        .stdout_behavior = .pipe,
        .stderr_behavior = .pipe,
    }, self.allocator);
    
    try child.spawn();
    self.child_process = child;
    
    // Wrap child's stdin/stdout with zio async handles
    // Note: This depends on zio's ability to wrap existing file descriptors
    const stdin_fd = child.stdin.?.handle;
    const stdout_fd = child.stdout.?.handle;
    
    // Create a zio stream from the file descriptors
    // (Implementation depends on zio's API for wrapping existing FDs)
    self.stream = try zio.net.Stream.fromPipes(stdin_fd, stdout_fd);
}
```

---

## 6. API Changes

### 6.1 Backward Compatible (No Changes Required)

```zig
// These APIs remain unchanged in signature and behavior:
pub fn init(allocator: Allocator, options: ConnectionOptions) !Client;
pub fn connect(self: *Client) !void;
pub fn disconnect(self: *Client) void;
pub fn deinit(self: *Client) void;
pub fn request(self: *Client, method: []const u8, params: []const msgpack.Value) !msgpack.Value;
pub fn notify(self: *Client, method: []const u8, params: []const msgpack.Value) !void;
pub fn getApiInfo(self: *const Client) ?ApiInfo;
pub fn findApiFunction(self: *const Client, name: []const u8) ?*const ApiFunction;
pub fn setEventHandler(self: *Client, handler: ?EventHandler, userdata: ?*anyopaque) void;
```

### 6.2 New APIs

```zig
// NEW: Async request for zio callers
pub fn requestAsync(self: *Client, method: []const u8, params: []const msgpack.Value) !RequestTask;

// NEW: Check if on runtime thread
pub fn isOnRuntimeThread(self: *const Client) bool;
```

### 6.3 New Options

```zig
pub const ConnectionOptions = struct {
    // ... existing fields ...
    
    // NEW
    zio_runtime: ?*zio.Runtime = null,
    runtime_mode: RuntimeMode = .owned_background_thread,
    worker_threads: ?u16 = null,
};
```

### 6.4 New Error Types

```zig
pub const ClientError = error{
    // ... existing errors ...
    
    // NEW
    CalledFromRuntimeThread,  // Sync API called from runtime thread
    NoExternalRuntime,        // external mode but no runtime provided
    RuntimeInitFailed,        // Failed to create zio runtime
};
```

---

## 7. Implementation Plan

### Phase 1: Foundation (Day 1)

| Task | Description | Files |
|------|-------------|-------|
| 1.1 | Add zio dependency | `build.zig.zon`, `build.zig` |
| 1.2 | Update ConnectionOptions | `src/connection.zig` |
| 1.3 | Add PendingRequest struct | `src/client.zig` |
| 1.4 | Update Client struct | `src/client.zig` |

### Phase 2: Runtime Management (Day 1-2)

| Task | Description | Files |
|------|-------------|-------|
| 2.1 | Implement ensureRuntime() | `src/client.zig` |
| 2.2 | Implement runRuntimeThread() | `src/client.zig` |
| 2.3 | Implement shutdown logic | `src/client.zig` |
| 2.4 | Update connect()/disconnect() | `src/client.zig` |

### Phase 3: Transport Layer (Day 2)

| Task | Description | Files |
|------|-------------|-------|
| 3.1 | Implement Unix socket via zio | `src/client.zig` |
| 3.2 | Implement TCP via zio | `src/client.zig` |
| 3.3 | Implement ChildProcess with zio pipes | `src/client.zig` |
| 3.4 | Implement stdio via zio | `src/client.zig` |
| 3.5 | Windows named pipes (if zio supports) | `src/client.zig` |

### Phase 4: Message Handling (Day 2-3)

| Task | Description | Files |
|------|-------------|-------|
| 4.1 | Implement reader fiber | `src/client.zig` |
| 4.2 | Implement handleMessage() | `src/client.zig` |
| 4.3 | Refactor request() | `src/client.zig` |
| 4.4 | Refactor notify() | `src/client.zig` |
| 4.5 | Implement requestAsync() | `src/client.zig` |

### Phase 5: Testing & Documentation (Day 3+)

| Task | Description | Files |
|------|-------------|-------|
| 5.1 | Update existing tests | `src/tests/*.zig` |
| 5.2 | Add zio-specific tests | `src/tests/zio_*.zig` |
| 5.3 | Add concurrent request tests | `src/tests/concurrent_*.zig` |
| 5.4 | Update documentation | `doc/*.md`, `README.md` |
| 5.5 | Update examples | `examples/*.zig` |

### Phase 6: Cleanup (Day 3+)

| Task | Description | Files |
|------|-------------|-------|
| 6.1 | Remove old transport files | `src/transport/*.zig` |
| 6.2 | Update AGENTS.md | `AGENTS.md` |
| 6.3 | Performance benchmarking | - |

---

## 8. Risk Assessment

### High Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| **zio doesn't support Windows named pipes** | Windows ChildProcess may not work | Keep std transport as fallback for Windows, or use TCP |
| **Deadlock if sync API called from runtime thread** | Application hangs | Detect and return `CalledFromRuntimeThread` error |
| **zio API instability** | Breaking changes in future versions | Pin to specific version, document compatibility |

### Medium Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Performance regression** | Slower than sync for simple cases | Benchmark, optimize hot paths |
| **Memory overhead** | Runtime uses more memory | Document requirements, make threads configurable |
| **Complex shutdown semantics** | Resource leaks, hanging | Careful implementation, extensive testing |

### Low Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| **API compatibility** | Minor changes needed | Semver major bump if necessary |
| **Documentation lag** | Confusion for users | Update docs as part of implementation |

---

## 9. Testing Strategy

### Unit Tests

- PendingRequest functionality
- Message encoding/decoding (unchanged)
- Connection options parsing

### Integration Tests

- Connect/disconnect lifecycle
- Single request/response
- Multiple concurrent requests
- Notification handling
- Error handling (connection closed, timeout)
- ChildProcess spawning

### Stress Tests

- 1000+ concurrent requests
- Long-running connections
- Memory leak detection
- Reconnection scenarios

### Platform-Specific Tests

- Linux: io_uring path
- macOS: kqueue path  
- Windows: IOCP path, named pipes

---

## 10. Migration Guide

### For Existing Users

**Good news: No changes required for basic usage!**

```zig
// This code continues to work unchanged:
var client = try znvim.Client.init(allocator, .{
    .spawn_process = true,
});
defer client.deinit();
try client.connect();

const result = try client.request("nvim_eval", &params);
defer msgpack.free(result, allocator);
```

### For Users Wanting Async

```zig
// Option 1: Use requestAsync() inside zio fiber
const rt = try zio.Runtime.init(allocator, .{});
defer rt.deinit();

var client = try znvim.Client.init(allocator, .{
    .spawn_process = true,
    .zio_runtime = rt,
    .runtime_mode = .external,
});

// Inside a zio fiber:
const task = try client.requestAsync("nvim_eval", &params);
const result = try task.wait();  // Yields, doesn't block

// Option 2: Fire multiple requests concurrently
var tasks: [10]RequestTask = undefined;
for (&tasks, 0..) |*task, i| {
    task.* = try client.requestAsync("nvim_eval", &params[i]);
}
for (tasks) |task| {
    const result = try task.wait();
    // process result
}
```

### Breaking Changes

1. **New dependency**: zio is now required
2. **New error**: `CalledFromRuntimeThread` may be returned
3. **Removed files**: Old transport implementations removed

---

## Appendix A: zio API Reference

Key zio APIs used:

```zig
// Runtime
const rt = try zio.Runtime.init(allocator, .{});
defer rt.deinit();

// TCP connection
const addr = try zio.net.IpAddress.parseIp4("127.0.0.1", 6666);
const stream = try addr.connect(.{});
defer stream.close();

// Unix socket
const stream = try zio.net.UnixAddress.connect("/tmp/nvim.sock", .{});

// Buffered I/O
var reader = stream.reader(&read_buffer);
var writer = stream.writer(&write_buffer);

// Reading
const data = try reader.interface.readSome();

// Writing  
try writer.interface.writeAll(data);
try writer.interface.flush();

// Task groups
var group: zio.Group = .init;
defer group.cancel();
try group.spawn(myFunction, .{arg1, arg2});

// Sleep
try zio.sleep(.fromMilliseconds(100));
```

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| **Fiber** | Lightweight cooperative thread managed by zio runtime |
| **Runtime** | zio's event loop and fiber scheduler |
| **io_uring** | Linux kernel async I/O interface |
| **IOCP** | Windows I/O Completion Ports |
| **kqueue** | BSD/macOS kernel event notification |
| **Pending Map** | Map of msgid → completion for matching requests to responses |
| **Structured Concurrency** | Pattern where child task lifetimes are bound to parent scope |

---

*Document End*
