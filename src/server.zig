// nyx server
const std = @import("std");
const PosixSocketFacade = @import("posixsocketfacade.zig").PosixSocketFacade;

const Ressource = struct {
        path: []const u8,
        id: []const u8,
        content_buf: [65536]u8,
        fn init(path: []const u8, id: []const u8) !Ressource {
            var content_buf = [1]u8{0} ** 65536;
            const flags = .{ .mode = .read_only};
            var file = try std.fs.openFileAbsolute(path, flags);
            defer file.close();
            var buf_reader = std.io.bufferedReader(file.reader());
            var in_stream = buf_reader.reader();
            _ = try in_stream.readAll(content_buf[0..]);
            return Ressource{
                .path = path,
                .id = id,
                .content_buf = content_buf,
            };
        }
    };

pub fn main() !void {

    const rsrcs = [_]Ressource{
        try Ressource.init("/home/msc/temporary/nyx/404", "/404"),
        try Ressource.init("/home/msc/temporary/nyx/a.txt", "/a.txt"),
        try Ressource.init("/home/msc/temporary/nyx/b.txt", "/b.txt"),
    };

    // var file = try std.fs.openFileAbsolute("/home/msc/temporary/nyx/a.txt", .{ .mode = .read_only});
    // defer file.close();
    // var buf_reader = std.io.bufferedReader(file.reader());
    // var in_stream = buf_reader.reader();
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

        //_ = try in_stream.readAll(buf[0..]);
        // for (5..8) |i| buf[i] = '0';
        var request_len:u64 = 0;
        for (buf) |char| {
            if (char == 0) { break; }
            request_len += 1;
        }
        const id: []const u8 = buf[0..request_len];
        std.debug.print("{s}{any}", .{id, request_len});
        const content = switch (hash(id)) {
            else => rsrcs[0].content_buf,
            hash("/a.txt") => rsrcs[1].content_buf,
            hash("/b.txt") => rsrcs[2].content_buf,
        };
        for (content, 0..) |char, i| {
            if (i >= buf.len) { break; }
            buf[i] = char;
        }
        try listen_socket.sendTo(buf[0..len], client_socket_address);

        //todo: remove sleep when everything is stable
        std.time.sleep(200 * std.time.ns_per_ms);
    }
}

fn hash(str: []const u8) u64 {
    const primes = [64]u16{2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127, 131, 137, 139, 149, 151, 157, 163, 167, 173, 179, 181, 191, 193, 197, 199, 211, 223, 227, 229, 233, 239, 241, 251, 257, 263, 269, 271, 277, 281, 283, 293, 307, 311};
    var sum: u64 = 0;
    for (str, 0..) |char, i| {
        sum += primes[i] * char;
    }
    return sum;
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
