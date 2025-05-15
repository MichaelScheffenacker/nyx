// server
const std = @import("std");

const len: usize = 1024;

pub fn main() !void {
    
    
    var buf = [_]u8{0} ** len;
    
    // const client_ipv6_addr = [8]u16{ 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000 };
    const client_ipv6_addr = [_]u8{0} ** 16;
    const listen_socket = try PosixSocketFacade.init();
    try listen_socket.bind(client_ipv6_addr, 5001);
    while (true) {
        buf = [_]u8{0} ** len;
        const client_socket_address = try listen_socket.receive(buf[0..len]);
        std.debug.print("{s} {any}\n", .{buf, buf.len});
        for (5..8) |i| buf[i] = '0';
        try listen_socket.sendTo(buf, client_socket_address);
        std.time.sleep(200 * std.time.ns_per_ms);
    }
}

const PosixSocketFacade = struct{
    // no idea what this flag does; might be worth to research at some point
    const flags = std.os.linux.MSG.NOSIGNAL;
    // only ipv6 addresses are supported; this might be permament
    const socket_addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in6);

    socket_fd: std.posix.socket_t,

    fn init() !PosixSocketFacade {

        // create IPv6 UDP posix socket
        const ipv6_family = std.posix.AF.INET6;
        const datagram = std.posix.SOCK.DGRAM;
        const socket_fd = try std.posix.socket(ipv6_family, datagram, 0);

        return PosixSocketFacade{
            .socket_fd = socket_fd,
        };
    }

    fn bind(self: PosixSocketFacade, ipv6: [16]u8, port: u16) !void {

        const socket_in6_addr = std.posix.sockaddr.in6{
            .family = std.posix.AF.INET6,
            .port = std.mem.nativeToBig(u16, port),
            .flowinfo = 0,
            .addr = ipv6,
            .scope_id = 0
        };
        const socket_oblique_addr_cp: *const std.os.linux.sockaddr = @ptrCast(&socket_in6_addr);

        _ = try std.posix.bind(
            self.socket_fd, 
            socket_oblique_addr_cp,                         
            socket_addr_len
        );
    }

    fn receive(self: PosixSocketFacade, buf: []u8) !std.posix.sockaddr.in6 {
        // todo: it should be possible to initialize sender_addr with 0
        var sender_in6_addr: std.posix.sockaddr.in6 = undefined;
        var sender_addr_size: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in6);
        const sender_oblique_addr_p: *std.posix.sockaddr = @ptrCast(&sender_in6_addr);
        const sender_addr_len = try std.posix.recvfrom(
            self.socket_fd,
            buf,
            flags,
            sender_oblique_addr_p,
            &sender_addr_size
        );

        // returned sender address length is ignored for now; valid ipv6 address length assumed
        _ = sender_addr_len;

        return sender_in6_addr;
    }

    fn sendTo(self: PosixSocketFacade, buf: [len]u8, dest_addr: std.posix.sockaddr.in6) !void {
        const dest_oblique_addr_p: *const std.posix.sockaddr = @ptrCast(&dest_addr);
        _ = try std.posix.sendto(
            self.socket_fd,
            &buf,
            flags,
            dest_oblique_addr_p,
            socket_addr_len
        );
    }

    fn ipv6_natural_2_ipv6_posix (ipv6: u128) [16]u8 {

        // the by std.posix required [16]u8 ipv6 contradicts the by convention
        // of writing ipv6 addresses as 8 hex quartets
        var ipv6_posix = [_]u8{0} ** 16;
        for (ipv6, 0..) |quartet, i| {
            const upper_halfquartet: u16 = quartet / 0x100;
            const lower_halfquartet: u16 = quartet - upper_halfquartet * 0x100;
            ipv6_posix[i*2] = @truncate(upper_halfquartet);
            ipv6_posix[i*2 + 1] = @truncate(lower_halfquartet);
        }
        return ipv6_posix;
    }
};

fn print_addr(addr_val: [16]u8) void {
    for (addr_val, 0..) |val, i| {
        std.debug.print("{x:0>2}", .{val});
        if (i % 2 == 1 and i < 14) {
            std.debug.print(":", .{});
        }
    }
    std.debug.print("\n\n{any}\n\n\n", .{addr_val});
}
