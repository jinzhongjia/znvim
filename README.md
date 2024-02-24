# znvim

_znvim_ is a [neovim remote rpc](https://neovim.io/doc/user/api.html#rpc-connecting) client implementation with [`zig`](https://ziglang.org/).

> This package is under developing!

## Features

- Implementation of multiple remote calling methods
- Support `latest release` and `nightly`
- Strict type checking
- Support all neovim [channels](https://neovim.io/doc/user/channel.html#channel-intro)

## Getting Started

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

- More complete static api binding
