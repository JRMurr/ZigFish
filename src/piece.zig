pub const PieceColor = enum {
    White,
    Black,
};

pub const PieceKind = enum {
    King,
    Queen,
    Rook,
    Bishop,
    Knight,
    Pawn,
};

pub const Piece = struct {
    color: PieceColor,
    kind: PieceKind,
};
