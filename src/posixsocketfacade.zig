// Posix Socket Facade

const std = @import("std");

pub const PosixSocketFacade = struct{
    // no idea what this flag does; might be worth to research at some point
    const flags = std.os.linux.MSG.NOSIGNAL;
    // only ipv6 addresses are supported; this might be permament
    const socket_addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in6);

    socket_fd: std.posix.socket_t,

    pub fn init() !PosixSocketFacade {

        // create IPv6 UDP posix socket
        const ipv6_family = std.posix.AF.INET6;
        const datagram = std.posix.SOCK.DGRAM;
        const socket_fd = try std.posix.socket(ipv6_family, datagram, 0);

        return PosixSocketFacade{
            .socket_fd = socket_fd,
        };
    }

    pub fn bind(self: PosixSocketFacade, ipv6: u128, port: u16) !void {
        const socket_in6_addr = std.posix.sockaddr.in6{
            .family = std.posix.AF.INET6,
            .port = std.mem.nativeToBig(u16, port),
            .flowinfo = 0,
            .addr = ipv6_natural_2_ipv6_posix(ipv6),
            .scope_id = 0
        };

        // posix sockets do some pointer shenanigans to allow different address fromats
        // see https://stackoverflow.com/questions/18609397/whats-the-difference-between-sockaddr-sockaddr-in-and-sockaddr-in6
        const socket_oblique_addr_cp: *const std.posix.sockaddr = @ptrCast(&socket_in6_addr);

        _ = try std.posix.bind(
            self.socket_fd,
            socket_oblique_addr_cp,
            socket_addr_len
        );
    }

    pub fn receiveFrom(self: PosixSocketFacade, buf: []u8) !std.posix.sockaddr.in6 {
        // todo: it should be possible to initialize sender_addr with 0
        var sender_in6_addr: std.posix.sockaddr.in6 = undefined;
        // see the comment in bind() for the oblique pointer
        const sender_oblique_addr_p: *std.posix.sockaddr = @ptrCast(&sender_in6_addr);
        // recvfrom() rejects an uninitialized sender_addr_size; unsure why
        var sender_addr_size: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in6);

        const message_len = try std.posix.recvfrom(
            self.socket_fd,
            buf,
            flags,
            sender_oblique_addr_p,
            &sender_addr_size
        );

        // returned message length is ignored for now
        // _ = sender_addr_len;
        std.debug.print("{any} ", .{message_len});

        if (sender_addr_size != @sizeOf(std.posix.sockaddr.in6)) {
            return error.UnsupportedAddressFamily;
        }

        return sender_in6_addr;
    }

    pub fn sendTo(self: PosixSocketFacade, buf: []u8, dest_addr: std.posix.sockaddr.in6) !void {
        // see the comment in bind() for the oblique pointer
        const dest_oblique_addr_p: *const std.posix.sockaddr = @ptrCast(&dest_addr);

        _ = try std.posix.sendto(
            self.socket_fd,
            buf,
            flags,
            dest_oblique_addr_p,
            socket_addr_len
        );
    }

    // the by std.posix required [16]u8 ipv6 contradicts the convention
    // of writing ipv6 addresses as 8 hex quartets; u128 provides a better interface
    fn ipv6_natural_2_ipv6_posix (ipv6: u128) [16]u8 {
        var address_bits = ipv6;
        var ipv6_posix = [1]u8{0} ** 16;
        const offset = ipv6_posix.len - 1;
        const bits_in_halfquartet = 8;
        for (ipv6_posix, 0..) |_, i| {
            ipv6_posix[offset - i] = @truncate(address_bits);
            address_bits = address_bits >> bits_in_halfquartet;
        }
        return ipv6_posix;
    }
};

test "ipv6_natural_2_ipv6_posix" {
    const ipv6 = 0x1234_5678_9abc_def0_1234_5678_9abc_def0;
    const result = PosixSocketFacade.ipv6_natural_2_ipv6_posix(ipv6);
    const expected = [8]u8{0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0} ** 2;
    for (result, expected) |res, exp| {
        try std.testing.expect( res == exp);
    }

    const ipv6_0 = 0x0000_0000_0000_0000_0000_0000_0000_0000;
    const result0 = PosixSocketFacade.ipv6_natural_2_ipv6_posix(ipv6_0);
    const expected0 = [_]u8{0} ** 16;
    for (result0, expected0) |res, exp| {
        try std.testing.expect( res == exp);
    }

    const ipv6_1 = 0x0000_0000_0000_0000_0000_0000_0000_0001;
    const result1 = PosixSocketFacade.ipv6_natural_2_ipv6_posix(ipv6_1);
    const expected1 = [_]u8{0} ** 15 ++ [_]u8{1};
    for (result1, expected1) |res, exp| {
        try std.testing.expect( res == exp);
    }
}
