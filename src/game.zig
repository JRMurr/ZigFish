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

        const enmey_queens = self.board.get_piece_set(Piece{ .color = color.get_enemy(), .kind = piece.Kind.Queen });

        var pinned = BoardBitSet.initEmpty();

        for (0..NUM_DIRS) |dir_index| {
            var moves = precompute.RAYS[king_square][dir_index];

            const dir: Dir = @enumFromInt(dir_index);

            var on_ray = moves.intersectWith(self.board.occupied_set);
            if (on_ray.count() > 1) {
                const possible_pin = dir.first_hit_on_ray(on_ray);

                if (!self.board.color_sets[@intFromEnum(color)].isSet(possible_pin)) {
                    continue;
                }

                on_ray.unset(possible_pin);

                const possible_attacker = dir.first_hit_on_ray(on_ray);

                const kind = if (dir_index < 4) piece.Kind.Rook else piece.Kind.Bishop;
                const kind_board = self.board.get_piece_set(Piece{ .color = color.get_enemy(), .kind = kind });

                const all_valid_enemies = kind_board.unionWith(enmey_queens);

                if (all_valid_enemies.intersectWith(on_ray).isSet(possible_attacker)) {
                    pinned.set(possible_pin);
                }
            }
        }
        return pinned;
    }

    pub fn get_sliding_moves(self: Self, p: piece.Piece, pos: Position) BoardBitSet {
        // TODO: debug assert pos has the piece?
        const start_idx = pos.toIndex();

        var attacks = BoardBitSet.initEmpty();

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
            attacks.setUnion(moves);
        }

        return attacks;
    }

    pub fn get_all_attacked_sqaures(self: Self, color: piece.Color) BoardBitSet {
        const pinned_pieces = self.find_pinned_pieces(color);

        var attacks = BoardBitSet.initEmpty();

        const freinds = self.board.color_sets[@intFromEnum(color)];

        for (0..utils.enum_len(piece.Kind)) |kind_idx| {
            const kind: piece.Kind = @enumFromInt(kind_idx);
            const p = Piece{ .color = color, .kind = kind };
            const piece_set = self.board.get_piece_set(p).differenceWith(pinned_pieces);

            switch (kind) {
                piece.Kind.Pawn => {
                    // TODO: enpassant check
                    const enemies = self.board.color_sets[@intFromEnum(color.get_enemy())];
                    const pawn_attacks = piece_set.pawnAttacks(color, enemies);
                    // pawn_attacks.debug();
                    attacks.setUnion(pawn_attacks);
                },
                piece.Kind.Knight => {
                    const knight_attacks = piece_set.knightMoves();
                    // knight_attacks.debug();
                    attacks.setUnion(knight_attacks);
                },
                piece.Kind.King => {
                    const king_attacks = piece_set.kingMoves();
                    // king_attacks.debug();
                    attacks.setUnion(king_attacks);
                },
                piece.Kind.Bishop, piece.Kind.Queen, piece.Kind.Rook => {
                    var slide_attacks = BoardBitSet.initEmpty();
                    var iter = piece_set.bit_set.iterator(.{});
                    while (iter.next()) |sqaure| {
                        const pos = Position.fromIndex(sqaure);
                        slide_attacks.setUnion(self.get_sliding_moves(p, pos));
                    }
                    // slide_attacks.debug();
                    attacks.setUnion(slide_attacks);
                },
            }
        }
        attacks.remove(freinds);
        return attacks;
    }

    pub fn get_valid_moves(self: Self, pos: Position) BoardBitSet {
        const start_idx = pos.toIndex();

        const cell = self.get_cell(pos);

        const p = switch (cell) {
            .piece => |p| p,
            .empty => return BoardBitSet.initEmpty(),
        };

        const pinned_pieces = self.find_pinned_pieces(p.color);

        if (pinned_pieces.isSet(start_idx)) {
            return BoardBitSet.initEmpty();
        }

        const start_bs = BoardBitSet.initWithIndex(start_idx);

        const freinds = self.board.color_sets[@intFromEnum(p.color)];
        const enemy_color = p.color.get_enemy();

        const enemies = self.board.color_sets[@intFromEnum(enemy_color)];

        if (p.is_pawn()) {
            const occupied = self.board.occupied_set;

            const non_captures = start_bs.pawnMoves(occupied.complement(), p.color);

            // TODO: enpassant check
            const possible_attacks = start_bs.pawnAttacks(p.color, enemies);

            return non_captures.unionWith(possible_attacks);
        }

        if (p.is_knight()) {
            const possible_moves = precompute.KNIGHT_MOVES[start_idx];

            return possible_moves.differenceWith(freinds);
        }

        if (p.is_king()) {
            const enemy_attacked_sqaures = self.get_all_attacked_sqaures(enemy_color);

            const possible_moves = precompute.KING_MOVES[start_idx];
            return possible_moves.differenceWith(freinds).differenceWith(enemy_attacked_sqaures);
        }

        var possible_moves = self.get_sliding_moves(p, pos);

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
