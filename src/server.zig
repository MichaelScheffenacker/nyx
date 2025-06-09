// nyx server
const std = @import("std");
const PosixSocketFacade = @import("posixsocketfacade.zig").PosixSocketFacade;
const utf8 = @import("utf8.zig");

const max_content_len = 65536;

const col_width = 50;

/// Since a window column of text can be composed of many code points and even more bytes, for a given
/// column width the number of required bytes cannot be estimated. 
/// todo: change fixed length line buffers to a over all buffer where parts can be partitioned off for a line
const line_buf_len = col_width * 5;
var lines_buf = [1][line_buf_len]u8{[_]u8{0} ** line_buf_len} ** 1024;
var window_rows_buf = [1][line_buf_len*2]u8{[_]u8{0} ** (line_buf_len*2)} ** 1024;

pub fn main() !void {

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const server_dir_path = "/home/msc/temporary/nyx";
    var page_map = std.StringHashMap([]const u8).init(alloc);
    defer page_map.deinit();
    try loadPages(server_dir_path, &page_map, alloc);
    listPages(&page_map);

    var content: []const u8 = page_map.get("/a.txt") orelse "<no entry>";
    // std.debug.print("{any} {s}\n", .{content.len, content});
    const lines: [][line_buf_len]u8 = try parseLines(content);

    const window_rows = try generateWindowRows(
        lines,
        2,
        3,
        12,
        3
    );
    for (window_rows) |row| {
        std.debug.print("{s}\n", .{row});
    }

    const win_size = try elicitWindowSize();
    std.debug.print("win cols/rows: {any}/{any}\n", .{win_size.col, win_size.row});

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

fn listPages(page_map: *std.StringHashMap([]const u8)) void {
    var  page_iterator = page_map.iterator();
    while (page_iterator.next()) |page| {
        const page_content = page.value_ptr.*;
        const trucated_len = if (page_content.len < col_width) page_content.len else col_width;
        var truncated_page_content = [1]u8{0} ** col_width;
        for (0..trucated_len) |i| {
            truncated_page_content[i] = if (page_content[i] == '\n') '-' else page_content[i];
        }
        std.debug.print("{s}: {s}\n", .{page.key_ptr.*, truncated_page_content});
    }
}

fn parseLines(content: []const u8) ![][line_buf_len]u8 {
    var lines: [][line_buf_len]u8 = lines_buf[0..1];
    var line_index: u64 = 0;
    var line_spacing: u64 = 0;
    var line_len: u64 = 0;

    var code_unit_index: u64 = 0;
    var word_buf = [1]u8{0} ** line_buf_len;
    var word: []u8 = word_buf[0..0];
    var word_spacing: u64 = 0;
    while (code_unit_index < content.len) {
        if (line_index >= lines_buf.len - 1) {
            return error.LinesBufferFull;
        }

        const code_unit = content[code_unit_index];
        const code_point_len = try utf8.codePointLength(code_unit);
        const code_point = content[code_unit_index .. (code_unit_index + code_point_len)];
        // std.debug.print("{s}", .{code_point}); ////////////////////

        const code_point_spacing = try utf8.spacing(code_point);
        // if (code_point_spacing != 1 or code_point_len != 1) {
        //     std.debug.print("o{s} {any} {any} {X:0>4}\n", .{code_point, code_point_spacing, code_point_len, try utf8.cp_2_unicode_point(code_point)});
        // }
        
        // ### lines and words ###
        var word_len = word.len;
        if (try utf8.isWordSeparator(code_point) or try utf8.isLineSeperator(code_point)) {

            if (try utf8.isLineSeperator(code_point)) {
                for (word, 0..) |code_unit_loc, i| {
                    lines[line_index][line_len + i] = code_unit_loc;
                }
                line_len += word_len;
                word_len = 0;
                word = word_buf[0..0];
                word_spacing = 0;
            }

            if (line_spacing + word_spacing >= col_width or try utf8.isLineSeperator(code_point)) {

                // compensation padding
                for (0 .. col_width-line_spacing) |i| {
                    lines[line_index][line_len + i] = ' ';
                }
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////
                // std.debug.print("comp:{any} len:{any} space:{any} point:{any}\n", .{col_width-line_spacing, line_len, line_spacing, code_point});

                // add additional empty line in case of line break
                if (try utf8.isLineSeperator(code_point)) {
                    line_index += 1;
                    if (line_index >= lines_buf.len - 1) {
                        return error.LinesBufferFull;
                    }
                    lines = lines_buf[0..line_index + 1];
                    lines[line_index][0] = ' ';
                }

                // add new line
                line_len = 0;
                line_spacing = 0;
                line_index += 1;
                if (line_index >= lines_buf.len - 1) {
                    return error.LinesBufferFull;
                }
                lines = lines_buf[0..line_index + 1];
            }
            for (word, 0..) |code_unit_loc, i| {
                lines[line_index][line_len + i] = code_unit_loc;
            }
            line_len += word_len;
            // the suffixing word separator is appended to a line even if it is exceeding the column width
            // todo: prevent exceedance of line buffer
            if (! try utf8.isLineSeperator(code_point)) {
                for (code_point, 0..) |code_unit_loc, i| {
                    lines[line_index][line_len + i] = code_unit_loc ;
                }
                line_len += code_point_len;
                line_spacing += word_spacing + code_point_spacing;
            }
            word = word_buf[0..0];
            word_spacing = 0;
        // ### words ###
        } else {
            if (word_len + code_point_len >= line_buf_len) {
                return error.WordBufferExhausted;
            }
            word = word_buf[0..word_len + code_point_len];
            for (code_point, 0..) |code_unit_loc, i| {
                word[word_len + i] = code_unit_loc;
            }
            word_spacing += code_point_spacing;
        }
        code_unit_index += code_point_len;

    }
    // append last word
    for (word, 0..) |code_unit_loc, i| {
        lines[line_index][line_len + i] = code_unit_loc;
    }
    line_len += word.len;
    return lines;
}

fn generateWindowRows(
    lines: [][line_buf_len]u8,
    col_count: u64,
    col_gap: u64,
    lines_per_col: u64,
    selis_gap: u64
    ) ![][]u8 {
    var rows_slices: [1024]([]u8) = undefined;
    for (rows_slices, 0..) |_, i| {
        rows_slices[i] = window_rows_buf[i][0..0];
    }
    var window_rows: [][]u8 = rows_slices[0..0];
    var row_offset: u64 = 0;
    for (lines, 0..) |line, line_indx| {
        // std.debug.print("{any}\n", .{line});  /////////////////////////////

        var code_unit_index: u64 = 0;
        while (line[code_unit_index] != 0 and code_unit_index < line_buf_len) {
            code_unit_index += 1;
        }
        const line_len = code_unit_index;
        var window_row_index = row_offset + (line_indx / (lines_per_col*col_count)) * lines_per_col + line_indx % lines_per_col;
        const col_of_line = (line_indx/lines_per_col) % col_count;
        const lines_per_selis = lines_per_col * col_count;
        const line_of_selis = line_indx % lines_per_selis;
        if (line_of_selis == 0) {
            for(0..selis_gap) |_| {
                if (window_row_index + 1 > window_rows.len) {
                    window_rows = rows_slices[0..window_row_index+1];
                }
                const pos = window_rows[window_row_index].len;
                window_rows[window_row_index] = window_rows_buf[window_row_index][0 .. pos+1];
                window_rows[window_row_index][0] = ' ';
                row_offset += 1;
                window_row_index += 1;
            }
        }
        if (window_row_index + 1 > window_rows.len) {
            window_rows = rows_slices[0..window_row_index+1];
        }
        
        var pos = window_rows[window_row_index].len;
        if (col_of_line != 0) {
            window_rows[window_row_index] = window_rows_buf[window_row_index][0 .. pos+col_gap];
            for (pos .. pos+col_gap) |i| {
                window_rows[window_row_index][i] = ' ';
            }
            pos += col_gap;
        } 
        window_rows[window_row_index] = window_rows_buf[window_row_index][0 .. pos+line_len];
        for (0 .. line_len) |i| {
            // std.debug.print("{s}", .{line[i]});
            window_rows[window_row_index][pos + i] = line[i];
        }
        ///////////////////////////////////////////
        // std.debug.print("{s}({any}/{any})\n", .{window_rows[window_row_index], pos, window_rows[window_row_index].len});
    }
    return window_rows;
}

fn elicitWindowSize() !std.posix.winsize {
    const stdout = std.io.getStdOut();

    var winsize: std.posix.winsize = undefined;
    const result = std.posix.system.ioctl(
        stdout.handle,
        std.posix.T.IOCGWINSZ,
        @intFromPtr(&winsize)
    );
    switch (std.posix.errno(result)) {
        .SUCCESS => {},
        else => return error.IoctlError,
    }
    return winsize;
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
