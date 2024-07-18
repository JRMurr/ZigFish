const std = @import("std");
const Piece = @import("piece.zig");
const Kind = Piece.Kind;
const Color = Piece.Color;

const board_types = @import("board.zig");
const Position = board_types.Position;

const MoveGen = @import("move_gen.zig");
pub const MoveList = MoveGen.MoveList;

pub const MoveType = enum {
    Capture,
    Promotion,
    EnPassant,
    Castling,
};

pub const MoveFlags = std.enums.EnumSet(MoveType);

const Move = @This();

const SAN_LEN = 8;

fn initStr(char: u8, comptime len: usize) [len]u8 {
    var str: [len]u8 = undefined;
    for (0..len) |i| {
        str[i] = char;
    }

    return str;
}

start: Position,
end: Position,
kind: Kind,
move_flags: MoveFlags,
captured_kind: ?Kind = null,
promotion_kind: ?Kind = null,

pub fn toSan(self: Move) [SAN_LEN]u8 {
    // https://www.chessprogramming.org/Algebraic_Chess_Notation#SAN
    // TODO: san can omit info depening on if the move is unambiguous.
    // for now duing "full"
    // TODO: castling

    const from_str = self.start.toStr();
    const to_str = self.end.toStr();

    const capture_str = if (self.move_flags.contains(MoveType.Capture)) "x" else "";

    const piece_symbol = self.kind.to_symbol();

    const promotion_symbol = if (self.promotion_kind) |k| k.to_symbol() else "";

    var str = comptime initStr(' ', SAN_LEN);
    _ = std.fmt.bufPrint(&str, "{s}{s}{s}{s}{s}", .{ piece_symbol, from_str, capture_str, to_str, promotion_symbol }) catch {
        std.debug.panic("Bad san format for {any}", .{self});
    };

    return str;
}

pub fn fromSan(pgn: []u8, valid_moves: MoveList) Move {
    // Handle castling
    const is_king_castle = std.mem.eql(u8, pgn, "O-O");
    const is_queen_castle = std.mem.eql(u8, pgn, "O-O-O");
    if (is_king_castle or is_queen_castle) {
        const end_file = if (is_king_castle) 7 else 2;
        for (valid_moves.items) |m| {
            if (!m.move_flags.eql(MoveFlags{ .Castling = true })) {
                continue;
            }
            const rankFile = m.start.toRankFile();
            if (rankFile.file != end_file) {
                continue;
            }

            return m;
        }
        std.debug.panic("could not find castle move for {s}", .{pgn});
    }

    var move_flags = MoveFlags.initEmpty();

    // Determine piece type and start position
    var idx = 0;
    var kind = Kind.Pawn;

    var end_square: Position = undefined;
    var promotion_kind: ?Kind = null;
    // var capture_kind: ?kind = null;

    if (std.ascii.isUpper(pgn[idx])) {
        kind = parsePieceType(pgn[idx]);
        idx += 1;
    }

    // Parse captures
    if (std.mem.indexOf(u8, pgn, "x")) |capture_idx| {
        move_flags |= MoveFlags{ .Capture = true };
        idx = capture_idx + 1;
    }

    // Parse destination square
    if (pgn.len - idx >= 2) {
        const square_str = pgn[(pgn.len - 2)..];
        end_square = Position.fromStr(square_str);
    } else {
        std.debug.panic("error parsing end_square: {s}", .{pgn});
    }

    // Parse promotion
    if (pgn.len > 2 and pgn[pgn.len - 3] == '=') {
        move_flags |= MoveFlags{ .Promotion = true };
        promotion_kind = parsePieceType(pgn[pgn.len - 1]);
    }

    var maybe_file: ?usize = null;
    var maybe_rank: ?usize = null;

    if (std.ascii.isAlphabetic(pgn[idx])) {
        maybe_file = @intCast(pgn[idx] - 'a');
        idx += 1;
    }

    if (std.ascii.isDigit(pgn[idx])) {
        maybe_rank = @intCast(pgn[idx] - '1');
        idx += 1;
    }

    for (valid_moves.items) |m| {
        if (m.kind != kind) {
            continue;
        }
        if (!m.end.eql(end_square)) {
            continue;
        }
        if (!m.move_flags.eql(move_flags)) {
            continue;
        }
        const rankFile = m.start.toRankFile();
        if (maybe_file) |file| {
            if (rankFile.file != file) {
                continue;
            }
        }
        if (maybe_rank) |rank| {
            if (rankFile.rank != rank) {
                continue;
            }
        }

        return m;
    }

    std.debug.panic("could not find move for {s}", .{pgn});
}

pub fn toStrSimple(self: Move) [5]u8 {
    const from_str = self.start.toStr();
    const to_str = self.end.toStr();
    const promotion_symbol = if (self.promotion_kind) |k| k.to_symbol() else "";

    var str = comptime initStr(' ', 5);
    _ = std.fmt.bufPrint(&str, "{s}{s}{s}", .{ from_str, to_str, promotion_symbol }) catch {
        std.debug.panic("Bad move format for {any}", .{self});
    };

    return str;
}

pub fn eql(self: Move, other: Move) bool {
    return std.meta.eql(self, other);
}

fn parsePieceType(ch: u8) Kind {
    return switch (ch) {
        'N' => Kind.Knight,
        'B' => Kind.Bishop,
        'R' => Kind.Rook,
        'Q' => Kind.Queen,
        'K' => Kind.King,
        else => Kind.Pawn,
    };
}
