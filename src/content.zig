const std = @import("std");
const utf8 = @import("utf8.zig");

const col_width = 50;

/// Since a window column of text can be composed of many code points and even more bytes, for a given
/// column width the number of required bytes cannot be estimated. 
/// todo: change fixed length line buffers to a over all buffer where parts can be partitioned off for a line
const line_buf_len = col_width * 5;
var lines_buf = [1][line_buf_len]u8{[_]u8{0} ** line_buf_len} ** 1024;
var lines_slices: [1024]([]u8) = undefined;
var window_rows_buf = [1][line_buf_len*2]u8{[_]u8{0} ** (line_buf_len*2)} ** 1024;

pub fn display (content: []const u8) !void {
    const lines = try parseLines(content);

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
}

fn parseLines(content: []const u8) ![][]u8 {
    for (lines_slices, 0..) |_, i| {
        lines_slices[i] = lines_buf[i][0..0];
    }
    var lines: [][]u8 = lines_slices[0..0];

    var line: []u8 = lines_buf[0][0..0];

    var code_unit_index: u64 = 0;
    var word_buf = [1]u8{0} ** line_buf_len;
    var word: []u8 = word_buf[0..0];

    const padding_buffer: [line_buf_len]u8 = [1]u8{' '} ** line_buf_len;
    while (code_unit_index < content.len) {

        const code_unit = content[code_unit_index];
        const code_point_len = try utf8.codePointLength(code_unit);
        const code_point: []u8 = @constCast(content[code_unit_index .. (code_unit_index + code_point_len)]);
        
        // ### lines and words ###
        if (try utf8.isWordSeparator(code_point)) {
            const line_spacing = try utf8.spacing(line);
            if (line_spacing + try utf8.spacing(word) >= col_width) {

                // append column compensation padding
                const padding = @constCast(padding_buffer[0 .. col_width-line_spacing]);
                line = try appendSlice(line, padding, line_buf_len);

                // new line
                lines = try appendLine(lines, line, lines_slices.len);
                line = lines_buf[lines.len][0..0];
            }
            
            // append word
            line = try appendSlice( line,  word, line_buf_len);

            // the suffixing word separator is appended to a line even if it is exceeding the column width
            line = try appendSlice( line,  code_point, line_buf_len);
            word = word_buf[0..0];
        } else if (try utf8.isLineSeperator(code_point)) {

            // append word
            line = try appendSlice( line, word, line_buf_len);
            word = word_buf[0..0];

            // append column compensation padding
            const line_spacing = try utf8.spacing(line);
            const padding = @constCast(padding_buffer[0 .. col_width-line_spacing]);
            line = try appendSlice(line, padding, line_buf_len);

            // new paragraph
            lines = try appendLine(lines, line, lines_slices.len);
            // todo: there might be an inconsitency with col_width/col_width-1 somewhere.
            const additional_empty_line = @constCast(padding_buffer[0 .. col_width]);
            lines = try appendLine(lines, additional_empty_line, lines_slices.len);
            line = lines_buf[lines.len][0..0];
        
        } else {  // ### words ###
            // add word  // todo: words can be longer than lines
            word = try appendSlice(word, code_point, word_buf.len);
        }
        code_unit_index += code_point_len;

    }
    // append last word // todo: is this even required?
    line = try appendSlice(line, word, line_buf_len);

    lines = try appendLine(lines, line, lines_slices.len);
    return lines;
}

fn appendLine(dest: [][]u8, src: []u8, max_len: u64) ![][]u8 {
    if (dest.len + 1 > max_len) {
        return error.MaxLenExceeded;
    }
    var new_slice = dest;
    new_slice.len += 1;
    new_slice[dest.len] = src;
    return new_slice;
}

fn appendSlice(dest: []u8, src: []u8, max_len: u64) ![]u8 {
    if (dest.len + src.len > max_len) {
        return error.MaxLenExceeded;
    }
    var new_slice = dest;
    new_slice.len += src.len;
    for (src, 0..) |code_unit, i| {
        new_slice[dest.len + i] = code_unit;
    }
    return new_slice;
}

fn generateWindowRows(
    lines: [][]u8,
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
        window_rows[window_row_index] = window_rows_buf[window_row_index][0 .. pos+line.len];
        for (0 .. line.len) |i| {
            window_rows[window_row_index][pos + i] = line[i];
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
