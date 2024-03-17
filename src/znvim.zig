const std = @import("std");
const builtin = @import("builtin");
const rpc = @import("rpc.zig");

const Allocator = std.mem.Allocator;

pub const ClientType = rpc.ClientType;
pub const Payload = rpc.Payload;
pub const ResultType = rpc.ResultType;
pub const ReqMethodType = rpc.ReqMethodType;
pub const NotifyMethodType = rpc.NotifyMethodType;

const ErrorSet = error{
    ApiNotFound,
    ApiDeprecated,
    NotGetVersion,
    NotGetApiLevel,
    NotGetFunctions,
    NotGetFuncName,
};

// current build mode
const build_mode = builtin.mode;

pub fn Client(comptime buffer_size: usize, comptime client_tag: ClientType) type {
    const RpcClientType = rpc.rpcClientType(buffer_size, client_tag);

    return struct {
        rpc_client: RpcClientType,
        nvim_info: rpc.Payload,

        const Self = @This();

        /// Transport type used
        /// only can be `std.net.Stream` or std.fs.File
        pub const TransType = RpcClientType.TransType;

        /// init
        pub fn init(trans_writer: TransType, trans_reader: TransType, allocator: Allocator) !Self {
            var rpc_client = try RpcClientType.init(
                trans_writer,
                trans_reader,
                allocator,
            );
            errdefer rpc_client.deinit();

            const arr = try Payload.arrPayload(0, allocator);
            defer arr.free(allocator);

            const result = try rpc_client.call("nvim_get_api_info", arr);

            return Self{
                .rpc_client = rpc_client,
                .nvim_info = result.result,
            };
        }

        /// deinit
        pub fn deinit(self: *Self) void {
            self.rpc_client.freePayload(self.nvim_info);
            self.rpc_client.deinit();
        }

        fn getApiInfos(self: Self) Payload {
            return self.nvim_info.arr[1];
        }

        fn getApiLevel(self: Self) !u32 {
            const api_infos = self.getApiInfos().map;
            const version = (api_infos.get("version") orelse return ErrorSet.NotGetVersion).map;
            const api_level = (version.get("api_level") orelse return ErrorSet.NotGetApiLevel).uint;
            return @intCast(api_level);
        }

        fn getFunc(self: Self, api_name: []const u8) !?Payload {
            const api_infos = self.getApiInfos().map;
            const funcs = (api_infos.get("functions") orelse return ErrorSet.NotGetFunctions).arr;
            for (funcs) |val| {
                const func = val.map;
                const func_name = (func.get("name") orelse return ErrorSet.NotGetFuncName).str.value();
                if (u8Eql(func_name, api_name)) {
                    return val;
                }
            }
            return null;
        }

        fn checkApiAvailable(self: Self, api_name: []const u8) !bool {
            const api_infos = self.getApiInfos().map;
            const funcs = (api_infos.get("functions") orelse return false).arr;
            for (funcs) |func| {
                const func_name = (func.map.get("name") orelse return ErrorSet.NotGetFuncName).str.value();
                if (api_name.len == func_name.len and u8Eql(func_name, api_name)) {
                    if (func.map.get("deprecated_since")) |deprecated_since| {
                        if (deprecated_since.uint <= try self.getApiLevel())
                            return ErrorSet.ApiDeprecated;
                    }
                    return true;
                }
            }
            return false;
        }

        /// register method
        pub fn registerMethod(self: *Self, method_name: []const u8, func: ReqMethodType) !void {
            try self.rpc_client.registerMethod(method_name, func);
        }

        /// register notify method
        pub fn registerNotifyMethod(self: *Self, method_name: []const u8, func: NotifyMethodType) !void {
            try self.rpc_client.registerNotifyMethod(method_name, func);
        }

        pub fn call(self: *Self, api_name: []const u8, params: rpc.Payload) !rpc.ResultType {
            if ((comptime build_mode == .Debug) and
                !try self.checkApiAvailable(api_name))
                return ErrorSet.ApiNotFound;

            return self.rpc_client.call(api_name, params);
        }

        pub fn notify(self: *Self, api_name: []const u8, params: rpc.Payload) !void {
            if ((comptime build_mode == .Debug) and
                !try self.checkApiAvailable(api_name))
                return ErrorSet.ApiNotFound;
            try self.rpc_client.notify(api_name, params);
        }

        pub fn createParams(nums: usize, allocator: Allocator) !Payload {
            return Payload.arrPayload(nums, allocator);
        }

        pub fn freeParams(payload: Payload, allocator: Allocator) void {
            payload.free(allocator);
        }

        pub fn freeResultType(self: Self, result_type: ResultType) void {
            self.rpc_client.freeResultType(result_type);
        }

        pub fn getChannelID(self: Self) u32 {
            return @intCast(self.nvim_info.arr[0].uint);
        }

        pub fn loop(self: *Self) !void {
            try self.rpc_client.loop();
        }
    };
}

fn u8Eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }
    return std.mem.eql(u8, a, b);
}
