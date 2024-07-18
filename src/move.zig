const std = @import("std");
const piece = @import("piece.zig");
const Piece = piece.Piece;

const board_types = @import("board.zig");
const Position = board_types.Position;

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
kind: piece.Kind,
move_flags: MoveFlags,
captured_kind: ?piece.Kind = null,
promotion_kind: ?piece.Kind = null,

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
