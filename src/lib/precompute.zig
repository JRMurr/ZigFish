const std = @import("std");
const ZigFish = @import("root.zig");
const utils = ZigFish.Utils;

const Position = ZigFish.Position;

const Piece = ZigFish.Piece;
const Color = Piece.Color;
const Kind = Piece.Kind;
const NUM_KINDS = utils.enumLen(Kind);
const NUM_COLOR = utils.enumLen(Color);

const bitset = ZigFish.BitSet;
const BoardBitSet = bitset.BoardBitSet;
const Dir = bitset.Dir;
const Line = bitset.Line;
const NUM_DIRS = bitset.NUM_DIRS;
const NUM_LINES = bitset.NUM_LINES;

const GamePhase = ZigFish.GamePhase;

const Score = ZigFish.Score;

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
        inline for (utils.enumFields(Line)) |f| {
            const line_idx = f.value;
            const line: Line = @enumFromInt(line_idx);

            moves[idx][line_idx] = line.computeLine(idx);
        }
    }
    return moves;
}

pub const LINES = computeLines();

/// indexed by file num
pub const NeighborFiles = [8]BoardBitSet;
fn computeNeighorFiles() NeighborFiles {
    var neighbors: NeighborFiles = undefined;
    inline for (0..8) |idx| {
        const file_bs = BoardBitSet.initFile(idx);
        neighbors[idx] = file_bs.pawnAttacks(Color.White, null);
    }
    return neighbors;
}
pub const NEIGHBOR_FILES = computeNeighorFiles();

pub const Rays = [64][NUM_DIRS]BoardBitSet;

