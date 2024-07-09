pub const Color = enum(u1) {
    White = 0,
    Black = 1,
};

pub const Kind = enum(u3) {
    King = 0,
    Queen = 1,
    Bishop = 2,
    Knight = 3,
    Rook = 4,
    Pawn = 5,
};

pub const Piece = struct {
    color: Color,
    kind: Kind,

    pub inline fn is_knight(self: Piece) bool {
        return self.kind == Kind.Knight;
    }

    pub inline fn is_king(self: Piece) bool {
        return self.kind == Kind.King;
    }

    pub inline fn is_queen(self: Piece) bool {
        return self.kind == Kind.Queen;
    }

    pub inline fn is_bishop(self: Piece) bool {
        return self.kind == Kind.Bishop;
    }

    pub inline fn is_rook(self: Piece) bool {
        return self.kind == Kind.Rook;
    }

    pub inline fn is_pawn(self: Piece) bool {
        return self.kind == Kind.Pawn;
    }

    pub inline fn is_white(self: Piece) bool {
        return self.color == Color.White;
    }

    pub inline fn is_black(self: Piece) bool {
        return self.color == Color.Black;
    }

    pub inline fn is_freindly(self: Piece, other: Piece) bool {
        return self.color == other.color;
    }

    pub inline fn on_starting_rank(self: Piece, rank: usize) bool {
        return switch (self.color) {
            Color.White => if (self.is_pawn()) rank == 1 else rank == 0,
            Color.Black => if (self.is_pawn()) rank == 6 else rank == 7,
        };
    }
};
