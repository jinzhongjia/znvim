# znvim

A lightweight Neovim RPC client written in Zig. znvim connects to a running Neovim instance, negotiates its API surface at runtime via `nvim_get_api_info`, and exposes a thin MessagePack-RPC interface for synchronous requests and notifications.

> **Status:** experimental / work-in-progress. Only Unix socket transports are implemented today.

## Features

- Runtime API discovery driven by `nvim_get_api_info`, exposed through typed `ApiInfo` / `ApiFunction` metadata.
- Multiple transport backends: Unix sockets (macOS/Linux), Windows named pipes, TCP sockets, stdio pipes, and auto-spawned `nvim --embed` child processes.
- Synchronous `Client.request` / `Client.notify` helpers over MessagePack-RPC.
- Built on top of [`zig-msgpack`](https://github.com/zigcc/zig-msgpack) for encoding/decoding MessagePack payloads.
- Simple allocator-aware design; callers control lifetimes of all payload allocations.

## Installation

The package targets Zig `0.15.x`.

```sh
zig fetch --save https://github.com/jinzhongjia/znvim/archive/main.tar.gz
```

Then wire the dependency in your `build.zig`:

```zig
const znvim_dep = b.dependency("znvim", .{
    .target = target,
    .optimize = optimize,
});
const znvim = znvim_dep.module("znvim");

// Usage example
exe.root_module.addImport("znvim", znvim);
```

## Quick Start

```zig
const std = @import("std");
const znvim = @import("znvim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const address = std.os.getenv("NVIM_LISTEN_ADDRESS") orelse
        return error.MissingAddress;

    var client = try znvim.Client.init(allocator, .{ .socket_path = address });
    defer client.deinit();
    try client.connect();

    const info = client.getApiInfo() orelse return error.ApiInfoUnavailable;
    std.debug.print("Neovim API {d}.{d}.{d} exposes {d} functions\n",
        .{ info.version.major, info.version.minor, info.version.patch, info.functions.len });
}
```

To connect from a shell, start Neovim in headless mode and point `NVIM_LISTEN_ADDRESS` at the socket:

```sh
nvim --headless --listen /tmp/nvim.sock &
export NVIM_LISTEN_ADDRESS=/tmp/nvim.sock
zig build-exe examples/print_api.zig
./print_api
```

## Examples

The `examples/` directory contains self-contained programs that demonstrate common interactions:

- `examples/print_api.zig` – connect and print the discovered API metadata (first 10 functions).
- `examples/run_command.zig` – send an `nvim_command` notification.
- `examples/eval_expression.zig` – evaluate a Vimscript expression and inspect the returned payload.
- `examples/buffer_lines.zig` – fetch the current buffer, overwrite its contents, and read lines back.
- `examples/api_lookup.zig` – query runtime metadata for a specific API function (pass the name as argv).

Each example imports `../src/root.zig` directly to work inside this repository. When you depend on znvim from another project, replace that import with `@import("znvim")` and build via your own `build.zig`.

## Development & Testing

Run the full test suite (including the new parser and API refresh tests) with:

```sh
zig build test
```

The tests leverage a fake transport and synthetic `nvim_get_api_info` responses to exercise the runtime parser without requiring a live Neovim instance.

## License

MIT
