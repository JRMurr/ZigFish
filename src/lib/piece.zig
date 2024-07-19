const std = @import("std");
const utils = @import("zigfish").utils;

pub const Color = enum(u1) {
    White = 0,
    Black = 1,

    pub fn get_enemy(self: Color) Color {
        return switch (self) {
            .White => Color.Black,
            .Black => Color.White,
        };
    }
};

pub const Kind = enum(u3) {
    King = 0,
    Queen = 1,
    Bishop = 2,
    Knight = 3,
    Rook = 4,
    Pawn = 5,

    pub fn toSymbol(self: Kind) []const u8 {
        return switch (self) {
            .King => "K",
            .Queen => "Q",
            .Bishop => "B",
            .Knight => "N",
            .Rook => "R",
            .Pawn => "",
        };
    }
};

pub const NUM_KINDS = utils.enum_len(Kind);
pub const NUM_COLOR = utils.enum_len(Color);

const Piece = @This();

color: Color,
kind: Kind,

pub fn eql(self: Piece, other: Piece) bool {
    return self.color == other.color and self.kind == other.kind;
}

pub fn is_knight(self: Piece) bool {
    return self.kind == Kind.Knight;
}

pub fn is_king(self: Piece) bool {
    return self.kind == Kind.King;
}

pub fn is_queen(self: Piece) bool {
    return self.kind == Kind.Queen;
}

pub fn is_bishop(self: Piece) bool {
    return self.kind == Kind.Bishop;
}

pub fn is_rook(self: Piece) bool {
    return self.kind == Kind.Rook;
}

pub fn is_pawn(self: Piece) bool {
    return self.kind == Kind.Pawn;
}

pub fn is_white(self: Piece) bool {
    return self.color == Color.White;
}

pub fn is_black(self: Piece) bool {
    return self.color == Color.Black;
}

pub fn is_freindly(self: Piece, other: Piece) bool {
    return self.color == other.color;
}

pub fn on_starting_rank(self: Piece, rank: usize) bool {
    return switch (self.color) {
        Color.White => if (self.is_pawn()) rank == 1 else rank == 0,
        Color.Black => if (self.is_pawn()) rank == 6 else rank == 7,
    };
}

pub fn fromChar(char: u8) Piece {
    return switch (char) {
        'K' => Piece{ .kind = Kind.King, .color = Color.White },
        'k' => Piece{ .kind = Kind.King, .color = Color.Black },
        'Q' => Piece{ .kind = Kind.Queen, .color = Color.White },
        'q' => Piece{ .kind = Kind.Queen, .color = Color.Black },
        'B' => Piece{ .kind = Kind.Bishop, .color = Color.White },
        'b' => Piece{ .kind = Kind.Bishop, .color = Color.Black },
        'N' => Piece{ .kind = Kind.Knight, .color = Color.White },
        'n' => Piece{ .kind = Kind.Knight, .color = Color.Black },
        'R' => Piece{ .kind = Kind.Rook, .color = Color.White },
        'r' => Piece{ .kind = Kind.Rook, .color = Color.Black },
        'P' => Piece{ .kind = Kind.Pawn, .color = Color.White },
        'p' => Piece{ .kind = Kind.Pawn, .color = Color.Black },
        else => {
            const str = [_]u8{char};
            std.debug.panic("invalid piece char: {s}", .{str});
        },
    };
}

pub fn toChar(self: Piece) u8 {
    const kind_char: u8 = switch (self.kind) {
        .King => 'K',
        .Queen => 'Q',
        .Bishop => 'B',
        .Knight => 'N',
        .Rook => 'R',
        .Pawn => 'P',
    };
    if (self.is_white()) {
        return kind_char;
    }

    return kind_char + 32;
}

test "no static erros" {
    std.testing.refAllDeclsRecursive(@This());
}

test "from and to char" {
    const chars = "KkQqBbNnRrPp";
    for (chars) |char| {
        const piece = fromChar(char);
        try std.testing.expectEqual(char, piece.toChar());
    }
}
