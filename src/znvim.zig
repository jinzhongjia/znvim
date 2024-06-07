const std = @import("std");
const builtin = @import("builtin");
const rpc = @import("rpc.zig");

const Allocator = std.mem.Allocator;

pub const ClientType = rpc.ClientType;
pub const Payload = rpc.Payload;
pub const ResultType = rpc.ResultType;

/// error sets
pub const ErrorSet = error{
    ApiNotFound,
    ApiDeprecated,
    NotGetVersion,
    NotGetApiLevel,
    NotGetApiInfo,
    GetApiInfoFailed,
};

/// the api name for get api info
const infoApiName = "nvim_get_api_info";

pub const connectNamedPipe = rpc.connectNamedPipe;

/// current build mode
const build_mode = builtin.mode;

/// default delay time, nanosecond
pub const default_delay_time = 3_0_000_000;
/// default buffer size
pub const default_buffer_size = 20 * 1024;

/// default Client type
/// buffer size is 20480
/// delay time is 3_0_000_000 nanoseconds
pub fn defaultClient(
    comptime client_tag: ClientType,
    comptime user_data: type,
) type {
    return Client(
        default_buffer_size,
        client_tag,
        user_data,
        default_delay_time,
    );
}

/// init a new client type
/// recommend to use defaultClient
pub fn Client(
    comptime buffer_size: usize,
    comptime client_tag: ClientType,
    comptime user_data: type,
    comptime delay_time: u64,
) type {
    if (builtin.os.tag == .windows and client_tag == .stdio) {
        @compileError("for windows, we only can use .pipe or .socket!");
    }

    return struct {
        /// znvim type self
        const Self = @This();

        /// the rpc client type
        pub const RpcClientType = rpc.RpcClientType(
            buffer_size,
            client_tag,
            user_data,
            delay_time,
        );

        /// request method type
        pub const ReqMethodType = RpcClientType.ReqMethodType;
        /// notify method type
        pub const NotifyMethodType = RpcClientType.NotifyMethodType;
        /// the type for trans
        pub const TransType = RpcClientType.TransType;

        /// the rpc client
        rpc_client: RpcClientType,
        /// store neovim api info
        /// used to check api avaiable
        nvim_info: ?rpc.Payload = null,

        /// init znvim instance
        /// the caller should call `deinit`
        pub fn init(
            trans_writer: TransType,
            trans_reader: TransType,
            allocator: Allocator,
        ) !Self {
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

        /// deinit the znvim instance
        pub fn deinit(self: *Self) void {
            if (self.nvim_info) |info| {
                self.rpc_client.freePayload(info);
            }
            self.rpc_client.deinit();
        }

        /// exit the znvim
        /// this is thread safe
        pub fn exit(self: *Self) void {
            self.rpc_client.exit();
        }

        /// run the loop thread
        /// this will spawn two thread, one receives message
        /// the other sends message to server
        pub fn loop(self: *Self) !void {
            try self.rpc_client.loop();
        }

        /// for freeing payload
        /// note: this only can free the payload
        /// which used allocator from same znvim instance
        pub fn freePayload(self: Self, payload: Payload) void {
            self.rpc_client.freePayload(payload);
        }

        /// for freeing result type
        /// this is just a wrapping for freePayload
        pub fn freeResultType(self: Self, result_type: ResultType) void {
            self.rpc_client.freeResultType(result_type);
        }

        /// register request method
        pub fn registerRequestMethod(self: *Self, method_name: []const u8, func: ReqMethodType) !void {
            return self.rpc_client.registerRequestMethod(method_name, func);
        }

        /// register notify method
        pub fn registerNotifyMethod(self: *Self, method_name: []const u8, func: NotifyMethodType) !void {
            return self.rpc_client.registerNotifyMethod(method_name, func);
        }

        /// unregister method
        pub fn unregisterMehod(self: *Self, method_name: []const u8) void {
            self.rpc_client.unregisterMethod(method_name);
        }

        /// call server api
        /// this will be blocked until znvim instance receive corresponding response from server
        pub fn call(self: *Self, method_name: []const u8, params: Payload) !ResultType {
            return self.rpc_client.call(method_name, params);
        }

        /// notify server
        /// this is no-blocked, so when you call this method it will return immediately!
        pub fn notify(self: *Self, method_name: []const u8, params: Payload) !void {
            return self.rpc_client.notify(method_name, params);
        }

        /// get the znvim instance allocator
        inline fn getAllocator(self: Self) Allocator {
            return self.rpc_client.allocator;
        }

        /// get api infos, recommend to call this after connecting server
        /// this will can enable api check
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

        /// get channel id
        pub fn getChannelID(self: Self) !u32 {
            if (self.nvim_info) |info| {
                return @intCast(info.arr[0].uint);
            }
            return ErrorSet.NotGetApiInfo;
        }

        /// get api infos
        fn apiInfos(self: Self) !Payload {
            if (self.nvim_info) |info| {
                return info.arr[1];
            }
            return ErrorSet.NotGetApiInfo;
        }
    };
}
