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
    const white_eval = getMaterialScore(board, Color.White);
    const black_eval = getMaterialScore(board, Color.Black);
    const score = white_eval - black_eval;

    const perspective: i64 = if (board.active_color == Color.White) 1 else -1;

    return score * perspective;
}

fn getMaterialScore(board: *const Board, color: Color) Score {
    var score: Score = 0;
    inline for (utils.enumFields(Kind)) |f| {
        const kind_idx = f.value;
        const kind: Kind = @enumFromInt(kind_idx);

        const p: Piece = .{ .kind = kind, .color = color };
        const pieces = board.getPieceSet(p);

        if (kind != Kind.King) {
            const piece_count = pieces.count();
            score += @as(Score, @intCast(piece_count)) * Precompute.PIECE_SCORES.get(kind);
        }

        score += Precompute.PieceSquareScore.scorePieces(p, .Opening, pieces);
    }

    return score;
}
