const std = @import("std");
const testing = std.testing;

pub usingnamespace @import("board.zig");
pub usingnamespace @import("game.zig");

pub usingnamespace @import("move.zig");
pub usingnamespace @import("move_gen.zig");

pub const Piece = @import("piece.zig");
pub const Precompute = @import("precompute.zig");
pub const Search = @import("search.zig");
pub const Utils = @import("utils.zig");
pub const Zhasing = @import("zhash.zig");

test {
    testing.refAllDecls(@This());
}
