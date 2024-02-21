const msgpack = @import("msgpack");

/// Error types for neovim result
pub const error_types = struct {
    enum {
        Exception,
        Validation,
    },
    msgpack.Str,
};

/// this type indicates that call cannot be used
pub const NoAutoCall = struct {};
