const std = @import("std");
const rpc = @import("rpc.zig");

const Allocator = std.mem.Allocator;

pub const ClientType = rpc.ClientType;
pub const Payload = rpc.Payload;
pub const ResultType = rpc.ResultType;

const ErrorSet = error{
    ApiNotFound,
};

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

        fn checkApiAvailable(self: Self, api_name: []const u8) bool {
            const api_infos = self.nvim_info.arr[1].map;
            const funcs = (api_infos.get("functions") orelse return false).arr;
            for (funcs) |func| {
                const val = func.map.get("name") orelse continue;
                const func_name = val.str.value();
                if (api_name.len == func_name.len and u8Eql(func_name, api_name)) {
                    return true;
                }
            }
            return false;
        }

        pub fn call(self: *Self, api_name: []const u8, params: rpc.Payload) !rpc.ResultType {
            if (!self.checkApiAvailable(api_name))
                return ErrorSet.ApiNotFound;
            return self.rpc_client.call(api_name, params);
        }

        pub fn notify(self: *Self, api_name: []const u8, params: rpc.Payload) !void {
            if (!self.checkApiAvailable(api_name))
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
    };
}

fn u8Eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
