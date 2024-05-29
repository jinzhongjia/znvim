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
};

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
        // TODO: add nvim info support
        // nvim_info: rpc.Payload,

        /// init
        pub fn init(trans_writer: TransType, trans_reader: TransType, allocator: Allocator) !Self {
            var rpc_client = try RpcClientType.init(
                trans_writer,
                trans_reader,
                allocator,
            );
            errdefer rpc_client.deinit();

            // const arr = try Payload.arrPayload(0, allocator);
            // defer arr.free(allocator);
            //
            // const result = try rpc_client.call("nvim_get_api_info", arr);

            return Self{
                .rpc_client = rpc_client,
                // .nvim_info = result.result,
            };
        }

        pub fn deinit(self: *Self) void {
            self.rpc_client.deinit();
        }
    };
}
