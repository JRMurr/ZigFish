const std = @import("std");
const ZigFish = @import("root.zig");

const utils = ZigFish.Utils;
const Piece = ZigFish.Piece;
const Kind = Piece.Kind;
const Color = Piece.Color;

const Position = ZigFish.Position;

const MoveList = ZigFish.MoveList;

pub const MoveType = enum {
    Capture,
    Promotion,
    EnPassant,
    Castling,
};

pub const MoveFlags = std.enums.EnumSet(MoveType);

pub const SimpleMove = struct {
    start: Position,
    end: Position,
    promotion_kind: ?Kind = null,

    pub fn fromStr(str: []const u8) !SimpleMove {
        if (str.len < 4 or str.len > 5) {
            std.log.debug("invalid move string: {s}\tlen: {}", .{ str, str.len });
            return error.InvalidMove;
        }

        const start = Position.fromStr(str[0..2]);
        const end = Position.fromStr(str[2..4]);

        var promotion_kind: ?Kind = null;
        if (str.len == 5) {
            promotion_kind = Move.parsePieceType(std.ascii.toUpper(str[4]));
        }

        return .{ .start = start, .end = end, .promotion_kind = promotion_kind };
    }

    pub fn toStr(self: *const SimpleMove) [5]u8 {
        const from_str = self.start.toStr();
        const to_str = self.end.toStr();
        const promotion_symbol = if (self.promotion_kind) |k| k.toSymbol() else "";

        var str = comptime utils.initStr(' ', 5);
        _ = std.fmt.bufPrint(&str, "{s}{s}{s}", .{ from_str, to_str, promotion_symbol }) catch {
            std.debug.panic("Bad move format for {any}", .{self});
        };

        return str;
    }
};

const SAN_LEN = 8;

