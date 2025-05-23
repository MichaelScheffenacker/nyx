// nyx server
const std = @import("std");
const PosixSocketFacade = @import("posixsocketfacade.zig").PosixSocketFacade;

const max_content_len = 65536;

fn getWithFallback(map: std.StringHashMap([]const u8), id: []const u8) []const u8 {
    return map.get(id) orelse map.get("/404") orelse "<err: missing /404>";
}

fn truncate(alloc: std.mem.Allocator, str: []const u8, len: u64) ![]const u8 {
    if (str.len > len) {
        const truncated = str[0..len];
        return try std.mem.concat(alloc, u8, &.{truncated, "…\n"});
    } else {
        return str;
    }
}

pub fn main() !void {

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const server_dir_path = "/home/msc/temporary/nyx";
    var page_map = std.StringHashMap([]const u8).init(alloc);
    defer page_map.deinit();
    try loadPages(server_dir_path, &page_map, alloc);

    var  page_iterator = page_map.iterator();
    while (page_iterator.next()) |page| {
        std.debug.print("{s}: {s}", .{page.key_ptr.*, try truncate(alloc, page.value_ptr.*, 50 )});
    }

    const col_width = 50;
    var content: []const u8 = page_map.get("/a.txt") orelse "<no entry>";
    const selis_break: u64 = 1000;
    const selis = content[0..selis_break];
    var col_break: u64 = 500;
    while (selis[col_break] != ' ') {
        col_break -= 1;
    }
    const cols = [_][]const u8{
        selis[0..col_break],
        selis[col_break..selis_break],
    };

    var line = [1][col_width]u8{[_]u8{' '} ** col_width} ** 2;

    var line_break = [1]u64{0} ** 2;
    for (0..12) |_| {
        line = [1][col_width]u8{[_]u8{' '} ** col_width} ** 2;
        for (cols, 0..) |col, i| {
            //const offset: u64 = if (line_break == 0) 0 else 1;
            //const prev_line_break: u64 = line_break + offset;
            var char_pos: u64 = 0;
            while (
                col[line_break[i]] != '\n'
                and char_pos < col_width
                and line_break[i] < cols[i].len - 1
            ) {
                line[i][char_pos] = col[line_break[i]];
                line_break[i] += 1;
                char_pos += 1;
            }
            if (col[line_break[i]] == '\n') {
                line[i][char_pos] = ' ';
                line_break[i] += 1;
                char_pos += 1;
            } else {
                line_break[i] -= 1;
                char_pos -= 1;
                while (col[line_break[i]] != ' ') {
                    line[i][char_pos] = ' ';
                    line_break[i] -= 1;
                    char_pos -= 1;
                }
            }
            // line_break[0] += 1;
            // line_break[1] += 1;
        
        // const offset2: u64 = if (line_break_2 == 0) 0 else 1;
        // const prev_line_break_2: u64 = line_break_2 + offset2;
        // line_break_2 += col_width;
        // while (col2[line_break_2] != ' ') {
        //     line_break_2 -= 1;
        // }
        //line[i] = col[prev_line_break..line_break];
        //const line2 = col2[prev_line_break_2..line_break_2];
        }
        

        const padding_buf = " " ** col_width;
        const padding =  padding_buf[0..50 - line[0].len + 5];
        const window_row_strings = &.{&line[0], padding, &line[1]};
        const window_row = try std.mem.concat(alloc, u8, window_row_strings);
        std.debug.print("{s}\n", .{window_row});
    }
    


    const stdout = std.io.getStdOut();

    var winsize: std.posix.winsize = undefined;
    const result = std.posix.system.ioctl(stdout.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize));
    switch (std.posix.errno(result)) {
        .SUCCESS => {},
        else => return error.IoctlError,
    }

    std.debug.print("{any} {any}", .{winsize.col, winsize.row});


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
        content = getWithFallback(page_map, id);
        for (content, 0..) |char, i| {
            if (i >= buf.len) { break; }
            buf[i] = char;
        }
        try listen_socket.sendTo(buf[0..len], client_socket_address);

        //todo: remove sleep when everything is stable
        std.time.sleep(200 * std.time.ns_per_ms);
    }
}

fn loadPages(
        server_dir_path: []const u8, 
        page_map: *std.StringHashMap([]const u8), 
        alloc: std.mem.Allocator
    ) !void {
    const dir_flags = .{ .iterate=true };
    var server_dir = try std.fs.openDirAbsolute(server_dir_path, dir_flags);

    var server_dir_iterator = server_dir.iterate();
    while (try server_dir_iterator.next()) |file| {
        if (
            file.kind != std.fs.File.Kind.file
            or file.name[0] == '.'
        ) {
            continue;
        }

        const id_strings = &.{"/", file.name};
        const page_id = try std.mem.concat(alloc, u8, id_strings);

        const path_strings = &.{server_dir_path, "/", file.name};
        const path = try std.mem.concat(alloc, u8, path_strings);

        const page_flags = .{ .mode = .read_only };
        var page_fd = try std.fs.openFileAbsolute(path, page_flags);
        defer page_fd.close();
        
        const content = try page_fd.readToEndAlloc(alloc, max_content_len);
        try page_map.put(page_id, content[0..]);
    }
}

fn printAddr(addr_val: [16]u8) void {
    for (addr_val, 0..) |val, i| {
        std.debug.print("{x:0>2}", .{val});
        if (i % 2 == 1 and i < 14) {
            std.debug.print(":", .{});
        }
    }
    std.debug.print("\n\n{any}\n\n\n", .{addr_val});
}
