const std = @import("std");

pub const Commands = @import("commands.zig");

test {
    std.testing.refAllDecls(@This());
}
