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

    pub fn all_positions() [64]Position {
        var positions: [64]Position = undefined;
        inline for (0..8) |rank| {
            inline for (0..8) |file| {
                const pos = Position{ .rank = rank, .file = file };
                positions[pos.to_index()] = pos;
            }
        }
    }
};

const MoveOffset = enum(i8) {
    North = 8,
    South = -8,
    West = -1,
    East = 1,
    NorthWest = 7,
    NorthEast = 9,
    SouthWest = -9,
    SouthEast = -7,
};

const dir_offsets = [8]MoveOffset{
    MoveOffset.North,
    MoveOffset.South,
    MoveOffset.West,
    MoveOffset.East,
    MoveOffset.NorthWest,
    MoveOffset.NorthEast,
    MoveOffset.SouthWest,
    MoveOffset.SouthEast,
};

fn compute_num_cells_to_edge() [64][8]u8 {
    const all_positon = Position.all_positions();
    var dist_to_edge: [64][8]u8 = undefined;
    for (all_positon) |pos| {
        const num_north = 7 - pos.rank;
        const num_south = pos.rank;
        const num_west = pos.file;
        const num_east = 7 - pos.file;

        dist_to_edge[pos.to_index()] = .{
            num_north,
            num_south,
            num_west,
            num_east,

            @min(num_north, num_west),
            @min(num_north, num_east),
            @min(num_south, num_west),
            @min(num_south, num_west),
        };
    }

    return num_squares_to_edge;
}

const num_squares_to_edge = compute_num_cells_to_edge();

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

    // pub fn get_valid_moves(self: Board, pos: Position) anyerror!std.ArrayList(Position) {
    //     var valid_pos = std.ArrayList(Position);

    //     const cell = self.get_cell(pos);
    //     switch (cell) {
    //         .piece => |p| {},
    //         .empty => {},
    //     }

    //     return valid_pos;
    // }
};
