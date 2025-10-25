# znvim

轻量级的 Neovim RPC 客户端，使用 Zig 编写。znvim 通过 `nvim_get_api_info` 动态获取运行时 API，提供多种传输方式，并自带易用的 MessagePack 封装，使用者无需直接对接 `zig-msgpack`。

## 特性

- **运行时 API 发现**：通过 `ApiInfo`、`ApiFunction`、`ApiParameter` 等结构返回完整的 Neovim API 元数据。
- **多种传输方式**：支持 Unix 套接字、TCP、stdio、Windows 管道以及自动拉起的 `nvim --embed` 进程。
- **内存友好设计**：调用者掌控分配与释放时机，适合在严格内存策略下运行。
- **MessagePack 外观层**：`znvim.msgpack` 提供 `array`、`object`、`encode` 等构造函数以及 `expect*`/`as*` 读取助手，屏蔽底层 `zig-msgpack` 细节。
- **示例开箱即用**：`zig build examples` 一键构建所有示例程序。

## 环境要求

- Zig 0.15.x
- 已启用 `--embed` 支持的 Neovim（官方构建默认包含）

## 安装

使用 `zig fetch` 将依赖加入项目：

```sh
zig fetch --save https://github.com/jinzhongjia/znvim/archive/main.tar.gz
```

在 `build.zig` 中引入模块：

```zig
const znvim_dep = b.dependency("znvim", .{
    .target = target,
    .optimize = optimize,
});
const znvim = znvim_dep.module("znvim");

exe.root_module.addImport("znvim", znvim);
```

## 快速上手

```zig
const std = @import("std");
const znvim = @import("znvim");
const msgpack = znvim.msgpack;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.debug.print("warning: leaked allocations\n", .{}),
    };
    const allocator = gpa.allocator();

    const address = std.process.getEnvVarOwned(allocator, "NVIM_LISTEN_ADDRESS") catch {
        std.debug.print("请先设置 NVIM_LISTEN_ADDRESS 环境变量。\n", .{});
        return error.MissingAddress;
    };
    defer allocator.free(address);

    var client = try znvim.Client.init(allocator, .{ .socket_path = address });
    defer client.deinit();
    try client.connect();

    const expr = try msgpack.string(allocator, "join(['zig', 'nvim'], '-')");
    defer msgpack.free(expr, allocator);

    const params = [_]msgpack.Value{expr};
    const response = try client.request("vim_eval", &params);
    defer msgpack.free(response, allocator);

    if (msgpack.asString(response)) |result| {
        std.debug.print("Neovim 返回: {s}\n", .{result});
    }
}
```

在终端启动 Neovim 并导出套接字地址：

```sh
nvim --headless --listen /tmp/nvim.sock &
export NVIM_LISTEN_ADDRESS=/tmp/nvim.sock
zig build examples
./zig-out/bin/print_api
```

## 示例

| 示例 | 说明 |
| --- | --- |
| `print_api.zig` | 连接后打印前几个可用的 API 函数。 |
| `run_command.zig` | 发送 `nvim_command` 通知，在 `:messages` 中查看输出。 |
| `eval_expression.zig` | 执行 Vimscript 表达式并读取返回值。 |
| `buffer_lines.zig` | 读取当前缓冲区、替换内容并再次验证。 |
| `api_lookup.zig` | 根据名称查询单个 API 函数的元数据。 |

执行 `zig build examples` 后可在 `zig-out/bin/` 目录中找到全部示例可执行文件。

## 文档

完整的英文文档位于 [`doc/`](doc/) 目录：

- **[快速开始](doc/00-quick-start.md)** - 5 分钟快速入门
- **[连接方式](doc/01-connections.md)** - 学习所有连接选项（Unix Socket、Named Pipe、TCP、ChildProcess、Stdio）
- **[API 使用](doc/02-api-usage.md)** - 完整的 Neovim API 调用指南和示例
- **[事件订阅](doc/03-events.md)** - 处理缓冲区事件、autocommand 和 UI 事件
- **[高级用法](doc/04-advanced.md)** - 线程安全、内存管理、性能优化
- **[代码示例](doc/05-examples.md)** - 真实世界的示例（文件编辑器、REPL、格式化工具等）
- **[常用模式](doc/06-patterns.md)** - 最佳实践和设计模式

👉 **从这里开始**: [doc/README.md](doc/README.md)

## MessagePack 辅助层概览

`znvim.msgpack` 是与 MessagePack 交互的统一入口：

```zig
const payload = try msgpack.object(allocator, .{
    .name = "my-command",
    .enabled = true,
    .retries = 3,
});

defer msgpack.free(payload, allocator);

const arr = try msgpack.array(allocator, &.{ payload });
const parsed = msgpack.expectArray(arr) catch return error.NotArray;
```

使用 `msgpack.encode` 可泛化编码常见 Zig 类型，`expect*` / `as*` 帮助在解码时安全地获取数据。

## 开发

运行测试：

```sh
zig build test
```

生成 API 文档：

```sh
zig build docs
```

生成的文档将位于 `zig-out/docs/` 目录，用浏览器打开 `zig-out/docs/index.html` 即可查看。

运行性能基准测试：

```sh
zig build run-benchmark
```

维护文档时请同步更新英文版 `README.md` 与中文版 `README.zh.md`。

## 许可证

MIT

---

- [English README](README.md)
