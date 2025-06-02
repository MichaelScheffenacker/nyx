const std = @import("std");

pub fn spacing(code_point: []const u8) !u64 {

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

    // const code_point_arr = code_point.ptr[0..code_point.len].*;
    const unicode_point: u21 =  switch (code_point.len) {
        1 => code_point[0],
        2 => try std.unicode.utf8Decode2(code_point[0..2].*),
        3 => try std.unicode.utf8Decode3(code_point[0..3].*),
        4 => try std.unicode.utf8Decode4(code_point[0..4].*),
        else => unreachable
    };
    const first_combining_diacritical_mark_unicode_point = 0x0300;
    const last_combining_diacritical_mark_unicode_point =  0x036F;
    const is_combining_diacritical_mark = 
        unicode_point >= first_combining_diacritical_mark_unicode_point and
        unicode_point <= last_combining_diacritical_mark_unicode_point;

    if (is_combining_diacritical_mark) {
        return 0;
    } else {
        return 1;
    }
}

// returns the length of a utf-8 code point as count of its code units
pub fn codePointLength(code_unit: u8) !u3 {
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
    try std.testing.expect(try spacing(a[0..]) == 1);
    try std.testing.expect(try spacing(combining_grave_accent[0..]) == 0);
}