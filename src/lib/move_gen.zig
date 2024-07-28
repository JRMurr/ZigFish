const std = @import("std");
const builtin = @import("builtin");
const utils = ZigFish.Utils;

const Allocator = std.mem.Allocator;

const ZigFish = @import("root.zig");
const Board = ZigFish.Board;
const Position = ZigFish.Position;
const BoardMeta = ZigFish.BoardMeta;
const MoveList = ZigFish.MoveList;

const Move = ZigFish.Move;
const MoveType = ZigFish.MoveType;
const MoveFlags = ZigFish.MoveFlags;

const BoardBitSet = ZigFish.BoardBitSet;
const Dir = ZigFish.Dir;

const Piece = ZigFish.Piece;
const Color = Piece.Color;
const Kind = Piece.Kind;

const precompute = ZigFish.Precompute;
const Score = precompute.Score;

const PinInfo = struct {
    // pieces pinned to the king
    pinned_pieces: BoardBitSet,
    // if king is attacked, the ray of the empty squares blockers can move into
    king_attack_ray: ?BoardBitSet,
};

const NUM_KINDS = utils.enumLen(Kind);

const AttackedSqaureInfo = struct {
    attackers: [NUM_KINDS]BoardBitSet,
    attacked_sqaures: BoardBitSet,
    king_attackers: BoardBitSet,
};

pub const MoveGenInfo = struct {
    pinned_pieces: BoardBitSet,
    king_attack_ray: ?BoardBitSet,
    attack_info: AttackedSqaureInfo,
};

// pub const MoveList = std.ArrayList(Move);

pub const GeneratedMoves = struct { moves: MoveList, gen_info: MoveGenInfo };

const NUM_DIRS = utils.enumLen(Dir);

const PROMOTION_KINDS = [4]Kind{ Kind.Queen, Kind.Knight, Kind.Bishop, Kind.Rook };

const Self = @This();
pub const MoveGen = Self;

board: *const Board,

pub fn init(allocator: Allocator, board: *const Board) !*MoveGen {
    const move_gen = try allocator.create(MoveGen);
    move_gen.* = MoveGen{ .board = board };
    return move_gen;
}

/// given the position of a pinned piece, get the ray of the attack
pub fn pinAttacker(self: *const Self, pin_pos: Position, ignore_sqaures: BoardBitSet) BoardBitSet {
    const pin_piece = if (self.board.getPos(pin_pos)) |p| p else return BoardBitSet.initEmpty();

    const color = pin_piece.color;

    const king_board = self.board.getPieceSet(Piece{ .color = color, .kind = Kind.King });
    const king_square = king_board.bitScanForward();

    const enmey_queens = self.board.getPieceSet(Piece{ .color = color.get_enemy(), .kind = Kind.Queen });

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

            const kind = if (dir_index < 4) Kind.Rook else Kind.Bishop;
            const kind_board = self.board.getPieceSet(Piece{ .color = color.get_enemy(), .kind = kind });

            const all_valid_enemies = kind_board.unionWith(enmey_queens);

            if (all_valid_enemies.intersectWith(on_ray).isSet(possible_attacker)) {
                return moves; // return entire ray from king
            }
        }
    }
    return BoardBitSet.initEmpty();
}

