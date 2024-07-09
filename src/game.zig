const std = @import("std");
const utils = @import("utils.zig");

const board_types = @import("board.zig");
const Board = board_types.Board;
const Cell = board_types.Cell;
const Position = board_types.Position;
const Move = board_types.Move;
const BoardBitSet = board_types.BoardBitSet;

const piece = @import("piece.zig");
const Piece = piece.Piece;

const fen = @import("fen.zig");

const Allocator = std.mem.Allocator;

const MoveFn = fn (self: BoardBitSet) BoardBitSet;

pub const Dir = enum(u3) {
    North,
    South,
    West,
    East,
    NorthWest,
    NorthEast,
    SouthWest,
    SouthEast,

    pub fn to_move_func_comptime(self: Dir) MoveFn {
        return switch (self) {
            .North => BoardBitSet.northOne,
            .South => BoardBitSet.southOne,
            .West => BoardBitSet.westOne,
            .East => BoardBitSet.eastOne,
            .NorthWest => BoardBitSet.noWeOne,
            .NorthEast => BoardBitSet.noEaOne,
            .SouthWest => BoardBitSet.soWeOne,
            .SouthEast => BoardBitSet.soEaOne,
        };
    }

    pub fn to_move_func(self: Dir) *const MoveFn {
        return switch (self) {
            .North => BoardBitSet.northOne,
            .South => BoardBitSet.southOne,
            .West => BoardBitSet.westOne,
            .East => BoardBitSet.eastOne,
            .NorthWest => BoardBitSet.noWeOne,
            .NorthEast => BoardBitSet.noEaOne,
            .SouthWest => BoardBitSet.soWeOne,
            .SouthEast => BoardBitSet.soEaOne,
        };
    }
};

const NUM_DIRS = utils.enum_len(Dir);

// TOOD: this is awful perf, switch to line attack generation https://www.chessprogramming.org/On_an_empty_Board#Line_Attacks
// fn generate_ray_attacks() [NUM_DIRS][64]BoardBitSet {
//     var all_attacks: [NUM_DIRS][64]BoardBitSet = undefined;

//     inline for (utils.enum_fields(Dir)) |f| {
//         const dir_idx = f.value;
//         const dir: Dir = @enumFromInt(dir_idx);
//         const move_fn = dir.to_move_func();

//         all_attacks[dir_idx] = undefined;
//         for (0..64) |square| {
//             var attacks = BoardBitSet.initEmpty();
//             // init at current position to make logic easier, rem
//             attacks.set(square);

//             var moved = move_fn(attacks);
//             while (moved.count() != 0) {
//                 attacks.bit_set.setUnion(moved.bit_set);
//                 moved = move_fn(attacks);
//             }

//             // start square is not a valid attack
//             attacks.bit_set.unset(square);
//             all_attacks[dir_idx][square] = attacks;
//         }
//     }

//     return all_attacks;
// }

const dir_offsets = [8]i8{
    8, //  MoveOffset.North,
    -8, // MoveOffset.South,
    -1, // MoveOffset.West,
    1, //  MoveOffset.East,
    7, //  MoveOffset.NorthWest,
    9, //  MoveOffset.NorthEast,
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
            @min(num_south, num_east),
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

    pub fn get_valid_moves(self: Self, pos: Position) BoardBitSet {
        // TODO: need to see if a move would make the king be in check and remove it

        var valid_pos = BoardBitSet.initEmpty();

        const start_idx = pos.to_index();
        defer valid_pos.unset(start_idx);

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
                            valid_pos.set(@intCast(target));
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
                    valid_pos.set(target_idx);
                }
            }
            return valid_pos;
        }

        if (p.is_pawn()) {
            const offset_mult: i8 = if (p.is_white()) 1 else -1;

            const file_offset: i8 = offset_mult * 8;

            const single_move = compute_target_idx(start_idx, file_offset, 0).?;
            valid_pos.set(single_move);
            if (p.on_starting_rank(pos.rank)) {
                const double_move = compute_target_idx(start_idx, file_offset, 1).?;
                valid_pos.set(double_move);
            }

            for ([_]i8{ 7, 9 }) |diag_offset_base| {
                // TODO: enpassant check
                const diag_offset = diag_offset_base * offset_mult;
                const target_idx = compute_target_idx(start_idx, diag_offset, 0).?;
                const target = self.get_cell(Position.from_index(target_idx));
                if (target.is_enemy(p)) {
                    valid_pos.set(target_idx);
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
            const dir: Dir = @enumFromInt(dirIndex);
            const move_fn = dir.to_move_func();

            var attacks = BoardBitSet.initEmpty();
            attacks.set(start_idx);

            attacks = move_fn(attacks);

            for (0..max_moves_in_dir) |_| {
                defer attacks = move_fn(attacks);

                const target_idx = attacks.bit_set.findFirstSet().?;
                const target = self.get_cell(Position.from_index(target_idx));

                // blocked by a freind, stop going in this dir
                if (target.is_freindly(p)) {
                    break;
                }

                valid_pos.set(target_idx);

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

// test "check rays" {
//     const ray_attacks = generate_ray_attacks();

//     //https://www.chessprogramming.org/Classical_Approach
//     const dir = Dir.NorthWest;
//     const pos = Position{ .rank = 2, .file = 6 };
//     const pos_idx = pos.to_index();

//     const attacks = ray_attacks[@intFromEnum(dir)][pos_idx];

//     var iter = attacks.bit_set.iterator(.{});

//     while (iter.next()) |idx| {
//         std.debug.print("{}\n", .{Position.from_index(idx)});
//     }

//     try std.testing.expect(attacks.count() == 6);
// }
