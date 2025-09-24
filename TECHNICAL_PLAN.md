# znvim - Zig Neovim 通信库技术规划方案

## 1. 项目概述

znvim 是一个用 Zig 编写的库，旨在实现与 Neovim 的完整通信能力，支持 Neovim 的所有通信方式，使用 MessagePack-RPC 协议。

### 项目目标
- 提供完整的 Neovim RPC 客户端实现
- 支持所有 Neovim 连接方式（Unix Socket、TCP、命名管道、标准输入输出、子进程）
- 自动生成类型安全的 API 绑定
- 提供事件订阅和处理机制
- 保证高性能和低内存占用

## 2. 核心架构设计

```
┌─────────────────────────────────────────────┐
│                 znvim Library                │
├─────────────────────────────────────────────┤
│            High-Level API Layer              │
│  ┌─────────────┬──────────────┬──────────┐ │
│  │   Client    │   Request    │ Response  │ │
│  │  Interface  │   Manager    │  Handler  │ │
│  └─────────────┴──────────────┴──────────┘ │
├─────────────────────────────────────────────┤
│            Protocol Layer                    │
│  ┌─────────────┬──────────────┬──────────┐ │
│  │  MsgPack    │     RPC      │   Event   │ │
│  │  Encoder/   │   Protocol   │  Dispatch │ │
│  │  Decoder    │   Handler    │           │ │
│  └─────────────┴──────────────┴──────────┘ │
├─────────────────────────────────────────────┤
│            Transport Layer                   │
│  ┌──────┬──────┬──────┬──────┬──────────┐ │
│  │ Unix │ TCP  │Named │Stdio │  Child   │ │
│  │Socket│Socket│ Pipe │      │ Process  │ │
│  └──────┴──────┴──────┴──────┴──────────┘ │
└─────────────────────────────────────────────┘
```

## 3. 模块划分

### 3.1 传输层模块 (Transport)

**文件结构：**
```
src/
├── transport/
│   ├── transport.zig       # 传输层抽象接口
│   ├── unix_socket.zig     # Unix域套接字实现
│   ├── tcp_socket.zig      # TCP/IP套接字实现
│   ├── named_pipe.zig      # 命名管道实现(Windows)
│   ├── stdio.zig           # 标准输入输出实现
│   └── child_process.zig   # 子进程通信实现
```

**核心接口定义：**
```zig
// transport.zig
pub const Transport = struct {
    pub const ReadError = error{
        ConnectionClosed,
        Timeout,
        Interrupted,
        UnexpectedError,
    };
    
    pub const WriteError = error{
        ConnectionClosed,
        BrokenPipe,
        UnexpectedError,
    };
    
    // 虚函数表模式
    const VTable = struct {
        connect: *const fn(*Transport, address: []const u8) anyerror!void,
        disconnect: *const fn(*Transport) void,
        read: *const fn(*Transport, buffer: []u8) ReadError!usize,
        write: *const fn(*Transport, data: []const u8) WriteError!void,
        is_connected: *const fn(*Transport) bool,
    };
    
    vtable: *const VTable,
    impl: *anyopaque,
};
```

### 3.2 协议层模块 (Protocol)

**文件结构：**
```
src/
├── protocol/
│   ├── msgpack_rpc.zig     # MessagePack-RPC协议实现
│   ├── message.zig         # 消息类型定义
│   ├── encoder.zig         # 消息编码
│   └── decoder.zig         # 消息解码
```

**消息类型：**
```zig
// message.zig
pub const MessageType = enum(u8) {
    Request = 0,
    Response = 1,
    Notification = 2,
};

pub const Request = struct {
    type: MessageType = .Request,
    msgid: u32,
    method: []const u8,
    params: msgpack.Payload,
};

pub const Response = struct {
    type: MessageType = .Response,
    msgid: u32,
    error: ?msgpack.Payload,
    result: ?msgpack.Payload,
};

pub const Notification = struct {
    type: MessageType = .Notification,
    method: []const u8,
    params: msgpack.Payload,
};
```

### 3.3 API 客户端层 (Client)

**文件结构：**
```
src/
├── client.zig              # 主客户端实现
├── api/
│   ├── generated.zig       # 从metadata.json生成的API
│   ├── buffer.zig          # Buffer相关API
│   ├── window.zig          # Window相关API
│   ├── command.zig         # Command相关API
│   └── events.zig          # 事件处理
```

