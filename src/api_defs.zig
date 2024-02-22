//! this package defines apis
//! every pub decl is a api
//! every api has decls called return_type and parameters
//! return type is the return type
//! parameters is the tuple of params
//! more info: https://neovim.io/doc/user/api.html

const msgpack = @import("msgpack");
const config = @import("config.zig");
const EXT = msgpack.EXT;
const Str = msgpack.Str;
const Bin = msgpack.Bin;

const Buffer = EXT;
const Window = EXT;
const Tabpage = EXT;

// and exactly, we just need to implementate str and ext ?
// need a cuntion to convert parameter to a new type and a extra function to convert the  new type value to parameter
// a function to convert return type to a new type

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
        /// listed
        bool,
        /// scratch
        bool,
    };
};

pub const nvim_del_current_line = struct {
    /// return type
    pub const return_type = void;

    /// parameters
    pub const parameters = struct {};
};

pub const nvim_del_keymap = struct {
    /// return type
    pub const return_type = void;

    /// parameters
    pub const parameters = struct {
        /// mode
        Str,
        /// lhs
        Str,
    };
};

pub const nvim_del_mark = struct {
    /// return type
    pub const return_type = bool;

    /// parameters
    pub const parameters = struct {
        /// name
        Str,
    };
};

pub const nvim_del_var = struct {
    /// return type
    pub const return_type = bool;

    /// parameters
    pub const parameters = struct {
        /// name
        Str,
    };
};

pub const nvim_echo = struct {
    /// return type
    pub const return_type = void;

    /// parameters
    pub const parameters = struct {
        /// chunks
        []chunk,
        /// history
        bool,
        /// opt
        option,
    };

    pub const chunk = struct {
        /// text
        Str,
        /// hl_group, this can be null
        Str,
    };

    pub const option = struct {
        verbose: bool,
    };
};

pub const nvim_err_write = struct {
    /// return type
    pub const return_type = void;

    /// parameters
    pub const parameters = struct {
        /// str
        Str,
    };
};

pub const nvim_err_writeln = struct {
    /// return type
    pub const return_type = void;

    /// parameters
    pub const parameters = struct {
        /// str
        Str,
    };
};

pub const nvim_eval_statusline = struct {
    /// return type
    pub const return_type = dictionary;

    /// parameters
    pub const parameters = struct {
        /// str
        Str,
        /// opts
        option,
    };

    const option = struct {
        winid: u16,
        maxwidth: u16,
        fillchar: Str,
        highlight: bool,
        use_winbar: bool,
        use_tabline: bool,
        use_statuscol_lnum: bool,
    };

    const hightlight = struct {
        start: u16,
        group: Str,
    };

    const dictionary = struct {
        str: Str,
        width: u16,
        hightlights: []hightlight,
    };
};

pub const nvim_exec_lua = struct {
    /// return type
    pub const return_type = config.NoAutoCall;

    /// parameters
    pub const parameters = struct {
        Str,
    };
};

pub const nvim_feedkeys = struct {
    /// return type
    pub const return_type = void;

    pub const parameters = struct {
        /// keys
        Str,
        /// mode
        Str,
        /// escape_ks
        bool,
    };
};

pub const nvim_get_chan_info = struct {
    /// return type
    pub const return_type = config.NoAutoCall;

    pub const parameters = struct {
        // chan id
        u16,
    };

    const client = struct {
        name: Str,
    };
};

pub const nvim_get_color_map = struct {
    /// return type
    pub const return_type = config.NoAutoCall;

    pub const parameters = struct {};
};
