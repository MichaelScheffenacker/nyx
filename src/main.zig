// server
const std = @import("std");

pub fn main() !void {
    const ipv6_family = std.posix.AF.INET6;
    const datagram = std.posix.SOCK.DGRAM;
    const socket_fd = try std.posix.socket(ipv6_family, datagram, 0);
    const len: usize = 16;
    var buf = [_]u8{0} ** len;
    //var buf : [16]u8 = undefined;
    const flags = std.os.linux.MSG.NOSIGNAL;
    const client_ipv6_addr = [16]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    //print_addr(addr_val);
    var client_socket_addr = std.posix.sockaddr.in6{ 
        .family = std.posix.AF.INET6, 
        .port = std.mem.nativeToBig(u16, 5001), 
        .flowinfo = 0, 
        .addr = client_ipv6_addr, 
        .scope_id = 0 
    };
    //std.debug.print("\n{any}\n\n", .{addr});
    const client_socket_addr_cp: *const std.os.linux.sockaddr = @ptrCast(&client_socket_addr);
    const client_socket_addr_p: ?* std.posix.sockaddr = @ptrCast(&client_socket_addr);
    var client_socket_addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in6);

   _ = try std.posix.bind(socket_fd, client_socket_addr_cp, client_socket_addr_len);
    while (true) {
        buf = [_]u8{0} ** len;
        _ = try std.posix.recvfrom(socket_fd, buf[0..len], flags, client_socket_addr_p, &client_socket_addr_len);
        std.debug.print("{s} {any}\n", .{buf, buf.len});
        for (5..8) |i| buf[i] = '0';
        _ = try std.posix.sendto(socket_fd, &buf, flags, client_socket_addr_p, client_socket_addr_len);
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
