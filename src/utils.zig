const std = @import("std");

pub inline fn enum_len(comptime T: type) comptime_int {
    return @typeInfo(T).Enum.fields.len;
}

pub inline fn enum_fields(comptime T: type) []const std.builtin.Type.EnumField {
    return @typeInfo(T).Enum.fields;
}
