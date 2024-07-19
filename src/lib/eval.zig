const builtin = @import("builtin");
const utils = ZigFish.utils;

const ZigFish = @import("root");
const Board = ZigFish.Board;
const Position = ZigFish.Position;

const Piece = @import("piece.zig");
const Color = Piece.Color;
const Kind = Piece.Kind;

const precompute = @import("precompute.zig");
const Score = precompute.Score;

pub fn evaluate(board: Board) Score {
    const white_eval = getMaterialScore(board, Color.White);
    const black_eval = getMaterialScore(board, Color.Black);
    const score = white_eval - black_eval;

    const perspective: i64 = if (board.active_color == Color.White) 1 else -1;

    return score * perspective;
}

fn getMaterialScore(board: Board, color: Color) Score {
    var score: Score = 0;
    inline for (utils.enum_fields(Kind)) |f| {
        const kind_idx = f.value;
        const kind: Kind = @enumFromInt(kind_idx);
        if (kind == Kind.King) {
            continue;
        }
        const p: Piece = .{ .kind = kind, .color = color };
        const pieces = board.getPieceSet(p);
        const piece_count = pieces.count();

        score += @as(Score, @intCast(piece_count)) * precompute.PIECE_SCORES.get(kind);
        score += precompute.PieceSquareScore.scorePieces(p, .Opening, pieces);
    }

    return score;
}
