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

    pub fn to_symbol(self: Kind) []const u8 {
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

pub const Piece = struct {
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
};
