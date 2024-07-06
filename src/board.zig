const std = @import("std");
const piece = @import("piece.zig");
const fen = @import("fen.zig");

pub const Cell = union(enum) { empty, piece: piece.Piece };

const empty_rank: [8]Cell = .{Cell.empty} ** 8;

pub const Position = struct {
    rank: usize,
    file: usize,
};

pub const Board = struct {
    // TODO: track castling + en passant
    cells: [8][8]Cell, // TODO: make single arr?

    pub fn from_fen(fen_str: []const u8) Board {
        return fen.parse(fen_str);
    }

    pub fn init() Board {
        return fen.parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR");
    }

    pub fn get_cell(self: Board, pos: Position) Cell {
        std.debug.assert(pos.rank < 8);
        std.debug.assert(pos.file < 8);
        return self.cells[pos.rank][pos.file];
    }

    pub fn set_cell(self: *Board, pos: Position, cell: Cell) void {
        std.debug.assert(pos.rank < 8);
        std.debug.assert(pos.file < 8);
        self.cells[pos.rank][pos.file] = cell;
    }
};
