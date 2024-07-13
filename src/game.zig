const std = @import("std");
const utils = @import("utils.zig");

const board_types = @import("board.zig");
const Board = board_types.Board;
const Position = board_types.Position;
const Move = board_types.Move;
const MoveType = board_types.MoveType;
const MoveFlags = board_types.MoveFlags;

const bit_set_types = @import("bitset.zig");
const BoardBitSet = bit_set_types.BoardBitSet;
const Dir = bit_set_types.Dir;

const piece = @import("piece.zig");
const Piece = piece.Piece;

const precompute = @import("precompute.zig");

const fen = @import("fen.zig");

const Allocator = std.mem.Allocator;

pub const MoveList = std.ArrayList(Move);

const NUM_DIRS = utils.enum_len(Dir);

const PROMOTION_KINDS = [4]piece.Kind{ piece.Kind.Queen, piece.Kind.Knight, piece.Kind.Bishop, piece.Kind.Rook };

pub const GameManager = struct {
    const Self = @This();

    // TODO: track castling + en passant
    board: Board,
    active_color: piece.Color = piece.Color.White,

    pub fn init() Self {
        return Self.from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    }

    pub fn from_fen(fen_str: []const u8) Self {
        const state = fen.parse(fen_str);
        return Self{
            .board = state.board,
            .active_color = state.active_color,
        };
    }

    pub fn get_pos(self: Self, pos: Position) ?Piece {
        return self.board.get_pos(pos);
    }

    pub fn set_cell(self: *Self, pos: Position, maybe_piece: ?Piece) void {
        self.board.set_pos(pos, maybe_piece);
    }

    pub fn flip_active_color(self: *Self) void {
        self.active_color = switch (self.active_color) {
            piece.Color.White => piece.Color.Black,
            piece.Color.Black => piece.Color.White,
        };
    }

    pub fn make_move(self: *Self, move: Move) void {
        const start_peice = self.get_pos(move.start).?;

        const color = self.active_color;
        const color_idx = @intFromEnum(color);
        // TODO: assert move.kind is promotion if promotion_kind is set?
        const kind = move.promotion_kind orelse start_peice.kind;
        const move_piece = Piece{ .color = color, .kind = kind };

        self.set_cell(move.start, null);
        self.set_cell(move.end, move_piece);

        switch (move.kind) {
            piece.Kind.Pawn => {
                const start_rank = move.start.toRankFile().rank;
                const end_rank = move.end.toRankFile().rank;

                var dir: Dir = undefined;
                var rank_diff: u8 = undefined;
                if (start_rank > end_rank) {
                    dir = Dir.South;
                    rank_diff = start_rank - end_rank;
                } else {
                    dir = Dir.North;
                    rank_diff = end_rank - start_rank;
                }

                if (rank_diff == 2) {
                    self.board.enPassantPos = move.start.move_dir(dir);
                }

                if (move.move_flags.isSet(MoveType.EnPassant)) {
                    const captured_pos = move.end.move_dir(dir.opposite());
                    self.set_cell(captured_pos, null);
                }
            },
            piece.Kind.King => {
                self.board.castling_rights[color_idx].king_side = false;
                self.board.castling_rights[color_idx].queen_side = false;
                if (move.move_flags.isSet(MoveType.Castling)) {
                    const all_castling_info = precompute.CASTLING_INFO[color_idx];
                    const castling_info = all_castling_info.from_king_end(move.end).?;

                    self.set_cell(castling_info.rook_start, null);
                    self.set_cell(castling_info.rook_end, .{
                        .color = color,
                        .kind = piece.Kind.Rook,
                    });
                }
            },
            piece.Kind.Rook => {
                const start_file = move.start.toRankFile().file;
                if (start_file == 0) {
                    self.board.castling_rights[color_idx].queen_side = false;
                } else if (start_file == 7) {
                    self.board.castling_rights[color_idx].king_side = false;
                }
            },
            else => {},
        }
        self.flip_active_color();
    }

    /// given the position of a pinned piece, get the ray of the attack
    fn get_pin_attacker(self: Self, pin_pos: Position) BoardBitSet {
        const pin_piece = if (self.board.get_pos(pin_pos)) |p| p else return BoardBitSet.initEmpty();

        const color = pin_piece.color;

        const king_board = self.board.get_piece_set(Piece{ .color = color, .kind = piece.Kind.King });
        const king_square = king_board.bitScanForward();

        const enmey_queens = self.board.get_piece_set(Piece{ .color = color.get_enemy(), .kind = piece.Kind.Queen });

        for (0..NUM_DIRS) |dir_index| {
            var moves = precompute.RAYS[king_square][dir_index];

            const dir: Dir = @enumFromInt(dir_index);

            var on_ray = moves.intersectWith(self.board.occupied_set);
            if (on_ray.count() > 1) {
                const possible_pin = dir.first_hit_on_ray(on_ray);

                if (possible_pin != pin_pos.toIndex()) {
                    continue;
                }

                on_ray.unset(possible_pin);

                const possible_attacker = dir.first_hit_on_ray(on_ray);

                const kind = if (dir_index < 4) piece.Kind.Rook else piece.Kind.Bishop;
                const kind_board = self.board.get_piece_set(Piece{ .color = color.get_enemy(), .kind = kind });

                const all_valid_enemies = kind_board.unionWith(enmey_queens);

                if (all_valid_enemies.intersectWith(on_ray).isSet(possible_attacker)) {
                    return moves; // return entire ray from king
                }
            }
        }
        return BoardBitSet.initEmpty();
    }

    fn find_pinned_pieces(self: Self, color: piece.Color) BoardBitSet {
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

    fn get_sliding_moves(self: Self, p: piece.Piece, pos: Position) BoardBitSet {
        // TODO: debug assert pos has the piece?
        const start_idx = pos.toIndex();

        var attacks = BoardBitSet.initEmpty();

        // bishops should only look at the first 4 dirs, rooks the last 4, queens all of it
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

    fn castle_allowed(self: Self, color: piece.Color, attacked_sqaures: BoardBitSet, king_side: bool) bool {
        const castle_rights = self.board.castling_rights[@intFromEnum(color)];
        if (king_side and castle_rights.king_side == false) {
            return false;
        }
        if (!king_side and castle_rights.queen_side == false) {
            return false;
        }

        const all_castle_info = precompute.CASTLING_INFO[@intFromEnum(color)];

        const castle_info = if (king_side) all_castle_info.king_side else all_castle_info.queen_side;

        const king_idx = self.board.get_piece_set(Piece{ .color = color, .kind = piece.Kind.King }).bitScanForward();
        const dir = if (king_side) Dir.East else Dir.West;
        const ray = precompute.RAYS[king_idx][@intFromEnum(dir)];

        const moving_through = castle_info.sqaures_moving_through;

        if (moving_through.intersectWith(attacked_sqaures).bit_set.mask != 0) {
            return false;
        }

        const occupied_ray = ray.intersectWith(self.board.occupied_set);
        if (occupied_ray.bit_set.mask == 0) {
            return false;
        }

        const maybe_rook_idx = dir.first_hit_on_ray(occupied_ray);

        const rooks = self.board.get_piece_set(Piece{ .color = color, .kind = piece.Kind.Rook });

        return rooks.isSet(maybe_rook_idx);
    }

    fn get_all_attacked_sqaures(self: Self, color: piece.Color) BoardBitSet {
        const pinned_pieces = self.find_pinned_pieces(color);

        var attacks = BoardBitSet.initEmpty();

        const freinds = self.board.color_sets[@intFromEnum(color)];

        for (0..utils.enum_len(piece.Kind)) |kind_idx| {
            const kind: piece.Kind = @enumFromInt(kind_idx);
            const p = Piece{ .color = color, .kind = kind };
            const piece_set = self.board.get_piece_set(p).differenceWith(pinned_pieces);

            switch (kind) {
                piece.Kind.Pawn => {
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

    pub fn get_valid_moves(self: Self, allocator: Allocator, pos: Position) Allocator.Error!MoveList {
        // TODO: set capture flag on moves that need it...
        const start_idx = pos.toIndex();

        const maybe_peice = self.get_pos(pos);

        var moves = try MoveList.initCapacity(allocator, 27);

        const p = if (maybe_peice) |p| p else return moves;

        const pinned_pieces = self.find_pinned_pieces(p.color);

        const is_pinned = pinned_pieces.isSet(start_idx);

        const pin_ray = if (is_pinned) self.get_pin_attacker(pos) else BoardBitSet.initFull();

        const freinds = self.board.color_sets[@intFromEnum(p.color)];
        const enemy_color = p.color.get_enemy();

        const enemies = self.board.color_sets[@intFromEnum(enemy_color)];

        var possible_moves = switch (p.kind) {
            piece.Kind.Pawn => {
                const start_bs = BoardBitSet.initWithIndex(start_idx);
                const occupied = self.board.occupied_set;

                // TODO: handle promotion
                const non_captures = start_bs.pawnMoves(occupied.complement(), p.color).intersectWith(pin_ray);
                var non_captures_iter = non_captures.iterator();
                while (non_captures_iter.next()) |to| {
                    const end_rank = to.toRankFile().rank;
                    if (end_rank == 0 or end_rank == 7) {
                        for (PROMOTION_KINDS) |promotion_kind| {
                            const move_flags = MoveFlags.initWith(MoveType.Promotion);
                            moves.appendAssumeCapacity(.{
                                .start = pos,
                                .end = to,
                                .kind = p.kind,
                                .move_flags = move_flags,
                                .promotion_kind = promotion_kind,
                            });
                        }
                    } else {
                        moves.appendAssumeCapacity(.{ .start = pos, .end = to, .kind = p.kind, .move_flags = MoveFlags.init() });
                    }
                }

                var en_passant_board = BoardBitSet.initEmpty();
                if (self.board.enPassantPos) |ep| {
                    en_passant_board.set(ep.toIndex());
                }

                const possible_captures = start_bs.pawnAttacks(p.color, enemies.unionWith(en_passant_board)).intersectWith(pin_ray);
                var captures_iter = possible_captures.iterator();
                while (captures_iter.next()) |to| {
                    const end_rank = to.toRankFile().rank;
                    if (end_rank == 0 or end_rank == 7) {
                        for (PROMOTION_KINDS) |promotion_kind| {
                            const move_types = [2]MoveType{ MoveType.Promotion, MoveType.Capture };
                            const move_flags = MoveFlags.initWithSlice(&move_types);
                            const captured_kind = self.board.get_pos(to).?.kind;
                            moves.appendAssumeCapacity(.{
                                .start = pos,
                                .end = to,
                                .kind = p.kind,
                                .move_flags = move_flags,
                                .promotion_kind = promotion_kind,
                                .captured_kind = captured_kind,
                            });
                        }
                    } else {
                        const move_flags = MoveFlags.initWith(MoveType.Capture);

                        var move = Move{ .start = pos, .end = to, .kind = p.kind, .move_flags = move_flags };
                        if (self.board.get_pos(to)) |captured| {
                            move.captured_kind = captured.kind;
                        } else {
                            move.captured_kind = piece.Kind.Pawn;
                            move.move_flags.set(MoveType.EnPassant);
                        }

                        moves.appendAssumeCapacity(move);
                    }
                }

                return moves;
            },
            piece.Kind.Knight => precompute.KNIGHT_MOVES[start_idx].intersectWith(pin_ray).differenceWith(freinds),
            piece.Kind.King => blk: {
                const enemy_attacked_sqaures = self.get_all_attacked_sqaures(enemy_color);

                const king_moves = precompute.KING_MOVES[start_idx];

                if (self.castle_allowed(p.color, enemy_attacked_sqaures, true)) {
                    // king side castle
                    const end = Position.fromIndex(pos.index + 2);
                    const flags = MoveFlags.initWith(MoveType.Castling);
                    const move = Move{ .start = pos, .end = end, .kind = piece.Kind.King, .move_flags = flags };
                    moves.appendAssumeCapacity(move);
                }
                if (self.castle_allowed(p.color, enemy_attacked_sqaures, false)) {
                    // queen side castle
                    const end = Position.fromIndex(pos.index - 2);
                    const flags = MoveFlags.initWith(MoveType.Castling);
                    const move = Move{ .start = pos, .end = end, .kind = piece.Kind.King, .move_flags = flags };
                    moves.appendAssumeCapacity(move);
                }

                break :blk king_moves.differenceWith(freinds).differenceWith(enemy_attacked_sqaures);
            },
            piece.Kind.Bishop,
            piece.Kind.Queen,
            piece.Kind.Rook,
            => self.get_sliding_moves(p, pos).intersectWith(pin_ray),
        };

        possible_moves.remove(freinds);

        var move_iter = possible_moves.iterator();

        while (move_iter.next()) |to| {
            const maybe_capture = self.board.get_pos(pos);
            var captured_kind: ?piece.Kind = null;
            var flags = MoveFlags.init();
            if (maybe_capture) |capture| {
                captured_kind = capture.kind;
                flags.set(MoveType.Capture);
            }
            moves.appendAssumeCapacity(.{ .start = pos, .end = to, .kind = p.kind, .captured_kind = captured_kind, .move_flags = flags });
        }

        return moves;
    }
};
