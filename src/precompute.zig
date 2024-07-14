const std = @import("std");
const utils = @import("utils.zig");

const board_types = @import("board.zig");
const Position = board_types.Position;

const piece = @import("piece.zig");
const Color = piece.Color;

const bitset = @import("bitset.zig");
const BoardBitSet = bitset.BoardBitSet;
const Dir = bitset.Dir;
const Line = bitset.Line;
const NUM_DIRS = bitset.NUM_DIRS;
const NUM_LINES = bitset.NUM_LINES;

fn computeNumCellsToEdge() [64][8]u8 {
    const all_positon = Position.all_positions();
    var dist_to_edge: [64][8]u8 = undefined;
    for (all_positon) |pos| {
        const num_north = 7 - pos.rank;
        const num_south = pos.rank;
        const num_west = pos.file;
        const num_east = 7 - pos.file;

        dist_to_edge[pos.toIndex()] = .{
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

pub const Lines = [64][NUM_LINES]BoardBitSet;

pub fn computeLines() Lines {
    @setEvalBranchQuota(64 * NUM_LINES * 100 + 1);
    var moves: [64][NUM_LINES]BoardBitSet = undefined;

    inline for (0..64) |idx| {
        const start_bs = BoardBitSet.initWithIndex(idx);
        inline for (utils.enum_fields(Line)) |f| {
            const line_idx = f.value;
            const line: Line = @enumFromInt(line_idx);

            moves[idx][line_idx] = line.compute_line(start_bs);
        }
    }
    return moves;
}

pub const LINES = computeLines();

pub const Rays = [64][NUM_DIRS]BoardBitSet;

pub fn computeRays() Rays {
    @setEvalBranchQuota(64 * NUM_DIRS * 100 + 1);
    var moves: [64][NUM_DIRS]BoardBitSet = undefined;

    inline for (0..64) |idx| {
        const start_bs = BoardBitSet.initWithIndex(idx);
        inline for (utils.enum_fields(Dir)) |f| {
            const dir_idx = f.value;
            const dir: Dir = @enumFromInt(dir_idx);

            moves[idx][dir_idx] = dir.compute_ray(start_bs);
        }
    }
    return moves;
}

pub const RAYS = computeRays();

/// Helper info for checking castling
pub const SideCastlingInfo = struct {
    rook_start: Position,
    king_end: Position,
    rook_end: Position,

    sqaures_moving_through: BoardBitSet,

    pub fn init(
        king_end_str: []const u8,
        rook_start_str: []const u8,
        rook_end_str: []const u8,
        extra_check_str: []const u8,
    ) SideCastlingInfo {
        const king_end = Position.fromStr(king_end_str);
        const rook_end = Position.fromStr(rook_end_str);
        const extra_check = Position.fromStr(extra_check_str);

        var sqaures_moving_through = BoardBitSet.initWithPos(king_end);
        sqaures_moving_through.setPos(rook_end);
        sqaures_moving_through.setPos(extra_check);

        const rook_start = Position.fromStr(rook_start_str);

        return SideCastlingInfo{
            .king_end = king_end,
            .rook_start = rook_start,
            .rook_end = rook_end,
            .sqaures_moving_through = sqaures_moving_through,
        };
    }
};

pub const CastlingInfo = struct {
    queen_side: SideCastlingInfo,
    king_side: SideCastlingInfo,

    king_start: Position,

    pub fn from_king_end(self: CastlingInfo, king_end: Position) ?SideCastlingInfo {
        if (self.queen_side.king_end.eql(king_end)) {
            return self.queen_side;
        }

        if (self.king_side.king_end.eql(king_end)) {
            return self.king_side;
        }

        return null;
    }
};

fn compute_castling_info() [2]CastlingInfo {
    const white_king_castle = SideCastlingInfo.init("g1", "h1", "f1", "e1");
    const black_king_castle = SideCastlingInfo.init("g8", "h8", "f8", "e8");

    const white_queen_castle = SideCastlingInfo.init("c1", "a1", "d1", "e1");
    const black_queen_castle = SideCastlingInfo.init("c8", "a8", "d8", "e8");

    var castle_info: [2]CastlingInfo = undefined;

    castle_info[@intFromEnum(Color.White)] = CastlingInfo{
        .queen_side = white_queen_castle,
        .king_side = white_king_castle,
        .king_start = Position.fromStr("e1"),
    };
    castle_info[@intFromEnum(Color.Black)] = CastlingInfo{
        .queen_side = black_queen_castle,
        .king_side = black_king_castle,
        .king_start = Position.fromStr("e8"),
    };

    return castle_info;
}

pub const CASTLING_INFO = compute_castling_info();

pub const Score = i64;

pub const PIECE_SCORES = std.EnumArray(piece.Kind, Score).init(.{
    .King = 0,
    .Queen = 1000,
    .Bishop = 350,
    .Knight = 350,
    .Rook = 525,
    .Pawn = 100,
});
