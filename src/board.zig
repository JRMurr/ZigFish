const std = @import("std");
const piece = @import("piece.zig");
const fen = @import("fen.zig");

pub const Cell = union(enum) {
    empty,
    piece: piece.Piece,

    pub fn is_freindly(self: Cell, other: piece.Piece) bool {
        return switch (self) {
            .piece => |p| p.color == other.color,
            .empty => false,
        };
    }

    pub fn is_enemy(self: Cell, other: piece.Piece) bool {
        return switch (self) {
            .piece => |p| p.color != other.color,
            .empty => false,
        };
    }
};

inline fn difference(a: usize, b: usize) usize {
    var diff = @as(i8, @intCast(a)) - @as(i8, @intCast(b));

    if (diff < 0) {
        diff *= -1;
    }

    return @as(usize, @intCast(diff));
}

pub const Position = struct {
    rank: usize,
    file: usize,

    pub inline fn to_index(self: Position) usize {
        std.debug.assert(self.rank < 8);
        std.debug.assert(self.file < 8);
        return self.rank * 8 + self.file;
    }

    pub inline fn from_index(idx: usize) Position {
        const file = idx % 8;
        const rank = @divFloor(idx, 8);
        return Position{ .file = file, .rank = rank };
    }

    pub fn all_positions() [64]Position {
        var positions: [64]Position = undefined;
        inline for (0..8) |rank| {
            inline for (0..8) |file| {
                const pos = Position{ .rank = rank, .file = file };
                positions[pos.to_index()] = pos;
            }
        }

        return positions;
    }

    /// taxicab distance btwn positons
    pub inline fn dist(self: Position, other: Position) usize {
        return difference(self.rank, other.rank) + difference(self.file, other.file);
    }
};

// const MoveOffset = enum(i8) {
//     North = 8,
//     South = -8,
//     West = -1,
//     East = 1,
//     NorthWest = 7,
//     NorthEast = 9,
//     SouthWest = -9,
//     SouthEast = -7,
// };

const dir_offsets = [8]i8{
    8, // MoveOffset.North,
    -8, // MoveOffset.South,
    -1, // MoveOffset.West,
    1, // MoveOffset.East,
    7, // MoveOffset.NorthWest,
    9, // MoveOffset.NorthEast,
    -9, // MoveOffset.SouthWest,
    -7, // MoveOffset.SouthEast,
};

fn compute_num_cells_to_edge() [64][8]u8 {
    const all_positon = Position.all_positions();
    var dist_to_edge: [64][8]u8 = undefined;
    for (all_positon) |pos| {
        const num_north = 7 - pos.rank;
        const num_south = pos.rank;
        const num_west = pos.file;
        const num_east = 7 - pos.file;

        // TODO: should i make this a struct?
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

    return dist_to_edge;
}

const num_squares_to_edge = compute_num_cells_to_edge();

// TODO: try to precompute valid knight moves for each square at startup
const knight_offsets = [8]i8{
    // 2 * 8 + 1,
    // 2 * 8 - 1,
    // 2 * -8 + 1,
    // 2 * -8 - 1,
    // 8 + 2,
    // 8 - 2,
    // -8 + 2,
    // -8 - 2,
    -2 + 8,
    -1 + 16,
    1 + 16,
    2 + 8,
    2 - 8,
    1 - 16,
    -1 - 16,
    -2 - 8,
};

pub const Board = struct {
    // TODO: track castling + en passant
    cells: [64]Cell,
    active_color: piece.Color = piece.Color.White,
    allocater: std.mem.Allocator,

    pub fn from_fen(allocater: std.mem.Allocator, fen_str: []const u8) Board {
        return fen.parse(allocater, fen_str);
    }

    pub fn init(allocater: std.mem.Allocator) Board {
        return fen.parse(allocater, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w");
    }

    pub fn get_cell(self: Board, pos: Position) Cell {
        return self.cells[pos.to_index()];
    }

    pub fn set_cell(self: *Board, pos: Position, cell: Cell) void {
        self.cells[pos.to_index()] = cell;
    }

    pub fn get_valid_moves(self: Board, pos: Position) anyerror!std.ArrayList(Position) {
        // TODO: need to see if a move would make the king be in check and remove it
        // 25ish should be more than the max possible moves a queen could make
        var valid_pos = try std.ArrayList(Position).initCapacity(self.allocater, 25);

        const start_idx = pos.to_index();

        const cell = self.get_cell(pos);
        switch (cell) {
            .piece => |p| {
                if (p.is_knight()) {
                    for (knight_offsets) |offset| {
                        if (start_idx > offset) {
                            const target = @as(i8, @intCast(start_idx)) + offset;
                            if (target < 64) {
                                const target_pos = Position.from_index(@intCast(target));
                                // hack to make sure move is valid, should just pre-compute allowed moves
                                if (pos.dist(target_pos) == 3) {
                                    valid_pos.appendAssumeCapacity(target_pos);
                                }
                            }
                        }
                    }

                    return valid_pos;
                }

                if (p.is_king()) {
                    for (dir_offsets) |offset| {
                        const maybe_target_idx = compute_target_idx(start_idx, offset, 0);
                        if (maybe_target_idx) |target_idx| {
                            const target_pos = Position.from_index(target_idx);
                            valid_pos.appendAssumeCapacity(target_pos);
                        }
                    }
                    return valid_pos;
                }

                if (p.is_pawn()) {
                    const offset: i8 = if (p.is_white()) 8 else -8;
                    const single_move = compute_target_idx(start_idx, offset, 0).?;
                    valid_pos.appendAssumeCapacity(Position.from_index(single_move));
                    if (p.on_starting_rank(pos.rank)) {
                        const double_move = compute_target_idx(start_idx, offset, 1).?;
                        valid_pos.appendAssumeCapacity(Position.from_index(double_move));
                    }
                    return valid_pos;
                }

                // moves for bishops, rooks, and queens
                // bishops should only look at the first 4 dir_offsets, rooks the last 4, queens all of it
                const dir_start: u8 = if (p.is_bishop()) 4 else 0;
                const dir_end: u8 = if (p.is_rook()) 4 else 8;
                for (dir_start..dir_end) |dirIndex| {
                    const max_moves_in_dir = num_squares_to_edge[start_idx][dirIndex];
                    for (0..max_moves_in_dir) |n| {
                        const target_idx = compute_target_idx(start_idx, dir_offsets[dirIndex], n).?;
                        const target = self.cells[target_idx];

                        // blocked by a freind, stop going in this dir
                        if (target.is_freindly(p)) {
                            break;
                        }

                        valid_pos.appendAssumeCapacity(Position.from_index(target_idx));

                        // can capture the peice here but no more
                        if (target.is_enemy(p)) {
                            break;
                        }
                    }
                }
            },
            .empty => {},
        }

        return valid_pos;
    }
};

inline fn compute_target_idx(start_idx: usize, dir: i8, n: usize) ?usize {
    const mult: i8 = @intCast(n + 1);

    const target_idx = @as(i8, @intCast(start_idx)) + (dir * mult);

    if (target_idx < 0 or target_idx >= 64) {
        return null;
    }

    return @as(usize, @intCast(target_idx));
}