pub fn findPinnedPieces(self: *const Self, color: Color) PinInfo {
    const king_board = self.board.getPieceSet(Piece{ .color = color, .kind = Kind.King });
    const king_square = king_board.bitScanForward();

    const enmey_queens = self.board.getPieceSet(Piece{ .color = color.get_enemy(), .kind = Kind.Queen });

    var pinned = BoardBitSet.initEmpty();

    var king_attack_ray: ?BoardBitSet = null;

    for (0..NUM_DIRS) |dir_index| {
        var moves = precompute.RAYS[king_square][dir_index];

        const dir: Dir = @enumFromInt(dir_index);

        var on_ray = moves.intersectWith(self.board.occupied_set);
        if (on_ray.count() >= 1) {
            const kind = if (dir_index < 4) Kind.Rook else Kind.Bishop;
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

pub fn slidingMoves(board: *const Board, p: Piece, pos: Position, ignore_sqaures: BoardBitSet) BoardBitSet {
    // TODO: debug assert pos has the piece?
    const start_idx = pos.toIndex();

    var attacks = BoardBitSet.initEmpty();

    // bishops should only look at the first 4 dirs, rooks the last 4, queens all of it
    const dir_start: u8 = if (p.is_bishop()) 4 else 0;
    const dir_end: u8 = if (p.is_rook()) 4 else 8;
    for (dir_start..dir_end) |dirIndex| {
        var moves = precompute.RAYS[start_idx][dirIndex];

        const dir: Dir = @enumFromInt(dirIndex);

        const blocker = moves.intersectWith(board.occupied_set.differenceWith(ignore_sqaures));
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

pub fn castleAllowed(self: *const Self, color: Color, attacked_sqaures: BoardBitSet, king_side: bool) bool {
    const castle_rights = self.board.meta.castling_rights[@intFromEnum(color)];
    if (king_side and castle_rights.king_side == false) {
        return false;
    }
    if (!king_side and castle_rights.queen_side == false) {
        return false;
    }

    const all_castle_info = precompute.CASTLING_INFO[@intFromEnum(color)];

    const castle_info = if (king_side) all_castle_info.king_side else all_castle_info.queen_side;

    const king_idx = self.board.getPieceSet(Piece{ .color = color, .kind = Kind.King }).bitScanForward();
    const dir = if (king_side) Dir.East else Dir.West;
    const ray = precompute.RAYS[king_idx][@intFromEnum(dir)];

    const moving_through = castle_info.sqaures_moving_through;

    if (moving_through.intersectWith(attacked_sqaures).bit_set.mask != 0) {
        return false;
    }

    const occupied_ray = ray.intersectWith(self.board.occupied_set);

    // occupied_ray.debug();

    // should only hit rook
    const rook_idx = castle_info.rook_start.toIndex();
    const valid_set = BoardBitSet.initWithIndex(rook_idx);
    if (!occupied_ray.eql(valid_set)) {
        return false;
    }

    const rooks = self.board.getPieceSet(Piece{ .color = color, .kind = Kind.Rook });
    return rooks.isSet(rook_idx);
}

pub fn allAttackedSqaures(board: *const Board) AttackedSqaureInfo {
    var attackInfo: AttackedSqaureInfo = undefined;
    var attacks = BoardBitSet.initEmpty();

    const color = board.active_color.get_enemy();

    const king_board = board.getPieceSet(Piece{ .color = board.active_color, .kind = Kind.King });
    const king_square = king_board.bitScanForward();

    var king_attackers = BoardBitSet.initEmpty();

    for (0..NUM_KINDS) |kind_idx| {
        const kind: Kind = @enumFromInt(kind_idx);
        const p = Piece{ .color = color, .kind = kind };
        const piece_set = board.getPieceSet(p);

        switch (kind) {
            Kind.Pawn => {
                // const enemies = self.board.color_sets[@intFromEnum(color.get_enemy())];
                const pawn_attacks = piece_set.pawnAttacks(color, null);
                if (pawn_attacks.isSet(king_square)) {
                    // treat the enemey king as an enemy pawn
                    // any sqaure it "attacks" that is a freindly is "our" pawn attacking the enemy
                    const freindly_pawn_attacking_king = king_board.pawnAttacks(color.get_enemy(), piece_set);
                    king_attackers.toggleSet(freindly_pawn_attacking_king);
                }
                attackInfo.attackers[kind_idx] = pawn_attacks;
                // pawn_attacks.debug();
                attacks.setUnion(pawn_attacks);
            },
            Kind.Knight => {
                const knight_attacks = piece_set.knightMoves();
                if (knight_attacks.isSet(king_square)) {
                    const attacking_knights = precompute.KNIGHT_MOVES[king_square].intersectWith(piece_set);
                    king_attackers.toggleSet(attacking_knights);
                }
                attackInfo.attackers[kind_idx] = knight_attacks;
                // knight_attacks.debug();
                attacks.setUnion(knight_attacks);
            },
            Kind.King => {
                const king_attacks = piece_set.kingMoves();
                // king_attacks.debug();
                attackInfo.attackers[kind_idx] = king_attacks;
                attacks.setUnion(king_attacks);
            },
            Kind.Bishop, Kind.Queen, Kind.Rook => {
                var slide_attacks = BoardBitSet.initEmpty();
                var iter = piece_set.iterator();
                while (iter.next()) |pos| {
                    // ignore king when calculating sliding moves so he wont be able to walk along an attack line
                    const moves = slidingMoves(board, p, pos, king_board);
                    if (moves.isSet(king_square)) {
                        king_attackers.set(pos.toIndex());
                    }
                    slide_attacks.setUnion(moves);
                }
                attackInfo.attackers[kind_idx] = slide_attacks;
                // slide_attacks.debug();
                attacks.setUnion(slide_attacks);
            },
        }
    }
    attackInfo.king_attackers = king_attackers;
    attackInfo.attacked_sqaures = attacks;
    return attackInfo;
}

pub fn getGenInfo(self: *const Self) MoveGenInfo {
    const color = self.board.active_color;

    const pin_info = self.findPinnedPieces(color);
    const attack_info = allAttackedSqaures(self.board);

    const gen_info = MoveGenInfo{
        .pinned_pieces = pin_info.pinned_pieces,
        .king_attack_ray = pin_info.king_attack_ray,
        .attack_info = attack_info,
    };

    return gen_info;
}

pub fn getAllValidMoves(self: *const Self, comptime captures_only: bool) GeneratedMoves {
    const color = self.board.active_color;

    const gen_info = self.getGenInfo();

    var moves = MoveList.init();

    const color_set = self.board.color_sets[@intFromEnum(color)];
    // std.log.debug("board: {}", .{self.board});
    var color_iter = color_set.iterator();
    while (color_iter.next()) |pos| {
        // std.log.debug("pos: {s}", .{pos.toStr()});
        const p = self.board.getPos(pos) orelse {
            std.debug.panic("Position not set when iterating over color set: {}", .{pos});
        };

        self.getValidMoves(&moves, &gen_info, pos, p, captures_only);
    }

    return .{ .moves = moves, .gen_info = gen_info };
}

pub fn getValidMoves(
    self: *const Self,
    out_moves: *MoveList,
    gen_info: *const MoveGenInfo,
    pos: Position,
    p: Piece,
    comptime captures_only: bool,
) void {
    const attack_info = gen_info.attack_info;

    if (attack_info.king_attackers.count() >= 2 and !p.is_king()) {
        // if there are 2 or more direct attacks on the king, only it can move
        return;
    }

    const start_idx = pos.toIndex();
    const pinned_pieces = gen_info.pinned_pieces;
    const is_pinned = pinned_pieces.isSet(start_idx);
    const pin_ray = if (is_pinned) self.pinAttacker(pos, BoardBitSet.initEmpty()) else BoardBitSet.initFull();
    const remove_check_sqaures = if (gen_info.king_attack_ray) |attack_ray|
        attack_ray.unionWith(attack_info.king_attackers)
    else blk: {
        break :blk if (attack_info.king_attackers.count() >= 1) attack_info.king_attackers else BoardBitSet.initFull();
    };

    const allowed_sqaures = pin_ray.intersectWith(remove_check_sqaures);

    const freinds = self.board.color_sets[@intFromEnum(p.color)];
    const enemy_color = p.color.get_enemy();

    const enemies = self.board.color_sets[@intFromEnum(enemy_color)];

    const occupied = self.board.occupied_set;

    var possible_moves = switch (p.kind) {
        Kind.Pawn => blk: {
            const start_bs = BoardBitSet.initWithIndex(start_idx);

            if (!captures_only) {
                const non_captures = start_bs.pawnMoves(occupied.complement(), p.color).intersectWith(allowed_sqaures);
                var non_captures_iter = non_captures.iterator();
                while (non_captures_iter.next()) |to| {
                    const end_rank = to.toRankFile().rank;
                    if (end_rank == 0 or end_rank == 7) {
                        for (PROMOTION_KINDS) |promotion_kind| {
                            const move_flags = MoveFlags.initOne(MoveType.Promotion);
                            out_moves.append(Move{
                                .start = pos,
                                .end = to,
                                .kind = p.kind,
                                .move_flags = move_flags,
                                .promotion_kind = promotion_kind,
                            });
                        }
                    } else {
                        out_moves.append(Move{
                            .start = pos,
                            .end = to,
                            .kind = p.kind,
                            .move_flags = MoveFlags.initEmpty(),
                        });
                    }
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
                        out_moves.append(Move{
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

                        const to_capture = if (enemy_color == Color.Black) ep_pos.move_dir(Dir.South) else ep_pos.move_dir(Dir.North);

                        const is_pinned_ignoring_capture = self.pinAttacker(pos, BoardBitSet.initWithPos(to_capture));
                        if (is_pinned_ignoring_capture.count() > 0) {
                            // if we took the ep pawn there would be no defender of the king
                            continue;
                        }

                        move.captured_kind = Kind.Pawn;
                        move.move_flags.setPresent(MoveType.EnPassant, true);
                    }

                    out_moves.append(move);
                }
            }

            break :blk BoardBitSet.initEmpty();
        },
        Kind.Knight => precompute.KNIGHT_MOVES[start_idx].intersectWith(allowed_sqaures).differenceWith(freinds),
        Kind.King => blk: {
            const enemy_attacked_sqaures = gen_info.attack_info.attacked_sqaures;

            const king_moves = precompute.KING_MOVES[start_idx];

            if (!captures_only and self.castleAllowed(p.color, enemy_attacked_sqaures, true)) {
                // king side castle
                const end = Position.fromIndex(pos.index + 2);
                const flags = MoveFlags.initOne(MoveType.Castling);
                const move = Move{ .start = pos, .end = end, .kind = Kind.King, .move_flags = flags };
                out_moves.append(move);
            }
            if (!captures_only and self.castleAllowed(p.color, enemy_attacked_sqaures, false)) {
                // queen side castle
                const end = Position.fromIndex(pos.index - 2);
                const flags = MoveFlags.initOne(MoveType.Castling);
                const move = Move{ .start = pos, .end = end, .kind = Kind.King, .move_flags = flags };
                out_moves.append(move);
            }

            break :blk king_moves.differenceWith(freinds).differenceWith(enemy_attacked_sqaures);
        },
        Kind.Bishop,
        Kind.Queen,
        Kind.Rook,
        => slidingMoves(self.board, p, pos, BoardBitSet.initEmpty()).intersectWith(allowed_sqaures),
    };

    possible_moves.remove(freinds);
    if (captures_only) {
        possible_moves.remove(occupied.complement());
    }

    var move_iter = possible_moves.iterator();

    while (move_iter.next()) |to| {
        const maybe_capture = self.board.getPos(to);
        var captured_kind: ?Kind = null;
        var flags = MoveFlags.initEmpty();
        if (maybe_capture) |capture| {
            captured_kind = capture.kind;
            flags.setPresent(MoveType.Capture, true);
        } else if (captures_only) {
            continue;
        }
        out_moves.append(Move{ .start = pos, .end = to, .kind = p.kind, .captured_kind = captured_kind, .move_flags = flags });
    }
}

test {
    std.testing.refAllDecls(@This());
}
