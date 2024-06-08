# znvim

_znvim_ is a [neovim remote rpc](https://neovim.io/doc/user/api.html#rpc-connecting) client implementation with [`zig`](https://ziglang.org/).

> This package is under developing!

## Document

[https://jinzhongjia.github.io/znvim/](https://jinzhongjia.github.io/znvim/)

## Features

- Implementation of multiple remote calling methods
- Support all neovim rpc [channels](https://neovim.io/doc/user/channel.html#channel-intro)
- Completely thread safe
- Asynchronous

## Getting Started

### `0.12.0` / `0.13.0`

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

## To use this lib

You can find example on `test` fold!

Recommend to learn about what [msgpack](https://github.com/msgpack/msgpack/blob/master/spec.md) is (this lib uses [zig-msgpack](https://github.com/zigcc/zig-msgpack)) and read neovim's API [documentation](https://neovim.io/doc/user/api.html).