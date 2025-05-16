// nyx client
const std = @import("std");

pub fn main() !void {
    std.debug.print("asdf\n", .{});
    // try network.init();
    // defer network.deinit();

    // const port_number = 5001;

    // //create udp socket
    // var socket = try network.Socket.create(.ipv6, .udp);
    // defer socket.close();

    // const incoming_endpoint = network.EndPoint{
    //     .address = network.Address{ .ipv6 = network.Address.IPv6.loopback },
    //     .port = port_number,
    // };

    //std.debug.print("{any}\n", .{incoming_endpoint.address.ipv6.value});
    // socket.bind(incoming_endpoint) catch |err| {
    //     std.debug.print("failed to bind to {any}:{any}\n", .{ incoming_endpoint, err });
    // };  // client does not need to bind in a browser szenario 

    // const buffer_size: usize = 400;
    // var buf = [_]u8{0} ** buffer_size;

    // const msg = "asdf";
    // if (msg.len <= buffer_size) {
    //     for (msg, 0..) |char, i| {
    //         buf[i] = char;
    //     }
    // }
    // _ = try socket.sendTo(incoming_endpoint, buf[0..]);

    // buf = [_]u8{0} ** buffer_size;
    // _ = try socket.receiveFrom(buf[0..]);
    // std.debug.print("{s}\n", .{ buf });
}