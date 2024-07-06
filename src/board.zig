const std = @import("std");
const piece = @import("piece.zig");

pub const Cell = union(enum) { empty, piece: piece.Piece };

// TODO: can I do comptime stuff to make this generic over array length?

fn kinds_to_cell(kinds: [8]piece.Kind, color: piece.Color) [8]Cell {
    var cells: [8]Cell = undefined;
    for (kinds, 0..) |kind, idx| {
        const cell = Cell{ .piece = piece.Piece{
            .color = color,
            .kind = kind,
        } };

        cells[idx] = cell;
    }

    return cells;
}

const empty_rank: [8]Cell = .{Cell.empty} ** 8;

pub const Board = struct {
    cells: [8][8]Cell, // TODO: make single arr?

    pub fn init_empty() Board {
        const cells: [8][8]Cell = .{.{Cell.empty} ** 8} ** 8;
        return .{ .cells = cells };
    }

    pub fn init() Board {
        const start_row = [8]piece.Kind{
            piece.Kind.Rook,
            piece.Kind.Knight,
            piece.Kind.Bishop,
            piece.Kind.Queen,
            piece.Kind.King,
            piece.Kind.Bishop,
            piece.Kind.Knight,
            piece.Kind.Rook,
        };

        const pawn_row: [8]piece.Kind = .{piece.Kind.Pawn} ** 8;

        const cells: [8][8]Cell = .{
            kinds_to_cell(start_row, piece.Color.White),
            kinds_to_cell(pawn_row, piece.Color.White),
            empty_rank,
            empty_rank,
            empty_rank,
            empty_rank,
            kinds_to_cell(pawn_row, piece.Color.Black),
            kinds_to_cell(start_row, piece.Color.Black),
        };
        return .{ .cells = cells };
    }
};
