const std = @import("std");

pub inline fn enum_len(comptime T: type) comptime_int {
    return @typeInfo(T).Enum.fields.len;
}

pub inline fn enum_fields(comptime T: type) []const std.builtin.Type.EnumField {
    return @typeInfo(T).Enum.fields;
}

pub inline fn unionFields(comptime T: type) []const std.builtin.Type.UnionField {
    return @typeInfo(T).Union.fields;
}

pub fn initStr(char: u8, comptime len: usize) [len]u8 {
    var str: [len]u8 = undefined;
    for (0..len) |i| {
        str[i] = char;
    }

    return str;
}
