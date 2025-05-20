// nyx server
const std = @import("std");
const PosixSocketFacade = @import("posixsocketfacade.zig").PosixSocketFacade;

const max_content_len = 65536;

fn getWithFallback(map: std.StringHashMap([]const u8), id: []const u8) []const u8 {
    return map.get(id) orelse map.get("/404") orelse "<err: missing /404>";
}

pub fn main() !void {

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const base_path = "/home/msc/temporary/nyx";
    var dir = try std.fs.openDirAbsolute(base_path, .{ .iterate=true});

    var map = std.StringHashMap([]const u8).init(allocator);
    defer map.deinit();

    var dir_iterator = dir.iterate();
    while (try dir_iterator.next()) |file| {
        if (file.kind != std.fs.File.Kind.file) {
            continue;
        }

        const id = try std.mem.concat(allocator, u8, &.{"/", file.name});
        const path = try std.mem.concat(allocator, u8, &.{base_path, id});
        const flags = .{ .mode = .read_only};
        var file_descriptor = try std.fs.openFileAbsolute(path, flags);
        defer file_descriptor.close();
        const content = try file_descriptor.readToEndAlloc(allocator, max_content_len);

        try map.put(id, content[0..]);
    }

    var  map_iterator = map.iterator();
    while (map_iterator.next()) |entry| {
        std.debug.print("{s}: {s}", .{entry.key_ptr.*, entry.value_ptr.*});
    }


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
        const content = getWithFallback(map, id);
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
