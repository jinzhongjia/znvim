const std = @import("std");
const msgpack = @import("msgpack");
const rpc = @import("rpc.zig");
const api = @import("api.zig");

const net = std.net;
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const MetaData = api.nvim_get_api_info.MetaData;

const comptimePrint = std.fmt.comptimePrint;
pub const wrapStr = msgpack.wrapStr;

const api_info = @typeInfo(api).Struct;

/// Error types for neovim result
pub const error_types = struct {
    enum {
        Exception,
        Validation,
    },
    msgpack.Str,
};

pub const api_enum = blk: {
    var fields: [api_info.decls.len]Type.EnumField = undefined;

    for (api_info.decls, 0..) |decl, i| {
        fields[i].name = decl.name;
        fields[i].value = i;
    }

    break :blk @Type(Type{
        .Enum = .{
            .is_exhaustive = false,
            .decls = &.{},
            .tag_type = u16,
            .fields = &fields,
        },
    });
};

inline fn get_api_type_def(comptime api_name: api_enum) type {
    const name = @tagName(api_name);
    for (api_info.decls) |decl| {
        if (decl.name.len == name.len and std.mem.eql(u8, decl.name, name)) {
            return @field(api, decl.name);
        }
    }
    const err_msg = comptimePrint("not found the api ({s})", .{api_name});
    @compileError(err_msg);
}

/// used to get api parameters
fn get_api_parameters(comptime api_name: api_enum) type {
    const api_def = get_api_type_def(api_name);
    if (comptime !@hasDecl(api_def, "parameters")) {
        @compileError(comptimePrint("not found {} in api ({})", .{ "parameters", api_name }));
    }
    const api_params_def = @field(api_def, "parameters");
    const api_params_def_type_info = @typeInfo(api_params_def);
    if (api_params_def_type_info == .Struct) {
        if (api_params_def_type_info.Struct.is_tuple) {
            return api_params_def;
        } else {
            return @Type(.{
                .Struct = .{
                    .layout = .Auto,
                    .fields = &.{},
                    .decls = &.{},
                    .is_tuple = true,
                },
            });
        }
    } else {
        @compileError(comptimePrint("api ({})'s parameters should be tuple", .{api_name}));
    }
}

/// used to get api return_type
fn get_api_return_type(comptime api_name: api_enum) type {
    return get_api_type_def(api_name).return_type;
}

pub fn Client(pack_type: type) type {
    const cT = rpc.TCPClient(pack_type);
    return struct {
        c: cT,
        channel_id: u16,
        metadata: MetaData,

        const Self = @This();

        pub fn init(
            stream: net.Stream,
        ) !Self {
            var self: Self = undefined;
            self.c = cT.init(stream);

            return self;
        }

        pub fn call(self: *Self, comptime method: api_enum, params: get_api_parameters(method), allocator: Allocator) !get_api_return_type(method) {
            const name = @tagName(method);
            return self.c.call(name, params, error_types, get_api_return_type(method), allocator);
        }

        // this api will call('nvim_get_api_info', [])
        pub fn get_api_info(self: *Self, allocator: Allocator) !void {
            const result = try self.call(.nvim_get_api_info, .{}, allocator);
            self.channel_id = result[0];
            self.metadata = result[1];
        }

        /// event loop
        pub fn loop(self: Self, allocator: Allocator) !void {
            return self.c.loop(allocator);
        }
    };
}
