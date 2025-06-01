// nyx server
const std = @import("std");
const PosixSocketFacade = @import("posixsocketfacade.zig").PosixSocketFacade;

const max_content_len = 65536;

const col_width = 50;

var lines_buf = [1][col_width]u8{[_]u8{' '} ** col_width} ** 1024;
var window_rows_buf: [1024][]u8 = undefined;

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
        const truncated_page_content = try truncate(alloc, page.value_ptr.*, 50 );
        defer alloc.free(truncated_page_content);
        std.debug.print("{s}: {s}", .{page.key_ptr.*, truncated_page_content});
    }

    var content: []const u8 = page_map.get("/a.txt") orelse "<no entry>";
    const lines = try parseLines(content);

    const window_rows = try generateWindowRows(
        alloc,
        lines,
        2,
        3,
        12,
        3
    );
    defer {
        for (window_rows) |row| {
            alloc.free(row);
        }
    }
    for (window_rows) |row| {
        std.debug.print("{s}\n", .{row});
    }

    const win_size = try elicitWindowSize();

    std.debug.print("{any} {any}", .{win_size.col, win_size.row});


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

fn parseLines(content: []const u8) ![][col_width]u8 {
    var lines: [][col_width]u8 = lines_buf[0..1];
    var line_index: u64 = 0;
    var code_unit_index: u64 = 0;
    var is_newline = false;

    for (content) |code_unit_para| {
        var code_unit = code_unit_para;
        if (line_index >= lines_buf.len - 1) {
            return error.LinesBufferFull;
        }
        
        if (code_unit == '\n') {
            code_unit = ' ';
            is_newline = true;
        }
        lines[line_index][code_unit_index] = code_unit;
        code_unit_index += 1;


        if (code_unit_index == col_width or is_newline) {
            is_newline = false;
            
            line_index += 1;
            lines = lines_buf[0..line_index + 1];

            if (code_unit != ' ') {
                const end_index = code_unit_index;
                while(code_unit != ' ') {
                    code_unit_index -= 1;
                    code_unit = lines[line_index - 1][code_unit_index];
                }
                const next_start_index = end_index - code_unit_index - 1;
                for (code_unit_index + 1..end_index, 0..next_start_index) |i, j| {
                    lines[line_index][j] = lines[line_index - 1][i];
                    lines[line_index - 1][i] = ' ';
                }
                code_unit_index = next_start_index;
            } else {
                code_unit_index = 0;
            }
        }
    }
    return lines;
}

