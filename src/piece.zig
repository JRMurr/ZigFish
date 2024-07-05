pub const Color = enum(u8) {
    White = 0,
    Black = 1,
};

pub const Kind = enum(u8) {
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
};
