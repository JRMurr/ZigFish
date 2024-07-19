const std = @import("std");
const testing = std.testing;

pub usingnamespace @import("board.zig");

const game_types = @import("game.zig");
pub const GameManager = game_types.GameManager;

pub const MoveGen = @import("move_gen.zig");
pub const MoveList = MoveGen.MoveList;
pub usingnamespace @import("piece.zig");
pub usingnamespace @import("move.zig");

pub const BitSet = @import("bitset.zig");
pub const BoardBitSet = BitSet.BoardBitSet;

pub const Fen = @import("fen.zig");
// pub const Piece = @import("piece.zig");
// pub const Kind = @import("piece.zig");

pub const Precompute = @import("precompute.zig");
pub const Search = @import("search.zig");
pub const Utils = @import("utils.zig");
pub const Zhasing = @import("zhash.zig");

test {
    testing.refAllDecls(@This());
}
