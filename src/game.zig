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

const piece = @import("piece.zig");
const Piece = piece.Piece;

const precompute = @import("precompute.zig");

const fen = @import("fen.zig");

const Allocator = std.mem.Allocator;

const NUM_DIRS = utils.enum_len(Dir);

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

    pub fn init(allocater: Allocator) Self {
        return Self.from_fen(allocater, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w");
    }

    pub fn from_fen(allocater: Allocator, fen_str: []const u8) Self {
        const state = fen.parse(fen_str);
        return Self{
            .board = state.board,
            .active_color = state.active_color,
            .allocater = allocater,
        };
    }

    pub fn get_cell(self: Self, pos: Position) Cell {
        const maybe_piece = self.board.get_pos(pos);
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

        self.board.set_pos(pos, maybe_piece);
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

    pub fn find_pinned_pieces(self: Self, color: piece.Color) BoardBitSet {
        const king_board = self.board.get_piece_set(Piece{ .color = color, .kind = piece.Kind.King });
        const king_square = king_board.bitScanForward();

        var pinned = BoardBitSet.initEmpty();

        for (0..NUM_DIRS) |dirIndex| {
            var moves = precompute.RAYS[king_square][dirIndex];

            const dir: Dir = @enumFromInt(dirIndex);

            var on_ray = moves.intersectWith(self.board.occupied_set);
            if (on_ray.count() > 1) {
                const possible_pin = dir.first_hit_on_ray(on_ray);

                on_ray.unset(possible_pin);

                const possible_attacker = dir.first_hit_on_ray(on_ray);

                // check if attacker is enemy color and valid type for this ray

            }
            // possible_moves.setUnion(moves);
        }
        return pinned;
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

        const freinds = self.board.color_sets[@intFromEnum(p.color)];

        if (p.is_pawn()) {
            const occupied = self.board.occupied_set;

            const non_captures = start_bs.pawnMoves(occupied.complement(), p.color);

            const enemy_color = p.color.get_enemy();

            // TODO: enpassant check
            const enemies = self.board.color_sets[@intFromEnum(enemy_color)];

            const possible_attacks = start_bs.pawnAttacks(p.color, enemies);

            return non_captures.unionWith(possible_attacks);
        }

        if (p.is_knight()) {
            const possible_moves = precompute.KNIGHT_MOVES[start_idx];

            return possible_moves.differenceWith(freinds);
        }

        if (p.is_king()) {
            const possible_moves = precompute.KING_MOVES[start_idx];

            return possible_moves.differenceWith(freinds);
        }

        var possible_moves = BoardBitSet.initEmpty();
        // moves for bishops, rooks, and queens
        // bishops should only look at the first 4 dir_offsets, rooks the last 4, queens all of it
        const dir_start: u8 = if (p.is_bishop()) 4 else 0;
        const dir_end: u8 = if (p.is_rook()) 4 else 8;
        for (dir_start..dir_end) |dirIndex| {
            var moves = precompute.RAYS[start_idx][dirIndex];

            const dir: Dir = @enumFromInt(dirIndex);

            const blocker = moves.intersectWith(self.board.occupied_set);
            if (blocker.count() > 0) {
                const sqaure = if (dir.is_positive())
                    blocker.bitScanForward()
                else
                    blocker.bitScanReverse();

                moves.toggleSet(precompute.RAYS[sqaure][dirIndex]);
            }
            possible_moves.setUnion(moves);
        }

        return possible_moves.differenceWith(freinds);
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
