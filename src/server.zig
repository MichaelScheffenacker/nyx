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

    const server_dir_path = "/home/msc/temporary/nyx";
    const dir_flags = .{ .iterate=true };
    var server_dir = try std.fs.openDirAbsolute(server_dir_path, dir_flags);

    var page_map = std.StringHashMap([]const u8).init(allocator);
    defer page_map.deinit();

    var server_dir_iterator = server_dir.iterate();
    while (try server_dir_iterator.next()) |file| {
        if (file.kind != std.fs.File.Kind.file) {
            continue;
        }

        const id_strings = &.{"/", file.name};
        const page_id = try std.mem.concat(allocator, u8, id_strings);

        const path_strings = &.{server_dir_path, "/", file.name};
        const path = try std.mem.concat(allocator, u8, path_strings);

        const page_flags = .{ .mode = .read_only };
        var page_fd = try std.fs.openFileAbsolute(path, page_flags);
        defer page_fd.close();
        
        const content = try page_fd.readToEndAlloc(allocator, max_content_len);
        try page_map.put(page_id, content[0..]);
    }

    var  page_iterator = page_map.iterator();
    while (page_iterator.next()) |page| {
        std.debug.print("{s}: {s}", .{page.key_ptr.*, page.value_ptr.*});
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
        const content = getWithFallback(page_map, id);
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
