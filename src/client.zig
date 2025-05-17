// nyx client
const std = @import("std");
const Socket = @import("posixsocketfacade.zig").PosixSocketFacade;

pub fn main() !void {
    const len: usize = 400;
    var buf_buf = [_]u8{0} ** len;
    var buf = buf_buf[0..];

    const server_ipv6_addr = 0x0000_0000_0000_0000_0000_0000_0000_0001;
    const socket = try Socket.init();
    buf[1] += 1;
    
    const request = "asdf";
    if (request.len <= len) {
        for (request, 0..) |char, i| {
            buf[i] = char;
        }
    }

    const server_posix_addr = Socket.ipv6_addr_2_posix_addr(server_ipv6_addr, 5001);
    try socket.sendTo(buf, server_posix_addr);
    _ = try socket.receiveFrom(buf);

    std.debug.print("{s}\n", .{buf});
}