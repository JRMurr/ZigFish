const std = @import("std");
const testing = std.testing;

pub usingnamespace @import("board.zig");
pub usingnamespace @import("position.zig");

const game_types = @import("game.zig");
pub const GameManager = game_types.GameManager;

pub const MoveGen = @import("move_gen.zig");
pub const MoveList = @import("move_list.zig");
pub const Piece = @import("piece.zig");
pub const Kind = Piece.Kind;
pub const Color = Piece.Color;

const move_types = @import("move.zig");
pub const Move = move_types.Move;
pub const SimpleMove = move_types.SimpleMove;
pub const MoveFlags = move_types.MoveFlags;
pub const MoveType = move_types.MoveType;

pub const BitSet = @import("bitset.zig");
pub const BoardBitSet = BitSet.BoardBitSet;
pub const Dir = BitSet.Dir;

pub const Fen = @import("fen.zig");
// pub const Piece = @import("piece.zig");
// pub const Kind = @import("piece.zig");

pub const Precompute = @import("precompute.zig");

pub const Search = @import("search.zig");
pub const GamePhase = Search.GamePhase;
pub const Utils = @import("utils.zig");
pub const Zhasing = @import("zhash.zig");

pub const Eval = @import("eval.zig");
pub const Score = Eval.Score;

test {
    testing.refAllDecls(@This());
}