**客户端核心结构：**
```zig
// client.zig
pub const Client = struct {
    allocator: std.mem.Allocator,
    transport: *Transport,
    next_msgid: std.atomic.Value(u32),
    pending_requests: std.AutoHashMap(u32, PendingRequest),
    event_handlers: std.StringHashMap(EventHandler),
    
    pub fn init(allocator: std.mem.Allocator, options: ConnectionOptions) !Client {
        // 初始化逻辑
    }
    
    pub fn connect(self: *Client) !void {
        // 连接逻辑
    }
    
    pub fn request(self: *Client, method: []const u8, params: anytype) !msgpack.Payload {
        // 发送请求并等待响应
    }
    
    pub fn notify(self: *Client, method: []const u8, params: anytype) !void {
        // 发送通知(无需等待响应)
    }
    
    pub fn subscribe(self: *Client, event: []const u8, handler: EventHandler) !void {
        // 订阅事件
    }
};
```

## 4. API 代码生成

### 4.1 元数据解析器

创建一个构建时工具，解析 `metadata.json` 并生成 Zig 代码：

```zig
// build_tools/api_generator.zig
pub fn generateAPI(metadata_path: []const u8, output_path: []const u8) !void {
    // 1. 解析 metadata.json
    // 2. 生成类型定义
    // 3. 生成函数包装器
    // 4. 生成文档注释
}
```

### 4.2 生成的 API 示例

```zig
// api/generated.zig (自动生成)
pub const Buffer = struct {
    client: *Client,
    handle: i64,
    
    /// Gets a line-range from the buffer.
    /// Indexing is zero-based, end-exclusive.
    pub fn getLines(self: Buffer, start: i64, end: i64, strict_indexing: bool) ![][]const u8 {
        const result = try self.client.request("nvim_buf_get_lines", .{
            self.handle, start, end, strict_indexing
        });
        // 转换结果
    }
    
    // ... 其他方法
};
```

## 5. 事件处理机制

```zig
// events.zig
pub const EventType = enum {
    BufLinesEvent,
    BufChangedTickEvent,
    BufDetachEvent,
    // ... 其他事件
};

pub const EventHandler = *const fn(event: Event) void;

pub const Event = union(EventType) {
    BufLinesEvent: struct {
        buf: i64,
        changedtick: i64,
        firstline: i64,
        lastline: i64,
        linedata: [][]const u8,
        more: bool,
    },
    // ... 其他事件结构
};
```

## 6. 连接选项和配置

```zig
// connection.zig
pub const ConnectionOptions = struct {
    /// Unix域套接字路径
    socket_path: ?[]const u8 = null,
    /// TCP连接地址
    tcp_address: ?[]const u8 = null,
    /// TCP端口
    tcp_port: ?u16 = null,
    /// 使用标准输入输出
    use_stdio: bool = false,
    /// 作为子进程启动Neovim
    spawn_process: bool = false,
    /// Neovim可执行文件路径
    nvim_path: []const u8 = "nvim",
    /// 超时设置(毫秒)
    timeout_ms: u32 = 5000,
};
```

## 7. 实现阶段

### 第一阶段：基础框架
- [x] 项目结构搭建
- [ ] Transport 抽象层定义
- [ ] Unix Socket 传输实现
- [ ] MessagePack-RPC 协议基础实现

### 第二阶段：核心功能
- [ ] TCP Socket 传输实现
- [ ] Stdio 传输实现
- [ ] 请求/响应机制
- [ ] 基础错误处理

### 第三阶段：API生成
- [ ] Metadata 解析器
- [ ] API 代码生成器
- [ ] 类型映射系统
- [ ] 生成的 API 测试

### 第四阶段：高级功能
- [ ] 事件订阅和处理
- [ ] 异步操作支持
- [ ] 连接池管理
- [ ] 批量操作优化

### 第五阶段：平台支持
- [ ] Windows 命名管道支持
- [ ] 子进程通信实现
- [ ] 平台特定优化
- [ ] 跨平台测试

### 第六阶段：完善和优化
- [ ] 性能优化
- [ ] 内存管理优化
- [ ] 文档编写
- [ ] 示例程序

## 8. 测试策略

### 8.1 测试结构
```
tests/
├── unit/
│   ├── transport_test.zig
│   ├── protocol_test.zig
│   └── api_test.zig
├── integration/
│   ├── connection_test.zig
│   ├── api_integration_test.zig
│   └── event_test.zig
└── fixtures/
    └── test_data.json
```

### 8.2 测试覆盖范围
- 单元测试：每个模块的独立功能
- 集成测试：模块间交互和完整流程
- 端到端测试：与真实 Neovim 实例的通信
- 压力测试：高并发和大数据量场景
- 兼容性测试：不同 Neovim 版本

## 9. 使用示例

