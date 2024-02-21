# znvim

_znvim_ is a neovim remote rpc client implementation with [`zig`](https://ziglang.org/).

> This package is under developing!

## Features

- Implementation of multiple remote calling methods(now only support tcp connect)
- Clean API
- Strict type checking

## Getting Started

**NOTE**: znvim now only supports zig `nightly`!

1. Add to `build.zig.zon`

```sh
zig fetch --save https://github.com/jinzhongjia/znvim/archive/{commit or branch}.tar.gz
```

2. Config `build.zig`

```zig
const znvim = b.dependency("znvim", .{
    .target = target,
    .optimize = optimize,
});

// add module
exe.root_module.addImport("znvim", znvim.module("znvim"));
```

## TODO

- More api
- More channels implementation, now only support tcp and unixsocket!
