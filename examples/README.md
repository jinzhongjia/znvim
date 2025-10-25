# znvim Examples

This directory contains various examples demonstrating how to use the znvim library in real-world projects.

## 📋 Table of Contents

### 🔰 Basic Examples

These examples demonstrate the core features and basic usage of znvim:

- **`simple_spawn.zig`** - Minimal example with auto-spawning embedded Neovim
- **`api_info.zig`** - Neovim API information tool (list all functions or lookup specific one)
- **`buffer_lines.zig`** - Manipulate buffer contents (read and write)
- **`eval_expression.zig`** - Execute and evaluate Vim expressions
- **`print_api.zig`** - Print Neovim API overview
- **`run_command.zig`** - Execute Neovim commands
- **`event_handling.zig`** - Handle Neovim events and notifications
- **`batch_file_processing.zig`** - Batch process files (add license headers)
- **`live_linter.zig`** - Real-time code linter example (using virtual text)

### 🚀 Production-Ready Examples

These examples demonstrate complete tools ready for production use, **supporting all platforms and all connection methods**:

- **`code_formatter.zig`** - Code formatting tool (supports multiple languages)
- **`batch_search_replace.zig`** - Batch search and replace tool (regex support)
- **`remote_edit_session.zig`** - Remote editing session (connect to running Neovim)
- **`code_statistics.zig`** - Code statistics analysis tool (lines, comments, complexity)

### 🔧 Helper Modules

- **`connection_helper.zig`** - Universal connection helper module, handles all platform connection methods

---

## 🌐 Cross-Platform Connection Support

All **production-ready examples** use the `connection_helper.zig` module and support the following connection methods:

### Windows Platform

| Method | Description | Environment Variable Example |
|--------|-------------|------------------------------|
| **Named Pipe** | Windows-specific | `set NVIM_LISTEN_ADDRESS=\\.\pipe\nvim-pipe` |
| **TCP Socket** | Cross-platform | `set NVIM_LISTEN_ADDRESS=127.0.0.1:6666` |
| **Stdio** | Cross-platform | Handled automatically |
| **Spawn Process** | Cross-platform | Auto-spawn Neovim |

### Unix/Linux/macOS Platform

| Method | Description | Environment Variable Example |
|--------|-------------|------------------------------|
| **Unix Socket** | Unix-specific | `export NVIM_LISTEN_ADDRESS=/tmp/nvim.sock` |
| **TCP Socket** | Cross-platform | `export NVIM_LISTEN_ADDRESS=127.0.0.1:6666` |
| **Stdio** | Cross-platform | Handled automatically |
| **Spawn Process** | Cross-platform | Auto-spawn Neovim |

### Smart Connection Logic

Production examples use an intelligent connection strategy:

1. **Check environment variable** `NVIM_LISTEN_ADDRESS`
   - Contains `:` → TCP connection
   - Windows without `:` → Named Pipe
   - Unix without `:` → Unix Socket

2. **No environment variable** → Auto-spawn embedded Neovim

---

## 🚀 Quick Start

### 1. Build All Examples

```bash
zig build examples
```

Compiled executables will be in the `zig-out/bin/` directory.

### 2. Run Basic Examples

**Simplest way (auto-spawn Neovim):**

```bash
# Windows
zig-out\bin\simple_spawn.exe

# Unix/Linux/macOS
./zig-out/bin/simple_spawn
```

**Connect to running Neovim:**

```bash
# In Neovim (Unix/Linux/macOS)
:let $NVIM_LISTEN_ADDRESS = '/tmp/nvim.sock'
:call serverstart($NVIM_LISTEN_ADDRESS)

# In another terminal
export NVIM_LISTEN_ADDRESS=/tmp/nvim.sock
./zig-out/bin/buffer_lines
```

```powershell
# In Neovim (Windows)
:let $NVIM_LISTEN_ADDRESS = '\\.\pipe\nvim-pipe'
:call serverstart($NVIM_LISTEN_ADDRESS)

# In another terminal
set NVIM_LISTEN_ADDRESS=\\.\pipe\nvim-pipe
zig-out\bin\buffer_lines.exe
```

### 3. Run Production Examples

#### Code Formatter

```bash
# Demo mode
./zig-out/bin/code_formatter

# Format single file
./zig-out/bin/code_formatter main.zig

# Batch format (check only, no modification)
./zig-out/bin/code_formatter --check src/*.zig

# Format and save
./zig-out/bin/code_formatter src/*.zig
```

#### Batch Search & Replace

```bash
# Demo mode
./zig-out/bin/batch_search_replace

# Preview replace (don't modify files)
./zig-out/bin/batch_search_replace -p "oldName" -r "newName" src/*.zig

# Auto replace
./zig-out/bin/batch_search_replace -p "oldName" -r "newName" --auto src/*.zig
```

#### Remote Editing Session

```bash
# Demo mode
./zig-out/bin/remote_edit_session

# Edit file
./zig-out/bin/remote_edit_session config.json

# Enable monitor mode
./zig-out/bin/remote_edit_session --monitor main.zig
```

#### Code Statistics

```bash
# Demo mode
./zig-out/bin/code_statistics

# Analyze single file
./zig-out/bin/code_statistics main.zig

# Batch analyze
./zig-out/bin/code_statistics src/*.zig

# Detailed report
./zig-out/bin/code_statistics --detailed src/**/*.zig
```

