const std = @import("std");
const piece = @import("piece.zig");
const fen = @import("fen.zig");

pub const Cell = union(enum) { empty, piece: piece.Piece };

pub const Position = struct {
    rank: usize,
    file: usize,

    pub fn to_index(self: Position) usize {
        std.debug.assert(self.rank < 8);
        std.debug.assert(self.file < 8);
        return self.rank * 8 + self.file;
    }
};

pub const Board = struct {
    // TODO: track castling + en passant
    cells: [64]Cell,
    active_color: piece.Color = piece.Color.White,

    pub fn from_fen(fen_str: []const u8) Board {
        return fen.parse(fen_str);
    }

    pub fn init() Board {
        return fen.parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w");
    }

    pub fn get_cell(self: Board, pos: Position) Cell {
        return self.cells[pos.to_index()];
    }

    pub fn set_cell(self: *Board, pos: Position, cell: Cell) void {
        self.cells[pos.to_index()] = cell;
    }
};
