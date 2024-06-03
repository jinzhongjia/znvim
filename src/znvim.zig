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
    NotGetApiInfo,
    GetApiInfoFailed,
};

const infoApiName = "nvim_get_api_info";

pub const connectNamedPipe = named_pipe.connectNamedPipe;

// current build mode
const build_mode = builtin.mode;

const default_delay_time = 3_0_000_000;

pub fn defaultClient(comptime client_tag: ClientType, comptime user_data: type) type {
    return Client(
        20480,
        client_tag,
        user_data,
        default_delay_time,
    );
}

pub fn Client(comptime buffer_size: usize, comptime client_tag: ClientType, comptime user_data: type, comptime delay_time: u64) type {
    const RpcClientType = rpc.RpcClientType(
        buffer_size,
        client_tag,
        user_data,
        delay_time,
    );

    return struct {
        const Self = @This();
        pub const ReqMethodType = RpcClientType.ReqMethodType;
        pub const NotifyMethodType = RpcClientType.NotifyMethodType;
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
            if (self.nvim_info) |info| {
                self.rpc_client.freePayload(info);
            }
            self.rpc_client.deinit();
        }

        pub fn exit(self: *Self) void {
            self.rpc_client.exit();
        }

        pub fn loop(self: *Self) !void {
            try self.rpc_client.loop();
        }

        pub fn freePayload(self: Self, payload: Payload) void {
            self.rpc_client.freePayload(payload);
        }

        pub fn freeResultType(self: Self, result_type: ResultType) void {
            self.rpc_client.freeResultType(result_type);
        }

        pub fn registerRequestMethod(self: *Self, method_name: []const u8, func: ReqMethodType) !void {
            return self.rpc_client.registerRequestMethod(method_name, func);
        }

        pub fn registerNotifyMethod(self: *Self, method_name: []const u8, func: NotifyMethodType) !void {
            return self.rpc_client.registerNotifyMethod(method_name, func);
        }

        pub fn call(self: *Self, method_name: []const u8, params: Payload) !ResultType {
            return self.rpc_client.call(method_name, params);
        }

        pub fn notify(self: *Self, method_name: []const u8, params: Payload) !void {
            return self.rpc_client.notify(method_name, params);
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

        pub fn getChannelID(self: Self) !u32 {
            if (self.nvim_info) |info| {
                return @intCast(info.arr[0].uint);
            }
            return ErrorSet.NotGetApiInfo;
        }
    };
}