---

## 🔌 Connection Methods

### Method 1: Auto-Spawn (Simplest)

**No environment variable needed**, programs auto-spawn embedded Neovim:

```bash
./zig-out/bin/code_formatter main.zig
```

**Pros:**
- No configuration required
- Runs independently
- Perfect for automation scripts

**Cons:**
- Spawns new instance each time
- Cannot interact with existing editor
- No shared editing state

### Method 2: Unix Socket (Unix/Linux/macOS Recommended)

**In Neovim:**

```vim
:let $NVIM_LISTEN_ADDRESS = '/tmp/nvim.sock'
:call serverstart($NVIM_LISTEN_ADDRESS)
```

**In terminal:**

```bash
export NVIM_LISTEN_ADDRESS=/tmp/nvim.sock
./zig-out/bin/code_formatter main.zig
```

**Pros:**
- Fastest for local connections
- Secure (filesystem permissions)
- Ideal for single-machine use

### Method 3: Named Pipe (Windows Recommended)

**In Neovim:**

```vim
:let $NVIM_LISTEN_ADDRESS = '\\.\pipe\nvim-pipe'
:call serverstart($NVIM_LISTEN_ADDRESS)
```

**In terminal:**

```powershell
set NVIM_LISTEN_ADDRESS=\\.\pipe\nvim-pipe
zig-out\bin\code_formatter.exe main.zig
```

### Method 4: TCP Socket (Cross-Platform/Remote)

**In Neovim (server):**

```vim
:let $NVIM_LISTEN_ADDRESS = '0.0.0.0:6666'
:call serverstart($NVIM_LISTEN_ADDRESS)
```

**In terminal (client):**

```bash
# Local connection
export NVIM_LISTEN_ADDRESS=127.0.0.1:6666

# Remote connection
export NVIM_LISTEN_ADDRESS=192.168.1.100:6666

./zig-out/bin/remote_edit_session
```

**Pros:**
- Supports remote connections
- Cross-platform universal
- Ideal for team collaboration

**Cons:**
- Requires network configuration
- Security needs extra handling

### Method 5: Stdio (Inter-Process Communication)

**Use cases:**
- Editor plugins
- Subprocess invocation
- Containerized environments

---

## 📚 Learning Path

### Beginner

1. `simple_spawn.zig` - Understand basic connection
2. `buffer_lines.zig` - Learn buffer operations
3. `eval_expression.zig` - Understand expression evaluation
4. `run_command.zig` - Execute Neovim commands

### Intermediate

1. `api_info.zig` - Explore API metadata and function details
2. `event_handling.zig` - Handle event notifications
3. `batch_file_processing.zig` - Batch operation techniques
4. `live_linter.zig` - Virtual text and extmarks

### Production Use

1. `code_formatter.zig` - Complete tool architecture
2. `batch_search_replace.zig` - Batch processing patterns
3. `remote_edit_session.zig` - Session management
4. `code_statistics.zig` - Data analysis and reporting

---

## 🛠️ Example Template

### Create New Cross-Platform Tool

```zig
const std = @import("std");
const znvim = @import("znvim");
const msgpack = znvim.msgpack;
const helper = @import("connection_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Smart connect (automatically supports all platforms and methods)
    var client = try helper.smartConnect(allocator);
    defer client.deinit();

    // Your business logic
    const api_info = client.getApiInfo() orelse return error.ApiInfoUnavailable;
    std.debug.print("Neovim {d}.{d}.{d}\n", .{
        api_info.version.major,
        api_info.version.minor,
        api_info.version.patch,
    });

    // ... more operations ...
}
```

---

## ❓ Common Questions

### Q: How to choose connection method?

**A:** Recommended order:
1. **Development/Testing** → Auto-spawn (no configuration)
2. **Local Use** → Unix Socket (Unix) or Named Pipe (Windows)
3. **Remote/Collaboration** → TCP Socket
4. **Plugin Development** → Stdio

### Q: Will examples work on my platform?

**A:**
- **Basic examples**: Most require setting `NVIM_LISTEN_ADDRESS`
- **Production examples**: Support all platforms, run without configuration

### Q: How to debug connection issues?

**A:**
1. Check environment variable: `echo $NVIM_LISTEN_ADDRESS`
2. Verify in Neovim: `:echo v:servername`
3. Use `--verbose` option with examples
4. Check logs from `connection_helper.zig`

### Q: Can I connect to multiple Neovim instances?

**A:** Yes! Each `Client` instance corresponds to one connection. Create multiple `Client` objects to connect to multiple Neovim instances.

---

## 📖 Related Documentation

- [Main README](../README.md) - Project overview
- [Technical Documentation](../doc/README.md) - Detailed API documentation
- [AGENTS.md](../AGENTS.md) - Architecture and design guide

---

## 🤝 Contributing

New examples are welcome! Please ensure:

1. **Cross-platform support** - Use `connection_helper.zig`
2. **Clear comments** - Explain each step
3. **Error handling** - Handle all errors properly
4. **Memory safety** - Proper use of `defer` and `errdefer`
5. **Practical value** - Solve real-world problems

---

**Last Updated**: 2025-10-25  
**znvim Version**: 0.1.0
