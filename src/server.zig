// nyx server
const std = @import("std");
const PosixSocketFacade = @import("posixsocketfacade.zig").PosixSocketFacade;

pub fn main() !void {
    
    var file = try std.fs.openFileAbsolute("/home/msc/temporary/nyx/a.txt", .{ .mode = .read_only});
    defer file.close();
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();
    // var line_buf_buf: [1024]u8 = undefined;
    // var line_buf = line_buf_buf[0..];
    // while (try in_stream.readUntilDelimiterOrEof(line_buf, '\n')) |line| {
    //     _ = line;
    // }

    const len: usize = 400;
    var buf = [_]u8{0} ** len;
    
    const client_ipv6_addr = 0x0000_0000_0000_0000_0000_0000_0000_0000;
    const listen_socket = try PosixSocketFacade.create();
    defer listen_socket.close();
    try listen_socket.bind(client_ipv6_addr, 5001);

    while (true) {
        buf = [_]u8{0} ** len;
        const client_socket_address = try listen_socket.receiveFrom(buf[0..]);
        std.debug.print("{s} ({any})\n", .{buf, buf.len});

        _ = try in_stream.readAll(buf[0..]);
        // for (5..8) |i| buf[i] = '0';
        try listen_socket.sendTo(buf[0..], client_socket_address);

        //todo: remove sleep when everything is stable
        std.time.sleep(200 * std.time.ns_per_ms);
    }
}

fn print_addr(addr_val: [16]u8) void {
    for (addr_val, 0..) |val, i| {
        std.debug.print("{x:0>2}", .{val});
        if (i % 2 == 1 and i < 14) {
            std.debug.print(":", .{});
        }
    }
    std.debug.print("\n\n{any}\n\n\n", .{addr_val});
}
