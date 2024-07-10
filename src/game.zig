const std = @import("std");
const utils = @import("utils.zig");

const board_types = @import("board.zig");
const Board = board_types.Board;
const Cell = board_types.Cell;
const Position = board_types.Position;
const Move = board_types.Move;

const bit_set_types = @import("bitset.zig");
const BoardBitSet = bit_set_types.BoardBitSet;
const Dir = bit_set_types.Dir;
const MoveFN = bit_set_types.MoveFN;

const piece = @import("piece.zig");
const Piece = piece.Piece;

const precompute = @import("precompute.zig");

const fen = @import("fen.zig");

const Allocator = std.mem.Allocator;

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

pub const GameManager = struct {
    const Self = @This();

    // TODO: track castling + en passant
    board: Board,
    active_color: piece.Color = piece.Color.White,
    /// allocator for internal state, returned moves will take in an allocator
    allocater: Allocator,
    rays: precompute.Rays,

    pub fn init(allocater: Allocator) Self {
        return Self.from_fen(allocater, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w");
    }

    pub fn from_fen(allocater: Allocator, fen_str: []const u8) Self {
        const state = fen.parse(fen_str);
        const rays = precompute.computeRays();
        return Self{
            .board = state.board,
            .active_color = state.active_color,
            .allocater = allocater,
            .rays = rays,
        };
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

        const start_idx = pos.to_index();

        const cell = self.get_cell(pos);

        const p = switch (cell) {
            .piece => |p| p,
            .empty => return BoardBitSet.initEmpty(),
        };

        const start_bs = BoardBitSet.initWithIndex(start_idx);

        if (p.is_pawn()) {
            const occupied = self.board.occupied_set;

            const non_captures = start_bs.pawnMoves(occupied.complement(), p.color);

            const enemy_color = p.color.get_enemy();

            // TODO: enpassant check
            const enemies = self.board.color_sets[@intFromEnum(enemy_color)];

            const possible_attacks = start_bs.pawnAttacks(p.color, enemies);

            return non_captures.unionWith(possible_attacks);
        }

        var valid_pos = BoardBitSet.initEmpty();

        if (p.is_knight()) {
            const possible_moves = precompute.KNIGHT_MOVES[start_idx];

            const freinds = self.board.color_sets[@intFromEnum(p.color)];

            return possible_moves.differenceWith(freinds);
        }

        if (p.is_king()) {
            const possible_moves = precompute.KING_MOVES[start_idx];

            const freinds = self.board.color_sets[@intFromEnum(p.color)];

            return possible_moves.differenceWith(freinds);
        }

        // moves for bishops, rooks, and queens
        // bishops should only look at the first 4 dir_offsets, rooks the last 4, queens all of it
        const dir_start: u8 = if (p.is_bishop()) 4 else 0;
        const dir_end: u8 = if (p.is_rook()) 4 else 8;
        for (dir_start..dir_end) |dirIndex| {
            const rays = self.rays[start_idx][dirIndex];

            valid_pos.setUnion(rays);

            // const max_moves_in_dir = precompute.NUM_SQUARES_TO_EDGE[start_idx][dirIndex];
            // const dir: Dir = @enumFromInt(dirIndex);
            // const move_fn = dir.to_move_func();

            // var attacks = BoardBitSet.initEmpty();
            // attacks.set(start_idx);

            // attacks = move_fn(attacks);

            // for (0..max_moves_in_dir) |_| {
            //     defer attacks = move_fn(attacks);

            //     const target_idx = attacks.bit_set.findFirstSet().?;
            //     const target = self.get_cell(Position.from_index(target_idx));

            //     // blocked by a freind, stop going in this dir
            //     if (target.is_freindly(p)) {
            //         break;
            //     }

            //     valid_pos.set(target_idx);

            //     // can capture the peice here but no more
            //     if (target.is_enemy(p)) {
            //         break;
            //     }
        }

        valid_pos.unset(start_idx);
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
