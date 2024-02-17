const msgpack = @import("msgpack");

const Buffer = msgpack.EXT;
const Window = msgpack.EXT;
const Tabpage = msgpack.EXT;

pub const nvim_get_api_info = struct {
    /// return type
    pub const return_type = struct {
        u16,
        MetaData,
    };

    /// parameters
    pub const parameters = struct {};

    const version = struct {
        major: u8,
        minor: u8,
        patch: u8,
        build: msgpack.Str,
        prerelease: bool,
        api_level: u8,
        api_compatible: u8,
        api_prerelease: bool,
    };

    const function = struct {
        since: u8,
        return_type: msgpack.Str,
        method: bool,
        parameters: [][2]msgpack.Str,
        deprecated_since: ?u8 = null,
        name: msgpack.Str,
    };

    const uiEvent = struct {
        name: msgpack.Str,
        since: u8,
        parameters: [][2]msgpack.Str,
    };

    const errorSubType = struct { id: u8 };

    const errorType = struct {
        Exception: errorSubType,
        Validation: errorSubType,
    };

    const TypeInfo = struct {
        id: u8,
        prefix: msgpack.Str,
    };
    const Type = struct {
        Buffer: TypeInfo,
        Window: TypeInfo,
        Tabpage: TypeInfo,
    };

    pub const MetaData = struct {
        version: version,
        functions: []function,
        ui_events: []uiEvent,
        ui_options: []msgpack.Str,
        error_types: errorType,
        types: Type,
    };
};

pub const nvim_get_current_buf = struct {
    /// return type
    pub const return_type = Buffer;

    /// parameters
    pub const parameters = struct {};
};
