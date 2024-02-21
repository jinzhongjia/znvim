const std = @import("std");
const msgpack = @import("msgpack");
const rpc = @import("rpc.zig");
const builtin = @import("builtin");
pub const api = @import("api.zig");

const net = std.net;
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const MetaData = api.nvim_get_api_info.MetaData;

const comptimePrint = std.fmt.comptimePrint;
pub const wrapStr = msgpack.wrapStr;

const api_info = @typeInfo(api).Struct;

const CallErrorSet = error{
    APIDeprecated,
    NotFindApi,
};

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
        } else if (api_params_def_type_info.Struct.fields.len == 0) {
            return @Type(.{
                .Struct = .{
                    .layout = .Auto,
                    .fields = &.{},
                    .decls = &.{},
                    .is_tuple = true,
                },
            });
        } else {
            const err_msg = comptimePrint("type ({}) is invalid, it must be tuple", .{api_params_def});
            @compileError(err_msg);
        }
    } else {
        @compileError(comptimePrint("api ({})'s parameters should be tuple", .{api_name}));
    }
}

/// used to get api return_type
fn get_api_return_type(comptime api_name: api_enum) type {
    return get_api_type_def(api_name).return_type;
}

pub fn DefaultClient(pack_type: type) type {
    return Client(pack_type, 20480);
}

pub fn Client(pack_type: type, comptime buffer_size: usize) type {
    const cT = rpc.TCPClient(pack_type, buffer_size);
    return struct {
        c: cT,
        channel_id: u16,
        metadata: MetaData,

        const Self = @This();

        pub const DynamicCall = cT.DynamicCall;

        pub fn init(stream: net.Stream, allocator: Allocator) !Self {
            var self: Self = undefined;
            self.c = try cT.init(stream, allocator);

            return self;
        }

        pub fn deinit(self: Self) void {
            self.c.deinit();
        }

        pub fn call(
            self: Self,
            comptime method: api_enum,
            params: get_api_parameters(method),
            allocator: Allocator,
        ) !get_api_return_type(method) {
            const name = @tagName(method);
            // This will verify whether the method is available in the current version in debug mode
            if (comptime (builtin.mode == .Debug and !std.mem.eql(u8, name, "nvim_get_api_info"))) {
                var if_find: bool = false;
                for (self.metadata.functions) |function| {
                    const function_name = function.name.value();
                    if (name.len == function_name.len and std.mem.eql(u8, name, function_name)) {
                        if_find = true;
                        if (function.deprecated_since) |deprecated_since| {
                            if (deprecated_since >= self.metadata.version.api_level) {
                                std.log.warn("since is {}", .{deprecated_since});
                                return CallErrorSet.APIDeprecated;
                            }
                        }
                        break;
                    }
                }

                if (!if_find) {
                    return CallErrorSet.NotFindApi;
                }
            }

            return self.c.call(
                name,
                params,
                error_types,
                get_api_return_type(method),
                allocator,
            );
        }

        /// caller not hold the mem
        /// this function will not read the value, it will just return a reader for you to read
        /// for arrary or map
        pub fn call_with_reader(
            self: Self,
            comptime method: api_enum,
            params: get_api_parameters(method),
            comptime call_type: DynamicCall,
            allocator: Allocator,
        ) !DynamicCall.get_type(call_type, true) {
            // TODO: add debug detect

            const name = @tagName(method);
            return self.c.call_with_reader(
                name,
                params,
                error_types,
                allocator,
                call_type,
            );
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
