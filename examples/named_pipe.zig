const std = @import("std");
const znvim = @import("znvim");

const nvim_pid: u16 = 28484;
const unique_number: u16 = 0;

const named_pipe = std.fmt.comptimePrint(
    "\\\\.\\pipe\\nvim.{}.{}",
    .{ nvim_pid, unique_number },
);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("memory leak!");
    }

    const pipe = try znvim.connectNamedPipe(named_pipe, allocator);
    defer pipe.close();
    // get znvim client_type
    const ClientType = znvim.DefaultClientType(struct {}, .file);

    const client = try ClientType.init(
        pipe,
        pipe,
        allocator,
        true,
    );
    defer client.deinit();

    std.log.info(
        "channel id id {}, function'nums is {}",
        .{ client.channel_id, client.metadata.functions.len },
    );
}
