# znvim

A lightweight Neovim RPC client for Zig that discovers the runtime API via `nvim_get_api_info`, manages transports, and ships a high-level MessagePack helper so application code never needs to touch the raw `zig-msgpack` API.

## Highlights

- **Runtime API discovery** – obtain structured metadata (`ApiInfo`, `ApiFunction`, `ApiParameter`) describing exactly what the connected Neovim instance exposes.
- **Multiple transports** – talk to Neovim over Unix sockets, TCP, stdio pipes, named pipes on Windows, or auto-spawned `nvim --embed` processes.
- **Allocator-friendly client** – the caller keeps ownership of allocations and can decide how long payloads live.
- **MessagePack façade** – `znvim.msgpack` wraps `zig-msgpack` with ergonomic constructors (`msgpack.array`, `msgpack.object`, `msgpack.encode`, …) plus type-safe readers (`msgpack.expectString`, `msgpack.asArray`, …).
- **Examples ready to build** – `zig build examples` produces runnable binaries that demonstrate common workflows.

## Requirements

- Zig 0.15.x
- A running Neovim instance compiled with `--embed` support (standard builds already have it)

## Installation

Add the package to your project using `zig fetch`:

```sh
zig fetch --save https://github.com/jinzhongjia/znvim/archive/main.tar.gz
```

Wire the module in `build.zig`:

```zig
const znvim_dep = b.dependency("znvim", .{
    .target = target,
    .optimize = optimize,
});
const znvim = znvim_dep.module("znvim");

exe.root_module.addImport("znvim", znvim);
```

## Quick Start

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
        std.debug.print("Set NVIM_LISTEN_ADDRESS to your Neovim socket before running.\n", .{});
        return error.MissingAddress;
    };
    defer allocator.free(address);

    var client = try znvim.Client.init(allocator, .{ .socket_path = address });
    defer client.deinit();
    try client.connect();

    // Ask Neovim to evaluate a small expression.
    const expr = try msgpack.string(allocator, "join(['zig', 'nvim'], '-')");
    defer msgpack.free(expr, allocator);

    const params = [_]msgpack.Value{expr};
    const response = try client.request("vim_eval", &params);
    defer msgpack.free(response, allocator);

    if (msgpack.asString(response)) |result| {
        std.debug.print("Neovim answered: {s}\n", .{result});
    }
}
```

Launch Neovim and point `NVIM_LISTEN_ADDRESS` at the exposed socket:

```sh
nvim --headless --listen /tmp/nvim.sock &
export NVIM_LISTEN_ADDRESS=/tmp/nvim.sock
zig build examples
./zig-out/bin/print_api
```

## Examples

| Example | Description |
| --- | --- |
| `print_api.zig` | Connects and prints the first few discovered API functions. |
| `run_command.zig` | Issues an `nvim_command` notification that writes to `:messages`. |
| `eval_expression.zig` | Evaluates a Vimscript expression and inspects the returned payload. |
| `buffer_lines.zig` | Reads the current buffer, replaces its content, then verifies the change. |
| `api_lookup.zig` | Looks up metadata for a single API function by name. |

Build all examples in one go with `zig build examples`; binaries are placed under `zig-out/bin/`.

## Documentation

Comprehensive documentation is available in the [`doc/`](doc/) directory:

- **[Quick Start](doc/00-quick-start.md)** - Get started in 5 minutes
- **[Connection Methods](doc/01-connections.md)** - Learn all connection options (Unix Socket, Named Pipe, TCP, ChildProcess, Stdio)
- **[API Usage](doc/02-api-usage.md)** - Complete guide to calling Neovim APIs with examples
- **[Event Subscription](doc/03-events.md)** - Handle buffer events, autocommands, and UI events
- **[Advanced Usage](doc/04-advanced.md)** - Thread safety, memory management, performance optimization
- **[Code Examples](doc/05-examples.md)** - Real-world examples (file editor, REPL, formatter, etc.)
- **[Common Patterns](doc/06-patterns.md)** - Best practices and design patterns

👉 **Start here**: [doc/README.md](doc/README.md)

## MessagePack helper overview

The `znvim.msgpack` namespace aims to be the only interface most users need:

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

Use `msgpack.encode(allocator, value)` for generic encoding of common Zig types, and the `expect*` / `as*` helpers when decoding responses.

## Development

Run tests:

```sh
zig build test
```

Generate API documentation:

```sh
zig build docs
```

The generated documentation will be in the `zig-out/docs/` directory. Open `zig-out/docs/index.html` in your browser.

Run performance benchmarks:

```sh
zig build run-benchmark
```

To work on the documentation, keep the English `README.md` and the Chinese translation `README.zh.md` in sync.

## License

MIT

---

- [中文文档](README.zh.md)
