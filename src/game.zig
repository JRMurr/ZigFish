const std = @import("std");
const utils = @import("utils.zig");

const board_types = @import("board.zig");
const Board = board_types.Board;
const Position = board_types.Position;
const Move = board_types.Move;
const MoveType = board_types.MoveType;
const MoveFlags = board_types.MoveFlags;
const BoardMeta = board_types.BoardMeta;

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

// pub const MoveHistory = struct {
//     move: Move,
//     meta: BoardMeta,
// };

const HistoryStack = std.ArrayList(BoardMeta);

const PinInfo = struct {
    // pieces pinned to the king
    pinned_pieces: BoardBitSet,
    // if king is attacked, the ray of the empty squares blockers can move into
    king_attack_ray: ?BoardBitSet,
};

const AttackedSqaureInfo = struct {
    attacked_sqaures: BoardBitSet,
    king_attackers: BoardBitSet,
};

const MoveGenInfo = struct {
    pinned_pieces: BoardBitSet,
    king_attackers: BoardBitSet,
    king_attack_ray: ?BoardBitSet,
    enemy_attacked_sqaures: BoardBitSet,
};

pub const GameManager = struct {
    const Self = @This();

    board: Board,
    history: HistoryStack,

    pub fn init(allocator: Allocator) Allocator.Error!Self {
        return Self.from_fen(allocator, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    }

    pub fn deinit(self: Self) void {
        self.history.deinit();
    }

    pub fn from_fen(allocator: Allocator, fen_str: []const u8) Allocator.Error!Self {
        const board = fen.parse(fen_str);
        const history = try HistoryStack.initCapacity(allocator, 30);
        return Self{ .board = board, .history = history };
    }

    pub fn getPos(self: Self, pos: Position) ?Piece {
        return self.board.getPos(pos);
    }

    pub fn setPos(self: *Self, pos: Position, maybe_piece: ?Piece) void {
        self.board.setPos(pos, maybe_piece);
    }

    pub fn makeMove(self: *Self, move: Move) Allocator.Error!void {
        try self.history.append(self.board.meta);
        self.board.makeMove(move);
    }

    pub fn unMakeMove(self: *Self, move: Move) void {
        const meta = self.history.pop();
        self.board.unMakeMove(move, meta);
    }

    /// given the position of a pinned piece, get the ray of the attack
    fn get_pin_attacker(self: Self, pin_pos: Position, ignore_sqaures: BoardBitSet) BoardBitSet {
        const pin_piece = if (self.board.getPos(pin_pos)) |p| p else return BoardBitSet.initEmpty();

        const color = pin_piece.color;

        const king_board = self.board.getPieceSet(Piece{ .color = color, .kind = piece.Kind.King });
        const king_square = king_board.bitScanForward();

        const enmey_queens = self.board.getPieceSet(Piece{ .color = color.get_enemy(), .kind = piece.Kind.Queen });

        for (0..NUM_DIRS) |dir_index| {
            var moves = precompute.RAYS[king_square][dir_index];

            const dir: Dir = @enumFromInt(dir_index);

            var on_ray = moves.intersectWith(self.board.occupied_set.differenceWith(ignore_sqaures));
            if (on_ray.count() > 1) {
                const possible_pin = dir.first_hit_on_ray(on_ray);

                if (possible_pin != pin_pos.toIndex()) {
                    continue;
                }

                on_ray.unset(possible_pin);

                const possible_attacker = dir.first_hit_on_ray(on_ray);

                const kind = if (dir_index < 4) piece.Kind.Rook else piece.Kind.Bishop;
                const kind_board = self.board.getPieceSet(Piece{ .color = color.get_enemy(), .kind = kind });

                const all_valid_enemies = kind_board.unionWith(enmey_queens);

                if (all_valid_enemies.intersectWith(on_ray).isSet(possible_attacker)) {
                    return moves; // return entire ray from king
                }
            }
        }
        return BoardBitSet.initEmpty();
    }

    fn find_pinned_pieces(self: Self, color: piece.Color) PinInfo {
        const king_board = self.board.getPieceSet(Piece{ .color = color, .kind = piece.Kind.King });
        const king_square = king_board.bitScanForward();

        const enmey_queens = self.board.getPieceSet(Piece{ .color = color.get_enemy(), .kind = piece.Kind.Queen });

        var pinned = BoardBitSet.initEmpty();

        var king_attack_ray: ?BoardBitSet = null;

        for (0..NUM_DIRS) |dir_index| {
            var moves = precompute.RAYS[king_square][dir_index];

            const dir: Dir = @enumFromInt(dir_index);

            var on_ray = moves.intersectWith(self.board.occupied_set);
            if (on_ray.count() >= 1) {
                const kind = if (dir_index < 4) piece.Kind.Rook else piece.Kind.Bishop;
                const kind_board = self.board.getPieceSet(Piece{ .color = color.get_enemy(), .kind = kind });

                const all_valid_enemies = kind_board.unionWith(enmey_queens);

                const first_seen_on_ray = dir.first_hit_on_ray(on_ray);

                if (all_valid_enemies.isSet(first_seen_on_ray)) {
                    // direct attack on king
                    king_attack_ray = moves.differenceWith(precompute.RAYS[first_seen_on_ray][dir_index]);
                    continue;
                } else if (!self.board.color_sets[@intFromEnum(color)].isSet(first_seen_on_ray)) {
                    // either is an enemy piece that doesnt matter or a friend
                    continue;
                }

                on_ray.unset(first_seen_on_ray);

                if (on_ray.count() == 0) {
                    continue;
                }

                const possible_attacker = dir.first_hit_on_ray(on_ray);

                if (all_valid_enemies.intersectWith(on_ray).isSet(possible_attacker)) {
                    pinned.set(first_seen_on_ray);
                }
            }
        }
        return .{ .pinned_pieces = pinned, .king_attack_ray = king_attack_ray };
    }

    fn slidingMoves(self: Self, p: piece.Piece, pos: Position, ignore_sqaures: BoardBitSet) BoardBitSet {
        // TODO: debug assert pos has the piece?
        const start_idx = pos.toIndex();

        var attacks = BoardBitSet.initEmpty();

        // bishops should only look at the first 4 dirs, rooks the last 4, queens all of it
        const dir_start: u8 = if (p.is_bishop()) 4 else 0;
        const dir_end: u8 = if (p.is_rook()) 4 else 8;
        for (dir_start..dir_end) |dirIndex| {
            var moves = precompute.RAYS[start_idx][dirIndex];

            const dir: Dir = @enumFromInt(dirIndex);

            const blocker = moves.intersectWith(self.board.occupied_set.differenceWith(ignore_sqaures));
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
        const castle_rights = self.board.meta.castling_rights[@intFromEnum(color)];
        if (king_side and castle_rights.king_side == false) {
            return false;
        }
        if (!king_side and castle_rights.queen_side == false) {
            return false;
        }

        const all_castle_info = precompute.CASTLING_INFO[@intFromEnum(color)];

        const castle_info = if (king_side) all_castle_info.king_side else all_castle_info.queen_side;

        const king_idx = self.board.getPieceSet(Piece{ .color = color, .kind = piece.Kind.King }).bitScanForward();
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

        const rooks = self.board.getPieceSet(Piece{ .color = color, .kind = piece.Kind.Rook });

        return rooks.isSet(maybe_rook_idx);
    }

    pub fn allAttackedSqaures(self: Self, color: piece.Color) AttackedSqaureInfo {
        var attacks = BoardBitSet.initEmpty();

        const king_board = self.board.getPieceSet(Piece{ .color = color.get_enemy(), .kind = piece.Kind.King });
        const king_square = king_board.bitScanForward();

        var king_attackers = BoardBitSet.initEmpty();

        for (0..utils.enum_len(piece.Kind)) |kind_idx| {
            const kind: piece.Kind = @enumFromInt(kind_idx);
            const p = Piece{ .color = color, .kind = kind };
            const piece_set = self.board.getPieceSet(p);

            switch (kind) {
                piece.Kind.Pawn => {
                    // const enemies = self.board.color_sets[@intFromEnum(color.get_enemy())];
                    const pawn_attacks = piece_set.pawnAttacks(color, null);
                    if (pawn_attacks.isSet(king_square)) {
                        // treat the enemey king as an enemy pawn
                        // any sqaure it "attacks" that is a freindly is "our" pawn attacking the enemy
                        const freindly_pawn_attacking_king = king_board.pawnAttacks(color.get_enemy(), piece_set);
                        king_attackers.toggleSet(freindly_pawn_attacking_king);
                    }
                    // pawn_attacks.debug();
                    attacks.setUnion(pawn_attacks);
                },
                piece.Kind.Knight => {
                    const knight_attacks = piece_set.knightMoves();
                    if (knight_attacks.isSet(king_square)) {
                        const attacking_knights = precompute.KNIGHT_MOVES[king_square].intersectWith(piece_set);
                        king_attackers.toggleSet(attacking_knights);
                    }
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
                    var iter = piece_set.iterator();
                    while (iter.next()) |pos| {
                        // ignore king when calculating sliding moves so he wont be able to walk along an attack line
                        const moves = self.slidingMoves(p, pos, king_board);
                        if (moves.isSet(king_square)) {
                            king_attackers.set(pos.toIndex());
                        }
                        slide_attacks.setUnion(moves);
                    }
                    // slide_attacks.debug();
                    attacks.setUnion(slide_attacks);
                },
            }
        }

        return .{
            .king_attackers = king_attackers,
            .attacked_sqaures = attacks,
        };
    }

    pub fn getAllValidMoves(self: Self, move_allocator: Allocator) Allocator.Error!MoveList {
        const color = self.board.active_color;

        const pin_info = self.find_pinned_pieces(color);
        const attack_info = self.allAttackedSqaures(color.get_enemy());

        const gen_info = MoveGenInfo{
            .pinned_pieces = pin_info.pinned_pieces,
            .king_attack_ray = pin_info.king_attack_ray,
            .enemy_attacked_sqaures = attack_info.attacked_sqaures,
            .king_attackers = attack_info.king_attackers,
        };

        var moves = MoveList.init(move_allocator);

        const color_set = self.board.color_sets[@intFromEnum(color)];
        var color_iter = color_set.iterator();
        while (color_iter.next()) |pos| {
            const p = self.getPos(pos).?;

            try self.get_valid_moves(&moves, &gen_info, pos, p);
        }

        return moves;
    }

    fn get_valid_moves(self: Self, out_moves: *MoveList, gen_info: *const MoveGenInfo, pos: Position, p: Piece) Allocator.Error!void {
        if (gen_info.king_attackers.count() >= 2 and !p.is_king()) {
            // if there are 2 or more direct attacks on the king, only it can move
            return;
        }

        try out_moves.ensureUnusedCapacity(27); // TODO: better number based on piece type...
        const start_idx = pos.toIndex();
        const pinned_pieces = gen_info.pinned_pieces;
        const is_pinned = pinned_pieces.isSet(start_idx);
        const pin_ray = if (is_pinned) self.get_pin_attacker(pos, BoardBitSet.initEmpty()) else BoardBitSet.initFull();
        const remove_check_sqaures = if (gen_info.king_attack_ray) |attack_ray|
            attack_ray.unionWith(gen_info.king_attackers)
        else blk: {
            break :blk if (gen_info.king_attackers.count() >= 1) gen_info.king_attackers else BoardBitSet.initFull();
        };

        const allowed_sqaures = pin_ray.intersectWith(remove_check_sqaures);

        const freinds = self.board.color_sets[@intFromEnum(p.color)];
        const enemy_color = p.color.get_enemy();

        const enemies = self.board.color_sets[@intFromEnum(enemy_color)];

        var possible_moves = switch (p.kind) {
            piece.Kind.Pawn => {
                const start_bs = BoardBitSet.initWithIndex(start_idx);
                const occupied = self.board.occupied_set;

                const non_captures = start_bs.pawnMoves(occupied.complement(), p.color).intersectWith(allowed_sqaures);
                var non_captures_iter = non_captures.iterator();
                while (non_captures_iter.next()) |to| {
                    const end_rank = to.toRankFile().rank;
                    if (end_rank == 0 or end_rank == 7) {
                        for (PROMOTION_KINDS) |promotion_kind| {
                            const move_flags = MoveFlags.initOne(MoveType.Promotion);
                            out_moves.appendAssumeCapacity(.{
                                .start = pos,
                                .end = to,
                                .kind = p.kind,
                                .move_flags = move_flags,
                                .promotion_kind = promotion_kind,
                            });
                        }
                    } else {
                        out_moves.appendAssumeCapacity(.{ .start = pos, .end = to, .kind = p.kind, .move_flags = MoveFlags.initEmpty() });
                    }
                }

                var en_passant_board = BoardBitSet.initEmpty();
                if (self.board.meta.en_passant_pos) |ep| {
                    en_passant_board.set(ep.toIndex());
                }

                const possible_captures = start_bs.pawnAttacks(p.color, enemies.unionWith(en_passant_board)).intersectWith(allowed_sqaures);
                var captures_iter = possible_captures.iterator();

                while (captures_iter.next()) |to| {
                    const end_rank = to.toRankFile().rank;
                    if (end_rank == 0 or end_rank == 7) {
                        for (PROMOTION_KINDS) |promotion_kind| {
                            const move_flags = MoveFlags.initMany(&[_]MoveType{ MoveType.Promotion, MoveType.Capture });
                            const captured_kind = self.board.getPos(to).?.kind;
                            out_moves.appendAssumeCapacity(.{
                                .start = pos,
                                .end = to,
                                .kind = p.kind,
                                .move_flags = move_flags,
                                .promotion_kind = promotion_kind,
                                .captured_kind = captured_kind,
                            });
                        }
                    } else {
                        const move_flags = MoveFlags.initOne(MoveType.Capture);

                        var move = Move{ .start = pos, .end = to, .kind = p.kind, .move_flags = move_flags };
                        if (self.board.getPos(to)) |captured| {
                            move.captured_kind = captured.kind;
                        } else {
                            const ep_pos = self.board.meta.en_passant_pos.?;

                            const to_capture = if (enemy_color == piece.Color.Black) ep_pos.move_dir(Dir.South) else ep_pos.move_dir(Dir.North);

                            const is_pinned_ignoring_capture = self.get_pin_attacker(pos, BoardBitSet.initWithPos(to_capture));
                            if (is_pinned_ignoring_capture.count() > 0) {
                                // if we took the ep pawn there would be no defender of the king
                                continue;
                            }

                            move.captured_kind = piece.Kind.Pawn;
                            move.move_flags.setPresent(MoveType.EnPassant, true);
                        }

                        out_moves.appendAssumeCapacity(move);
                    }
                }

                return;
            },
            piece.Kind.Knight => precompute.KNIGHT_MOVES[start_idx].intersectWith(allowed_sqaures).differenceWith(freinds),
            piece.Kind.King => blk: {
                const enemy_attacked_sqaures = gen_info.enemy_attacked_sqaures;

                const king_moves = precompute.KING_MOVES[start_idx];

                if (self.castle_allowed(p.color, enemy_attacked_sqaures, true)) {
                    // king side castle
                    const end = Position.fromIndex(pos.index + 2);
                    const flags = MoveFlags.initOne(MoveType.Castling);
                    const move = Move{ .start = pos, .end = end, .kind = piece.Kind.King, .move_flags = flags };
                    out_moves.appendAssumeCapacity(move);
                }
                if (self.castle_allowed(p.color, enemy_attacked_sqaures, false)) {
                    // queen side castle
                    const end = Position.fromIndex(pos.index - 2);
                    const flags = MoveFlags.initOne(MoveType.Castling);
                    const move = Move{ .start = pos, .end = end, .kind = piece.Kind.King, .move_flags = flags };
                    out_moves.appendAssumeCapacity(move);
                }

                break :blk king_moves.differenceWith(freinds).differenceWith(enemy_attacked_sqaures);
            },
            piece.Kind.Bishop,
            piece.Kind.Queen,
            piece.Kind.Rook,
            => self.slidingMoves(p, pos, BoardBitSet.initEmpty()).intersectWith(allowed_sqaures),
        };

        possible_moves.remove(freinds);

        var move_iter = possible_moves.iterator();

        while (move_iter.next()) |to| {
            const maybe_capture = self.board.getPos(to);
            var captured_kind: ?piece.Kind = null;
            var flags = MoveFlags.initEmpty();
            if (maybe_capture) |capture| {
                captured_kind = capture.kind;
                flags.setPresent(MoveType.Capture, true);
            }
            out_moves.appendAssumeCapacity(.{ .start = pos, .end = to, .kind = p.kind, .captured_kind = captured_kind, .move_flags = flags });
        }
    }

    pub fn get_valid_moves_at_pos(self: Self, move_allocator: Allocator, pos: Position) Allocator.Error!MoveList {
        const maybe_peice = self.getPos(pos);

        var moves = MoveList.init(move_allocator);

        const p = if (maybe_peice) |p| p else return moves;

        const pin_info = self.find_pinned_pieces(p.color);
        const attack_info = self.allAttackedSqaures(p.color.get_enemy());

        const gen_info = MoveGenInfo{
            .pinned_pieces = pin_info.pinned_pieces,
            .king_attack_ray = pin_info.king_attack_ray,
            .enemy_attacked_sqaures = attack_info.attacked_sqaures,
            .king_attackers = attack_info.king_attackers,
        };

        try self.get_valid_moves(&moves, &gen_info, pos, p);

        return moves;
    }

    // https://www.chessprogramming.org/Perft
    pub fn perft(self: *Self, depth: usize, move_allocator: Allocator, print_count_per_move: bool) Allocator.Error!usize {
        var nodes: usize = 0;
        if (depth == 0) {
            return 1;
        }

        const moves = try self.getAllValidMoves(move_allocator);
        defer moves.deinit();

        if (depth == 1 and !print_count_per_move) {
            // dont need to actually make these last ones
            return moves.items.len;
        }

        for (moves.items) |move| {
            try self.makeMove(move);
            const num_leafs = try self.perft(depth - 1, move_allocator, false);
            if (print_count_per_move) {
                std.debug.print("{s}: {d}\n", .{ move.toStrSimple(), num_leafs });
            }
            nodes += num_leafs;
            self.unMakeMove(move);
        }

        return nodes;
    }
};

test "perft base" {
    var game = try GameManager.init(std.testing.allocator);
    defer game.deinit();

    const perf = try game.perft(3, std.testing.allocator, false);

    try std.testing.expectEqual(8_902, perf);
}

test "perft pos 4" {
    var game = try GameManager.from_fen(std.testing.allocator, "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8");
    defer game.deinit();

    try std.testing.expectEqual(62_379, try game.perft(3, std.testing.allocator, false));
}

test "perft pos 5 depth 3" {
    var game = try GameManager.from_fen(std.testing.allocator, "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8");
    defer game.deinit();

    try std.testing.expectEqual(62_379, try game.perft(3, std.testing.allocator, false));
}

test "perft pos 5 depth 5" {
    var game = try GameManager.from_fen(std.testing.allocator, "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8");
    defer game.deinit();

    try std.testing.expectEqual(89_941_194, try game.perft(5, std.testing.allocator, false));
}
