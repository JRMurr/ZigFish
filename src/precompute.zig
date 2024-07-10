const std = @import("std");

const board_types = @import("board.zig");
const Position = board_types.Position;

const bitset = @import("bitset.zig");
const BoardBitSet = bitset.BoardBitSet;

fn computeNumCellsToEdge() [64][8]u8 {
    const all_positon = Position.all_positions();
    var dist_to_edge: [64][8]u8 = undefined;
    for (all_positon) |pos| {
        const num_north = 7 - pos.rank;
        const num_south = pos.rank;
        const num_west = pos.file;
        const num_east = 7 - pos.file;

        dist_to_edge[pos.to_index()] = .{
            num_north,
            num_south,
            num_west,
            num_east,

            @min(num_north, num_west),
            @min(num_north, num_east),
            @min(num_south, num_west),
            @min(num_south, num_east),
        };
    }

    return dist_to_edge;
}

pub const NUM_SQUARES_TO_EDGE = computeNumCellsToEdge();

fn computeKnightMoves() [64]BoardBitSet {
    var moves: [64]BoardBitSet = undefined;

    for (0..64) |idx| {
        const start_bs = BoardBitSet.initWithIndex(idx);
        moves[idx] = start_bs.knightMoves();
    }
    return moves;
}

pub const KNIGHT_MOVES = computeKnightMoves();

fn computeKingMoves() [64]BoardBitSet {
    var moves: [64]BoardBitSet = undefined;

    for (0..64) |idx| {
        const start_bs = BoardBitSet.initWithIndex(idx);
        moves[idx] = start_bs.kingMoves();
    }
    return moves;
}

pub const KING_MOVES = computeKingMoves();
