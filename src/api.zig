const msgpack = @import("msgpack");
const EXT = msgpack.EXT;
const Str = msgpack.Str;
const Bin = msgpack.Bin;

const Buffer = EXT;
const Window = EXT;
const Tabpage = EXT;

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
        build: Str,
        prerelease: bool,
        api_level: u16,
        api_compatible: u16,
        api_prerelease: bool,
    };

    const function = struct {
        since: u16,
        return_type: Str,
        method: bool,
        parameters: [][2]Str,
        deprecated_since: ?u16 = null,
        name: Str,
    };

    const uiEvent = struct {
        name: Str,
        since: u16,
        parameters: [][2]Str,
    };

    const errorSubType = struct { id: u16 };

    const errorType = struct {
        Exception: errorSubType,
        Validation: errorSubType,
    };

    const TypeInfo = struct {
        id: u16,
        prefix: Str,
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
        ui_options: []Str,
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

pub const nvim_create_buf = struct {
    /// return type
    pub const return_type = Buffer;

    /// parameters
    pub const parameters = struct {
        listed: bool,
        scratch: bool,
    };
};

pub const nvim_del_current_line = struct {
    /// return type
    pub const return_type = void;

    /// parameters
    pub const parameters = struct {};
};

pub const nvim_del_keymap = struct {
    pub const return_type = void;

    pub const parameters = struct {
        mode: Str,
        lhs: Str,
    };
};