### 9.1 基础连接示例
```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // 创建客户端
    var client = try znvim.Client.init(allocator, .{
        .socket_path = "/tmp/nvim.socket",
    });
    defer client.deinit();
    
    // 连接到 Neovim
    try client.connect();
    
    // 获取当前缓冲区
    const buf = try client.getCurrentBuf();
    
    // 获取缓冲区内容
    const lines = try buf.getLines(0, -1, false);
    defer allocator.free(lines);
    
    // 设置缓冲区内容
    try buf.setLines(0, -1, false, &.{"Hello", "from", "Zig!"});
}
```

### 9.2 事件订阅示例
```zig
// 订阅缓冲区变更事件
try client.subscribe("nvim_buf_lines_event", struct {
    fn handler(event: znvim.Event) void {
        switch (event) {
            .BufLinesEvent => |e| {
                std.debug.print("Buffer {} changed at line {}\n", .{e.buf, e.firstline});
            },
            else => {},
        }
    }
}.handler);
```

## 10. 依赖管理

### 当前依赖
- `zig-msgpack` (v0.0.12): MessagePack 序列化/反序列化
  
### 潜在依赖
- 网络库（如需要更高级的网络功能）
- 异步运行时（如需要更复杂的异步支持）

## 11. 性能考虑

### 11.1 优化策略
- 使用对象池减少内存分配
- 批量请求优化
- 连接复用
- 缓存常用 API 调用结果
- 零拷贝设计（尽可能）
- 预分配缓冲区

### 11.2 性能目标
- 单次 RPC 调用延迟 < 1ms（本地连接）
- 支持每秒 > 10000 次请求
- 内存使用增长可控

## 12. 错误处理

### 12.1 错误类型定义
```zig
pub const ZnvimError = error{
    // 连接相关
    ConnectionFailed,
    ConnectionLost,
    ConnectionTimeout,
    
    // 协议相关
    InvalidResponse,
    MessagePackError,
    ProtocolError,
    
    // API相关
    UnknownMethod,
    InvalidArgument,
    
    // Neovim相关
    NvimError,
    NvimInternalError,
};
```

### 12.2 错误处理策略
- 提供详细的错误信息
- 支持错误恢复机制
- 自动重连选项
- 错误日志记录

## 13. 文档计划

### 13.1 文档类型
- API 参考文档（自动生成）
- 使用指南
- 示例代码集
- 贡献指南
- 架构设计文档

### 13.2 文档工具
- 使用 Zig 的内置文档生成
- Markdown 格式的手册
- 在线文档网站

## 14. 版本策略

### 14.1 版本兼容性
- 支持 Neovim 0.8.0+
- 遵循语义化版本规范
- 保持向后兼容性

### 14.2 发布计划
- v0.1.0: 基础功能（Unix Socket + 核心 API）
- v0.2.0: 完整传输层支持
- v0.3.0: 自动生成 API
- v0.4.0: 事件系统
- v1.0.0: 稳定版本

## 15. 质量保证

### 15.1 代码质量
- 代码覆盖率 > 80%
- 静态分析检查
- 代码审查流程
- CI/CD 集成

### 15.2 性能基准
- 建立性能基准测试套件
- 定期性能回归测试
- 性能报告生成

## 16. 社区和贡献

### 16.1 开源协议
- MIT License

### 16.2 贡献流程
- GitHub Issues 跟踪
- Pull Request 流程
- 代码贡献指南
- 社区行为准则

## 17. 风险和挑战

### 17.1 技术风险
- Neovim API 变更
- Zig 语言不稳定性（仍在发展中）
- 跨平台兼容性问题

### 17.2 缓解措施
- 版本锁定机制
- 充分的测试覆盖
- 渐进式开发策略
- 社区反馈机制

## 18. 未来扩展

### 18.1 潜在功能
- Lua 插件桥接
- GUI 框架集成
- 插件开发框架
- 性能分析工具

### 18.2 生态系统
- VSCode 扩展集成
- LSP 客户端示例
- 插件市场支持

---

## 附录

### A. 参考资料
- [Neovim API Documentation](https://neovim.io/doc/user/api.html)
- [MessagePack Specification](https://msgpack.org/index.html)
- [MessagePack-RPC Specification](https://github.com/msgpack-rpc/msgpack-rpc/blob/master/spec.md)
- [Zig Language Reference](https://ziglang.org/documentation/)

### B. 相关项目
- [neovim-client (Rust)](https://github.com/neovim/nvim-rs)
- [node-client](https://github.com/neovim/node-client)
- [python-client](https://github.com/neovim/pynvim)

### C. 术语表
- **RPC**: Remote Procedure Call，远程过程调用
- **MessagePack**: 高效的二进制序列化格式
- **Transport**: 传输层，负责数据传输
- **Protocol**: 协议层，负责消息编解码
- **Client**: 客户端，提供高级 API

---

*本文档版本: 1.0.0*
*最后更新: 2024*