pub fn computeRays() Rays {
    @setEvalBranchQuota(64 * NUM_DIRS * 100 + 1);
    var moves: [64][NUM_DIRS]BoardBitSet = undefined;

    inline for (0..64) |idx| {
        inline for (utils.enumFields(Dir)) |f| {
            const dir_idx = f.value;
            const dir: Dir = @enumFromInt(dir_idx);

            moves[idx][dir_idx] = dir.computeRay(idx);
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

pub const PIECE_SCORES = std.EnumArray(Kind, Score).init(.{
    .King = 200000,
    .Queen = 900,
    .Bishop = 330,
    .Knight = 320,
    .Rook = 500,
    .Pawn = 100,
});

pub const PieceSquareScore = struct {
    const PieceSquare = [64]Score;

    fn flipPieceSqaure(x: PieceSquare) PieceSquare {
        var res: PieceSquare = undefined;

        for (0..64) |idx| {
            const start_pos = Position.fromIndex(idx);
            const flipped = start_pos.flipRank();
            res[flipped.toIndex()] = x[start_pos.toIndex()];
        }

        return res;
    }

    fn getPieceSquare(p: Piece, phase: GamePhase) PieceSquare {
        const kind = p.kind;
        const is_white = p.color == Color.White;

        return switch (kind) {
            .Knight => KNIGHT_SCORE,
            .Queen => QUEEN_SCORE,
            .Pawn => if (is_white) WHITE_PAWN_SCORE else BLACK_PAWN_SCORE,
            .Bishop => if (is_white) WHITE_BISHOP_SCORE else BLACK_BISHOP_SCORE,
            .Rook => if (is_white) WHITE_ROOK_SCORE else BLACK_ROOK_SCORE,
            .King => switch (phase) {
                .Opening => KING_OPENING_SCORE,
                .Middle => if (is_white) WHITE_KING_MID_SCORE else BLACK_KING_MID_SCORE,
                .End => if (is_white) WHITE_KING_END_SCORE else BLACK_KING_END_SCORE,
            },
        };
    }

    pub fn scorePieces(p: Piece, phase: GamePhase, board: BoardBitSet) Score {
        var score: Score = 0;

        const piece_sqaure = getPieceSquare(p, phase);

        var board_iter = board.iterator();
        while (board_iter.next()) |pos| {
            score += piece_sqaure[pos.toIndex()];
        }

        return score;
    }

    // https://www.chessprogramming.org/Simplified_Evaluation_Function#Piece-Square_Tables
    // Note the arrays for the following boards have the 0 index as the a8, so they are from "blacks"
    // perspective if using bitboard indexs
    // some are syemtrical so name won't matter

    // zig fmt: off
    const BLACK_PAWN_SCORE = PieceSquare{ 
        0,  0,  0,  0,  0,  0,  0,  0,
        50, 50, 50, 50, 50, 50, 50, 50,
        10, 10, 20, 30, 30, 20, 10, 10,
        5,  5, 10, 25, 25, 10,  5,  5,
        0,  0,  0, 20, 20,  0,  0,  0,
        5, -5,-10,  0,  0,-10, -5,  5,
        5, 10, 10,-20,-20, 10, 10,  5,
        0,  0,  0,  0,  0,  0,  0,  0
    };
    // zig fmt: on
    const WHITE_PAWN_SCORE = flipPieceSqaure(BLACK_PAWN_SCORE);

    // zig fmt: off
    const KNIGHT_SCORE = PieceSquare{ 
        -50,-40,-30,-30,-30,-30,-40,-50,
        -40,-20,  0,  0,  0,  0,-20,-40,
        -30,  0, 10, 15, 15, 10,  0,-30,
        -30,  5, 15, 20, 20, 15,  5,-30,
        -30,  0, 15, 20, 20, 15,  0,-30,
        -30,  5, 10, 15, 15, 10,  5,-30,
        -40,-20,  0,  5,  5,  0,-20,-40,
        -50,-40,-30,-30,-30,-30,-40,-50,
    };
    // zig fmt: on

    // zig fmt: off
    const BLACK_BISHOP_SCORE = PieceSquare{ 
        -20,-10,-10,-10,-10,-10,-10,-20,
        -10,  0,  0,  0,  0,  0,  0,-10,
        -10,  0,  5, 10, 10,  5,  0,-10,
        -10,  5,  5, 10, 10,  5,  5,-10,
        -10,  0, 10, 10, 10, 10,  0,-10,
        -10, 10, 10, 10, 10, 10, 10,-10,
        -10,  5,  0,  0,  0,  0,  5,-10,
        -20,-10,-10,-10,-10,-10,-10,-20,
    };
    // zig fmt: on
    const WHITE_BISHOP_SCORE = flipPieceSqaure(BLACK_BISHOP_SCORE);

    // zig fmt: off
    const BLACK_ROOK_SCORE = PieceSquare{ 
         0,  0,  0,  0,  0,  0,  0,  0,
         5, 10, 10, 10, 10, 10, 10,  5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
         0,  0,  0,  5,  5,  0,  0,  0,
    };
    // zig fmt: on
    const WHITE_ROOK_SCORE = flipPieceSqaure(BLACK_ROOK_SCORE);

    // zig fmt: off
    const QUEEN_SCORE = PieceSquare{ 
        -20,-10,-10, -5, -5,-10,-10, -20,
        -10,  0,  0,  0,  0,  0,  0, -10,
        -10,  0,  5,  5,  5,  5,  0, -10,
        -5 ,  0,  5,  5,  5,  5,  0,  -5,
         0 ,  0,  5,  5,  5,  5,  0,  -5,
        -10,  5,  5,  5,  5,  5,  0, -10,
        -10,  0,  5,  0,  0,  0,  0, -10,
        -20,-10,-10, -5, -5,-10,-10, -20
    };
    // zig fmt: on

    const KING_OPENING_SCORE: PieceSquare = [_]Score{0} ** 64;

    // zig fmt: off
    const BLACK_KING_MID_SCORE = PieceSquare{ 
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -20,-30,-30,-40,-40,-30,-30,-20,
        -10,-20,-20,-20,-20,-20,-20,-10,
         20, 20,  0,  0,  0,  0, 20, 20,
         20, 30, 10,  0,  0, 10, 30, 20
    };
    // zig fmt: on
    const WHITE_KING_MID_SCORE = flipPieceSqaure(BLACK_KING_MID_SCORE);

    // zig fmt: off
    const BLACK_KING_END_SCORE = PieceSquare{ 
        -50,-40,-30,-20,-20,-30,-40,-50,
        -30,-20,-10,  0,  0,-10,-20,-30,
        -30,-10, 20, 30, 30, 20,-10,-30,
        -30,-10, 30, 40, 40, 30,-10,-30,
        -30,-10, 30, 40, 40, 30,-10,-30,
        -30,-10, 20, 30, 30, 20,-10,-30,
        -30,-30,  0,  0,  0,  0,-30,-30,
        -50,-30,-30,-30,-30,-30,-30,-50
    };
    // zig fmt: on
    const WHITE_KING_END_SCORE = flipPieceSqaure(BLACK_KING_END_SCORE);
};
