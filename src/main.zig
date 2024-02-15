const std = @import("std");
const net = std.net;

pub fn main() !void {
    const peer = try net.Address.parseIp4("127.0.0.1", 9090);
    const stream = try net.tcpConnectToAddress(peer);
    defer stream.close();

    _ = try stream.write("55");
}