pub const Move = struct {
    start: Position,
    end: Position,
    kind: Kind,
    move_flags: MoveFlags,
    captured_kind: ?Kind = null,
    promotion_kind: ?Kind = null,

    pub fn toSan(self: *const Move) [SAN_LEN]u8 {
        var str = comptime utils.initStr(' ', SAN_LEN);
        _ = self.toSanBuf(&str);
        return str;
    }

    pub fn toSanBuf(self: *const Move, buff: []u8) []u8 {
        // https://www.chessprogramming.org/Algebraic_Chess_Notation#SAN
        // TODO: san can omit info depening on if the move is unambiguous.
        // for now duing "full"
        // TODO: castling

        const from_str = self.start.toStr();
        const to_str = self.end.toStr();

        const capture_str = if (self.move_flags.contains(MoveType.Capture)) "x" else "";

        const piece_symbol = self.kind.toSymbol();

        const promotion_symbol = if (self.promotion_kind) |k| k.toSymbol() else "";

        return std.fmt.bufPrint(buff, "{s}{s}{s}{s}{s}", .{ piece_symbol, from_str, capture_str, to_str, promotion_symbol }) catch {
            std.debug.panic("Bad san format for {any}", .{self});
        };
    }

    pub fn fromSan(san: []const u8, valid_moves: []const Move) Move {
        // Handle castling
        const is_king_castle: bool = std.mem.startsWith(u8, san, "O-O");
        const is_queen_castle: bool = std.mem.startsWith(u8, san, "O-O-O");
        if (is_king_castle or is_queen_castle) {
            const end_file: usize = if (is_queen_castle) 2 else 6;
            for (valid_moves) |m| {
                if (!m.move_flags.eql(MoveFlags.initOne(MoveType.Castling))) {
                    continue;
                }
                const rankFile = m.end.toRankFile();
                if (rankFile.file != end_file) {
                    continue;
                }

                return m;
            }
            std.debug.panic("could not find castle move for {s}", .{san});
        }

        var move_flags = MoveFlags.initEmpty();

        var idx: usize = 0;
        var end_idx = san.len - 1;
        var kind = Kind.Pawn;

        if (!std.ascii.isDigit(san[end_idx])) {
            // check or checkmate char at end
            end_idx -= 1;
        }

        var end_square: Position = undefined;
        var promotion_kind: ?Kind = null;
        // var capture_kind: ?kind = null;

        if (std.ascii.isUpper(san[idx])) {
            kind = parsePieceType(san[idx]);
            idx += 1;
        }

        var maybe_file: ?usize = null;
        var maybe_rank: ?usize = null;

        if (idx < end_idx - 1) {
            if (std.ascii.isAlphabetic(san[idx]) and san[idx] != 'x') {
                maybe_file = @intCast(san[idx] - 'a');
                idx += 1;
            }

            if (std.ascii.isDigit(san[idx]) and san[idx] != 'x') {
                maybe_rank = @intCast(san[idx] - '1');
                idx += 1;
            }
        }

        // Parse captures
        if (std.mem.indexOf(u8, san, "x")) |capture_idx| {
            move_flags.setPresent(MoveType.Capture, true);
            idx = capture_idx + 1;
            // _ = capture_idx;
        }

        // Parse destination square
        if (end_idx - idx >= 1) {
            const square_str = san[(end_idx - 1)..(end_idx + 1)];
            // std.log.debug("square_str {s}", .{square_str});
            end_square = Position.fromStr(square_str);
        } else {
            std.debug.panic("error parsing end_square: {s}", .{san});
        }

        // Parse promotion
        if (san.len > 2 and san[end_idx - 2] == '=') {
            move_flags.setPresent(MoveType.Promotion, true);
            promotion_kind = parsePieceType(san[end_idx]);
        }

        for (valid_moves) |m| {
            if (m.kind != kind) {
                continue;
            }
            if (!m.end.eql(end_square)) {
                continue;
            }
            if (!m.move_flags.supersetOf(move_flags)) { // super set to allow for en passant flag
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

            // std.debug.assert(std.mem.startsWith(u8, san, &m.toStrSimple()));
            return m;
        }

        // for (valid_moves) |m| {
        //     std.debug.print("move: {s}\n", .{m.toStrSimple()});
        // }

        std.debug.panic("could not find move for {s}\nkind: {}\nend_square: {s}\nmaybe_file: {?}\nmaybe_rank: {?}\ncapture? {}\n", .{
            san,
            kind,
            end_square.toStr(),
            maybe_file,
            maybe_rank,
            move_flags.contains(MoveType.Capture),
        });
    }

    pub fn toStrSimple(self: *const Move) [5]u8 {
        return self.toSimple().toStr();
    }

    pub fn toSimple(self: *const Move) SimpleMove {
        return .{
            .start = self.start,
            .end = self.end,
            .promotion_kind = self.promotion_kind,
        };
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
};

test "no static erros" {
    std.testing.refAllDecls(Move);
}

test "eql" {
    const moveOne = Move{
        .start = Position.fromIndex(10),
        .end = Position.fromStr("e4"),
        .kind = ZigFish.Kind.Pawn,
        .move_flags = MoveFlags.initOne(MoveType.Capture),
    };

    const moveTwo = Move{
        .start = Position.fromIndex(3),
        .end = Position.fromStr("c3"),
        .kind = ZigFish.Kind.Knight,
        .move_flags = MoveFlags{},
    };

    try std.testing.expect(moveOne.eql(moveTwo) == false);

    const moveThree = Move{
        .start = Position.fromIndex(10),
        .end = Position.fromStr("e4"),
        .kind = ZigFish.Kind.Pawn,
        .move_flags = MoveFlags{},
    };

    try std.testing.expect(moveOne.eql(moveThree) == false);

    const moveFour = Move{
        .start = Position.fromIndex(10),
        .end = Position.fromStr("e4"),
        .kind = ZigFish.Kind.Pawn,
        .move_flags = MoveFlags.initOne(MoveType.Capture),
    };

    try std.testing.expect(moveOne.eql(moveFour) == true);
}
