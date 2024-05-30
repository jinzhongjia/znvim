const std = @import("std");
const builtin = @import("builtin");
const rpc = @import("rpc.zig");
const named_pipe = @import("named_pipe.zig");

const Allocator = std.mem.Allocator;

pub const ClientType = rpc.ClientType;
pub const Payload = rpc.Payload;
pub const ResultType = rpc.ResultType;

const ErrorSet = error{
    ApiNotFound,
    ApiDeprecated,
    NotGetVersion,
    NotGetApiLevel,
    GetApiInfoFailed,
};

const infoApiName = "nvim_get_api_info";

pub const connectNamedPipe = named_pipe.connectNamedPipe;

// current build mode
const build_mode = builtin.mode;

pub fn Client(comptime buffer_size: usize, comptime client_tag: ClientType, comptime user_data: type) type {
    const RpcClientType = rpc.RpcClientType(
        buffer_size,
        client_tag,
        user_data,
    );

    return struct {
        const Self = @This();
        pub const TransType = RpcClientType.TransType;

        rpc_client: RpcClientType,
        nvim_info: ?rpc.Payload = null,

        /// init
        pub fn init(trans_writer: TransType, trans_reader: TransType, allocator: Allocator) !Self {
            var rpc_client = try RpcClientType.init(
                trans_writer,
                trans_reader,
                allocator,
            );
            errdefer rpc_client.deinit();

            return Self{
                .rpc_client = rpc_client,
            };
        }

        pub fn deinit(self: *Self) void {
            self.rpc_client.freePayload(self.nvim_info.?);
            self.rpc_client.deinit();
        }

        pub fn freePayload(self: Self, payload: Payload) void {
            self.rpc_client.freePayload(payload);
        }

        pub fn call(self: *Self, method_name: []const u8, params: Payload) !ResultType {
            return self.rpc_client.call(method_name, params);
        }

        inline fn getAllocator(self: Self) Allocator {
            return self.rpc_client.allocator;
        }

        pub fn getApiInfo(self: *Self) !void {
            if (self.nvim_info != null) {
                return;
            }
            const params = try Payload.arrPayload(0, self.getAllocator());
            defer self.freePayload(params);
            const result = try self.call(infoApiName, params);
            if (result == .err) {
                return ErrorSet.GetApiInfoFailed;
            }
            self.nvim_info = result.result;
        }

        pub fn getChannelID(self: Self) u32 {
            return @intCast(self.nvim_info.?.arr[0].uint);
        }
    };
}
