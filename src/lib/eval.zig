const builtin = @import("builtin");
const utils = ZigFish.Utils;

const ZigFish = @import("root.zig");
const Board = ZigFish.Board;
const Position = ZigFish.Position;

const Piece = @import("piece.zig");
const Color = Piece.Color;
const Kind = Piece.Kind;

const Precompute = ZigFish.Precompute;

pub const Score = i64;

// in centipawns
pub const MAX_SCORE = 500_000_000;
pub const MIN_SCORE = -1 * MAX_SCORE;

pub fn evaluate(board: *const Board) Score {
    const white_eval = evalForColor(board, Color.White);
    const black_eval = evalForColor(board, Color.Black);
    const score = white_eval - black_eval;

    const perspective: i64 = if (board.active_color == Color.White) 1 else -1;

    return score * perspective;
}

const EvalFn = fn (board: *const Board, color: Color) Score;

const evalFuncs = [_](EvalFn){
    getMaterialScore,
    // isolatedPawns,
};

fn evalForColor(board: *const Board, color: Color) Score {
    var score: Score = 0;
    inline for (evalFuncs) |evalFn| {
        score += evalFn(board, color);
    }

    return score;
}

// center isolated pawns should be more sad
// const ISOLATED_PAWN_FILE_SCORE = [8]Score{ -15, -20, -30, -30, -30, -30, -20, -15 };
const ISOLATED_PAWN_SCORE = -15;
fn isolatedPawns(board: *const Board, color: Color) Score {
    const p = Piece{ .kind = .Pawn, .color = color };
    const pawns = board.getPieceSet(p);

    var pawn_iter = pawns.iterator();

    var score: Score = 0;
    while (pawn_iter.next()) |pos| {
        if (pos.toRank() == color.get_enemy().pawnRank()) {
            continue; // could promote so no need to care
        }

        const file = pos.toFile();
        const neighbors = Precompute.NEIGHBOR_FILES[file];

        if (neighbors.intersectWith(pawns).isEmpty()) {
            const scale: Score = if (ZigFish.BitSet.EXTENDED_CENTER_BOARD.isPosSet(pos)) 3 else 1;

            score += (ISOLATED_PAWN_SCORE * scale);
        }
    }

    return score;
}

fn getMaterialScore(board: *const Board, color: Color) Score {
    var score: Score = 0;
    inline for (utils.enumFields(Kind)) |f| {
        const kind_idx = f.value;
        const kind: Kind = @enumFromInt(kind_idx);

        const p = Piece{ .kind = kind, .color = color };
        const pieces = board.getPieceSet(p);

        if (kind != Kind.King) {
            const piece_count = pieces.count();
            score += @as(Score, @intCast(piece_count)) * Precompute.PIECE_SCORES.get(kind);
        }

        score += Precompute.PieceSquareScore.scorePieces(p, .Opening, pieces);
    }

    return score;
}