fn generateWindowRows(
    alloc: std.mem.Allocator,
    lines: [][col_width]u8,
    col_count: u64,
    col_gap: u64,
    lines_per_col: u64,
    selis_gap: u64
    ) ![][]u8 {
    var window_rows: [][]u8 = window_rows_buf[0..0];
    const padding_buf = " " ** 100; // todo: maybe too short
    var row_offset: u64 = 0;
    // var compensation: []const u8 = padding_buf[0..0];
    for (lines, 0..) |line, line_indx| {
        const padding = padding_buf[0..col_gap];
        var line_spacing: u64 = 0;
        var code_unit_index: u64 = 0;
        while (code_unit_index < line.len) {
            const code_unit = line[code_unit_index];
            const code_point_length = try utf8CodePointLength(code_unit);
            const code_point = line[code_unit_index..code_unit_index + code_point_length];
            // std.debug.print("ln idx: {any}:{any} [{any}..{any}]\n", .{code_point, code_point.len, code_unit_index, code_point_length});
            line_spacing += spacing(code_point);
            code_unit_index += code_point_length;
        }
        const compensation_len = col_width - line_spacing;
        const compensation = padding_buf[0..compensation_len];
        var window_row_index = row_offset + (line_indx / (lines_per_col*col_count)) * lines_per_col + line_indx % lines_per_col;
        const col_of_line = (line_indx/lines_per_col) % col_count;
        const lines_per_selis = lines_per_col * col_count;
        const line_of_selis = line_indx % lines_per_selis;
        if (line_of_selis == 0) {
            for(0..selis_gap) |_| {
                if (window_row_index + 1 > window_rows.len) {
                    window_rows = window_rows_buf[0..window_row_index+1];
                }
                window_rows[window_row_index] = try std.mem.concat(alloc, u8, &.{""});
                row_offset += 1;
                window_row_index += 1;
            }
        }
        // std.debug.print("{any} " ** 3 ++ "\n", .{line_indx, window_row_index, col_of_line});
        if (window_row_index + 1 > window_rows.len) {
            window_rows = window_rows_buf[0..window_row_index+1];
        }
        if (col_of_line == 0) {
            const window_row_strings = &.{&line, compensation};
            window_rows[window_row_index] = try std.mem.concat(alloc, u8, window_row_strings);
        } else {
            const window_row_strings = &.{window_rows[window_row_index], compensation, padding, &line};
            window_rows[window_row_index] = try std.mem.concat(alloc, u8, window_row_strings);
        }
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

fn spacing(code_point: []const u8) u64 {

    // There are a number of characters that do not occupy the space of 1 column in,
    // the terminal, potentially among others:
    // - Zero Width
    //   - Zero Width Space (ZWSP) (U+200B)
    //   - Zero Width Non-Joiner (ZWNJ) (U+200C)
    //   - Zero Width Joiner (ZWJ) (U+200D)
    //     This code point might even combine multiples code points to 
    //     a singe glyph: 👨‍👨‍👧‍👧 = 👨\u200d👨\u200d👧\u200d👧 (the column counter
    //     of VS Code jumps by 7)
    //   - Word Joiner (WJ) (U+2060⁠)
    //   - Zero Width No-Break Space (BOM, ZWNBSP) (U+FEFF)
    // - Combining Marks
    //   - Combining Diacritical Marks https://en.wikipedia.org/wiki/Combining_Diacritical_Marks
    //   - Combining Diacritical Marks Supplement https://en.wikipedia.org/wiki/Combining_Diacritical_Marks_Supplement
    //   - Combining Diacritical Marks for Symbols https://en.wikipedia.org/wiki/Combining_Diacritical_Marks_for_Symbols
    //   - Combining Half Marks https://en.wikipedia.org/wiki/Combining_Diacritical_Marks_Extended
    // - Control Characters https://en.wikipedia.org/wiki/Unicode_control_characters
    //   - Most Control Characters of Unicode Block “Basic Latin” 0000–001F and 007F
    //     - (Except the Format Effectors: BS, TAB, LF, VT, FF, and CR)
    //   - Unicode Block “Latin-1 Supplement” 0080–009F
    //   - Language Tags https://en.wikipedia.org/wiki/Tags_(Unicode_block)
    //   - Interlinear Annotation https://en.wikipedia.org/wiki/Interlinear_gloss
    //   - Ruby Characters https://en.wikipedia.org/wiki/Ruby_character
    //   - Bidirectional text control https://en.wikipedia.org/wiki/Bidirectional_text
    //   - Variation Selectors https://en.wikipedia.org/wiki/Variation_selector_(Unicode)
    // - Some CJK Chracacters might take two columns in the terminal
    //
    // https://www.perlmonks.org/?node_id=713297 (The “real length" of UTF8 strings)
    // https://stackoverflow.com/questions/79241895/c-strlen-returns-the-wrong-string-length-character-count-when-using-umlauts
    // https://www.compart.com/en/unicode/block/U+0080
    //
    //
    // Combining Diacritical Marks U+0300–U+036F
    // 11001100(0xCC) 10000000(0x80) (U+0300 utf-8)
    // 11010000(0xCD) 10101111(0xAF) (U+036F utf-8)

    // First CP     Last CP     Byte 1      Byte 2      Byte 3      Byte 4
    // U+0000       U+007F      0yyyzzzz
    // U+0080       U+07FF      110xxxyy    10yyzzzz
    // U+0800       U+FFFF      1110wwww    10xxxxyy    10yyzzzz
    // U+010000     U+10FFFF    11110uvv    10vvwwww    10xxxxyy    10yyzzzz

    switch (code_point.len) {
        1 => {
            // 0yyyzzzz
            return 1;
        },
        2 => {
            // 110xxxyy 10yyzzzz
            const first_combining_diacritical_mark_unicode_point = 0x0300;
            const last_combining_diacritical_mark_unicode_point =  0x036F;
            const z: u4 = @truncate(code_point[1]);
            const y_lower: u2 = @truncate(code_point[1] >> 4);
            const y_upper: u2 = @truncate(code_point[0]);
            const y: u4 = (@as(u4, y_upper) << 2) + y_lower;
            const x: u3 = @truncate(code_point[0] >> 2);
            const unicode_point: u32 = (@as(u12, x) << 8) + (@as(u8, y) << 4) + z;

            const is_combining_diacritical_mark = 
                unicode_point >= first_combining_diacritical_mark_unicode_point and
                unicode_point <= last_combining_diacritical_mark_unicode_point;

            if (is_combining_diacritical_mark) {
                return 0;
            } else {
                return 1;
            }
        },
        3 => {
            // 1110wwww 10xxxxyy 10yyzzzz
            return 1;
        },
        4 => {
            // 11110uvv 10vvwwww 10xxxxyy 10yyzzzz
            return 1;
        },
        else => unreachable
    }
}

// returns the length of a utf-8 code point as count of its code units
fn utf8CodePointLength(code_unit: u8) !u3 {
    // A utf-8 code point (CP) is composed of 1 to 4 code units (CU) (a utf-8 code unit is 1 byte).
    // The length of a code point is determined by the first bits of its first code unit:
    // first CU length CP   in bytes    in bits
    // 0xxxxxxx 1           1           8
    // 110xxxxx 2           2           16
    // 1110xxxx 3           3           24
    // 11110xxx 4           4           32
    // If a code point consists of more than one code unit every code unit after the first
    // one is called a continuation code unit (CCU); it starts with the bist 10.
    // 1. CU    1. CCU   2. CCU   3. CCU
    // 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
    // Every code unit that does not start with 0, 10, 110, 1110 or 11110 is invalid.
    const one_bit_mask =    0b1_0000000;
    const two_bit_mask =    0b11_000000;
    const three_bit_mask =  0b111_00000;
    const four_bit_mask =   0b1111_0000;
    const five_bit_mask =   0b11111_000;
    const single_code_unit_marker =         0b0_0000000;
    const continuation_code_unit_marker =   0b10_000000;
    const double_code_unit_marker =         0b110_00000;
    const triple_code_unit_marker =         0b1110_0000;
    const quadruple_code_unit_marker =      0b11110_000;
    if (code_unit & one_bit_mask == single_code_unit_marker) {
        return 1;
    }
    if (code_unit & three_bit_mask == double_code_unit_marker) {
        return 2;
    }
    if (code_unit & four_bit_mask == triple_code_unit_marker) {
        return 3;
    }
    if (code_unit & five_bit_mask == quadruple_code_unit_marker) {
        return 4;
    }
    if (code_unit & two_bit_mask == continuation_code_unit_marker) {
        return error.MissplacedUtf8ContinuationCodeUnit;
    }
    return error.InvalidUtf8CodeUnit;
}

test "utf-8 spacing" {
    const a = [1]u8{0x61};
    const combining_grave_accent  = [2]u8{0xCC, 0x80};
    try std.testing.expect(spacing(a[0..]) == 1);
    try std.testing.expect(spacing(combining_grave_accent[0..]) == 0);
}
