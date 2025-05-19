// nyx server
const std = @import("std");
const PosixSocketFacade = @import("posixsocketfacade.zig").PosixSocketFacade;

const Ressource = struct {
    const max_path_len = 128;
    const max_id_len = 64;
    const max_content_len = 65536;
    path: []const u8,
    id: []const u8,
    content_buf: [max_content_len]u8,
    fn init(path: []const u8, id: []const u8) !Ressource {
        var content_buf = [1]u8{0} ** max_content_len;
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

    // makeshift hash function
    pub fn hash(id: []const u8) !u64 {
    if (id.len > max_id_len) {
        return error.StringTooLong;
    }
    const primes = [max_id_len]u16{2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127, 131, 137, 139, 149, 151, 157, 163, 167, 173, 179, 181, 191, 193, 197, 199, 211, 223, 227, 229, 233, 239, 241, 251, 257, 263, 269, 271, 277, 281, 283, 293, 307, 311};
    var sum: u64 = 0;
    for (id, 0..) |char, i| {
        // summing prime products is not even injective (2+3=5)
        sum += primes[i] * char;
    }
    return sum;
}
};

pub fn main() !void {

    const rsrcs = [_]Ressource{
        try Ressource.init("/home/msc/temporary/nyx/404", "/404"),
        try Ressource.init("/home/msc/temporary/nyx/a.txt", "/a.txt"),
        try Ressource.init("/home/msc/temporary/nyx/b.txt", "/b.txt"),
    };

    const len: usize = 400;
    var buf = [_]u8{0} ** len;
    
    const client_ipv6_addr = 0x0000_0000_0000_0000_0000_0000_0000_0000;
    const listen_socket = try PosixSocketFacade.create();
    defer listen_socket.close();
    try listen_socket.bind(client_ipv6_addr, 5001);

    while (true) {
        buf = [_]u8{0} ** len;
        const client_socket_address = try listen_socket.receiveFrom(buf[0..]);

        var request_len:u64 = 0;
        for (buf) |char| {
            if (char == 0) { break; }
            request_len += 1;
        }
        const id: []const u8 = buf[0..request_len];
        std.debug.print("{s} ({any}/{any})\n", .{id, request_len, len});
        const content = switch (try Ressource.hash(id)) {
            else => rsrcs[0].content_buf,
            try Ressource.hash("/a.txt") => rsrcs[1].content_buf,
            try Ressource.hash("/b.txt") => rsrcs[2].content_buf,
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

fn print_addr(addr_val: [16]u8) void {
    for (addr_val, 0..) |val, i| {
        std.debug.print("{x:0>2}", .{val});
        if (i % 2 == 1 and i < 14) {
            std.debug.print(":", .{});
        }
    }
    std.debug.print("\n\n{any}\n\n\n", .{addr_val});
}
