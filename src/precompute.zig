const std = @import("std");
const utils = @import("utils.zig");

const board_types = @import("board.zig");
const Position = board_types.Position;

const bitset = @import("bitset.zig");
const BoardBitSet = bitset.BoardBitSet;
const Dir = bitset.Dir;
const NUM_DIRS = bitset.NUM_DIRS;

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

pub const Rays = [64][NUM_DIRS]BoardBitSet;

// This is too much for comptime :(
pub fn computeRays() [64][NUM_DIRS]BoardBitSet {
    var moves: [64][NUM_DIRS]BoardBitSet = undefined;

    for (0..64) |idx| {
        const start_bs = BoardBitSet.initWithIndex(idx);
        inline for (utils.enum_fields(Dir)) |f| {
            const dir_idx = f.value;
            const dir: Dir = @enumFromInt(dir_idx);

            moves[idx][dir_idx] = dir.compute_ray(start_bs);
        }
    }
    return moves;
}

// const RAYS = computeRays();

test "test rays" {
    const RAYS = computeRays();
    const pos = Position{ .rank = 7, .file = 7 };

    const idx = pos.to_index();

    const ray_west = RAYS[idx][@intFromEnum(Dir.West)];

    std.debug.print("ray {}\n", .{ray_west});

    try std.testing.expect(ray_west.count() == 7);

    const ray_north_east = RAYS[idx][@intFromEnum(Dir.NorthEast)];

    std.debug.print("ray {}\n", .{ray_north_east});

    try std.testing.expect(ray_west.count() == 0);
}
