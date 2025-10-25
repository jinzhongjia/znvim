# znvim Documentation

Complete documentation for the znvim Neovim RPC client library.

## 📚 Table of Contents

### Getting Started
- [Quick Start](00-quick-start.md) - Get up and running in 5 minutes
- [Connection Methods](01-connections.md) - Learn different ways to connect to Neovim

### Core Concepts
- [API Usage](02-api-usage.md) - Comprehensive guide to calling Neovim APIs
- [Event Subscription](03-events.md) - Handle Neovim events
- [Advanced Usage](04-advanced.md) - Advanced features and optimization

### Examples & Patterns
- [Code Examples](05-examples.md) - Real-world code examples
- [Common Patterns](06-patterns.md) - Best practices and design patterns

## 🚀 Quick Navigation

### By Use Case

**I want to...**

- **Build an editor plugin** → [Connection Methods](01-connections.md) → [API Usage](02-api-usage.md)
- **Automate Neovim** → [Quick Start](00-quick-start.md) → [Code Examples](05-examples.md)
- **Handle buffer changes** → [Event Subscription](03-events.md)
- **Optimize performance** → [Advanced Usage](04-advanced.md)
- **Use in multi-threaded app** → [Advanced Usage](04-advanced.md#thread-safety)

### By Platform

- **Windows Users** → Focus on Named Pipe and ChildProcess connections
- **Linux/macOS Users** → Focus on Unix Socket and ChildProcess connections
- **Cross-platform Apps** → Use TCP Socket or ChildProcess

## 📖 Learning Path

### Beginner
1. [Quick Start](00-quick-start.md) - Run your first program
2. [Connection Methods](01-connections.md) - Understand connection options
3. [API Usage](02-api-usage.md) - Learn basic API calls

### Intermediate
4. [Code Examples](05-examples.md) - Study real-world examples
5. [Event Subscription](03-events.md) - Handle Neovim events
6. [Common Patterns](06-patterns.md) - Learn best practices

### Advanced
7. [Advanced Usage](04-advanced.md) - Performance optimization
8. Thread safety and concurrency
9. Memory management techniques

## 🔗 External Resources

- [Neovim API Documentation](https://neovim.io/doc/user/api.html)
- [MessagePack Specification](https://msgpack.org/)
- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [GitHub Repository](https://github.com/jinzhongjia/znvim)

## 💡 Tips

- All code examples are tested and working
- Copy-paste examples into your projects
- Check `examples/` directory for complete programs
- Join discussions on GitHub Issues

---

**Version**: 1.0.0  
**Last Updated**: 2025-10-24  
**License**: MIT

