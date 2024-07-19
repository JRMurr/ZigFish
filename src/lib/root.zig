const std = @import("std");
const testing = std.testing;

const board_types = @import("board.zig");
pub const Position = board_types.Position;
pub const Board = board_types.Board;
pub const BoardMeta = board_types.BoardMeta;

const game_types = @import("game.zig");
pub const GameManager = game_types.GameManager;

pub usingnamespace @import("move_gen.zig");

pub const BitSet = @import("bitset.zig");
pub const Fen = @import("fen.zig");
pub const Move = @import("move.zig");
pub const Piece = @import("piece.zig");
pub const Precompute = @import("precompute.zig");
pub const Search = @import("search.zig");
pub const Utils = @import("utils.zig");
pub const Zhasing = @import("zhash.zig");

test {
    testing.refAllDecls(@This());
}
