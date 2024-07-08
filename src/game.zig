const std = @import("std");

const board_types = @import("board.zig");
const Board = board_types.Board;
const Cell = board_types.Cell;
const Position = board_types.Position;
const Move = board_types.Move;

const piece = @import("piece.zig");
const Piece = piece.Piece;

const fen = @import("fen.zig");

const Allocator = std.mem.Allocator;

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
    -2 + 8,
    -1 + 16,
    1 + 16,
    2 + 8,
    2 - 8,
    1 - 16,
    -1 - 16,
    -2 - 8,
};

pub const GameManager = struct {
    const Self = @This();

    // TODO: track castling + en passant
    board: Board,
    active_color: piece.Color = piece.Color.White,
    /// allocator for internal state, returned moves will take in an allocator
    allocater: Allocator,

    pub fn init(allocater: Allocator) Self {
        return Self.from_fen(allocater, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w");
    }

    pub fn from_fen(allocater: Allocator, fen_str: []const u8) Self {
        const state = fen.parse(fen_str);
        return Self{ .board = state.board, .active_color = state.active_color, .allocater = allocater };
    }

    pub fn get_cell(self: Self, pos: Position) Cell {
        const maybe_piece = self.board.get_piece(pos);
        if (maybe_piece) |p| {
            return .{ .piece = p };
        }

        return .empty;
    }

    pub fn set_cell(self: *Self, pos: Position, cell: Cell) void {
        const maybe_piece = switch (cell) {
            .piece => |p| p,
            .empty => null,
        };

        self.board.set_piece(pos, maybe_piece);
    }

    pub fn flip_active_color(self: *Self) void {
        self.active_color = switch (self.active_color) {
            piece.Color.White => piece.Color.Black,
            piece.Color.Black => piece.Color.White,
        };
    }

    pub fn make_move(self: *Self, move: Move) void {
        const start_cell = self.get_cell(move.start);

        const start_peice = switch (start_cell) {
            .empty => return,
            .piece => |p| p,
        };

        self.set_cell(move.start, .empty);

        self.set_cell(move.end, .{ .piece = start_peice });
        self.flip_active_color();
    }

    pub fn get_valid_moves(self: Self, allocater: Allocator, pos: Position) anyerror!std.ArrayList(Position) {
        // TODO: need to see if a move would make the king be in check and remove it
        // 27 is max number of possible postions a queen could move to
        var valid_pos = try std.ArrayList(Position).initCapacity(allocater, 27);

        const start_idx = pos.to_index();

        const cell = self.get_cell(pos);

        const p = switch (cell) {
            .piece => |p| p,
            .empty => return valid_pos,
        };

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
            const offset_mult: i8 = if (p.is_white()) 1 else -1;

            const file_offset: i8 = offset_mult * 8;

            const single_move = compute_target_idx(start_idx, file_offset, 0).?;
            valid_pos.appendAssumeCapacity(Position.from_index(single_move));
            if (p.on_starting_rank(pos.rank)) {
                const double_move = compute_target_idx(start_idx, file_offset, 1).?;
                valid_pos.appendAssumeCapacity(Position.from_index(double_move));
            }

            for ([_]i8{ 7, 9 }) |diag_offset_base| {
                // TODO: enpassant check
                const diag_offset = diag_offset_base * offset_mult;
                const target_idx = compute_target_idx(start_idx, diag_offset, 0).?;
                const target = self.get_cell(Position.from_index(target_idx));
                if (target.is_enemy(p)) {
                    valid_pos.appendAssumeCapacity(Position.from_index(target_idx));
                }
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
                const target = self.get_cell(Position.from_index(target_idx));

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
