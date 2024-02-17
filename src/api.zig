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
        major: u16,
        minor: u16,
        patch: u16,
        build: msgpack.Str,
        prerelease: bool,
        api_level: u16,
        api_compatible: u16,
        api_prerelease: bool,
    };

    const function = struct {
        since: u16,
        return_type: msgpack.Str,
        method: bool,
        parameters: [][2]msgpack.Str,
        deprecated_since: ?u16 = null,
        name: msgpack.Str,
    };

    const uiEvent = struct {
        name: msgpack.Str,
        since: u16,
        parameters: [][2]msgpack.Str,
    };

    const errorSubType = struct { id: u16 };

    const errorType = struct {
        Exception: errorSubType,
        Validation: errorSubType,
    };

    const TypeInfo = struct {
        id: u16,
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
