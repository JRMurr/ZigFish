const std = @import("std");

const ZigFish = @import("root.zig");
const ZHashing = ZigFish.Zhasing;
const Precompute = ZigFish.Precompute;
const Bitset = ZigFish.BitSet;
const Move = ZigFish.Move;
const MoveType = ZigFish.MoveType;
const Piece = ZigFish.Piece;
const Color = Piece.Color;
const Kind = Piece.Kind;
const Position = ZigFish.Position;

const Dir = Bitset.Dir;
const BoardBitSet = ZigFish.BoardBitSet;

pub const CastlingRights = struct {
    queen_side: bool,
    king_side: bool,

    pub fn initNone() CastlingRights {
        return .{ .queen_side = false, .king_side = false };
    }

    pub fn canCastle(self: CastlingRights) bool {
        return self.queen_side or self.king_side;
    }

    pub fn toStr(self: CastlingRights) []const u8 {
        if (self.queen_side and self.king_side) {
            return "KQ";
        }
        if (self.king_side) {
            return "K";
        }
        if (self.queen_side) {
            return "Q";
        }
        return "-";
    }
};

const NUM_KINDS = ZigFish.Utils.enumLen(ZigFish.Kind);
const NUM_COLOR = ZigFish.Utils.enumLen(ZigFish.Color);

/// Metadata about the board that is irreversible
/// Need to store copies of this for move unmaking
pub const BoardMeta = struct {
    castling_rights: [NUM_COLOR]CastlingRights,
    half_moves: usize,
    en_passant_pos: ?Position,

    pub fn init() BoardMeta {
        var castling_rights: [NUM_COLOR]CastlingRights = undefined;

        for (0..NUM_COLOR) |i| {
            castling_rights[i] = CastlingRights.initNone();
        }

        return BoardMeta{
            .castling_rights = castling_rights,
            .half_moves = 0,
            .en_passant_pos = null,
        };
    }

    pub fn clone(self: BoardMeta) BoardMeta {
        var res = BoardMeta{
            .half_moves = self.half_moves,
            .en_passant_pos = self.en_passant_pos,
            .castling_rights = undefined,
        };

        @memcpy(res.castling_rights[0..NUM_COLOR], self.castling_rights[0..NUM_COLOR]);

        return res;
    }
};

fn get_diff_dir(move: *const Move) std.meta.Tuple(&.{ u8, Dir }) {
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

    return .{ rank_diff, dir };
}

const HASHER = ZHashing.ZHASHER;

pub const Board = struct {
    const Self = @This();
    kind_sets: [NUM_KINDS]BoardBitSet,
    color_sets: [NUM_COLOR]BoardBitSet,
    /// redundant set for easy check if a square is occupied
    occupied_set: BoardBitSet,

    active_color: ZigFish.Color = ZigFish.Color.White,
    full_moves: usize = 0,

    meta: BoardMeta,

    zhash: u64 = 0,

    pub fn init() Self {
        var kind_sets: [NUM_KINDS]BoardBitSet = undefined;

        for (0..NUM_KINDS) |i| {
            kind_sets[i] = BoardBitSet.initEmpty();
        }

        var color_sets: [NUM_COLOR]BoardBitSet = undefined;
        for (0..NUM_COLOR) |i| {
            color_sets[i] = BoardBitSet.initEmpty();
        }

        const occupied_set = BoardBitSet.initEmpty();

        return Self{
            .kind_sets = kind_sets,
            .color_sets = color_sets,
            .occupied_set = occupied_set,
            .meta = BoardMeta.init(),
        };
    }

    pub fn clone(self: Self) Self {
        var res = Self{
            .zhash = self.zhash,
            .kind_sets = undefined,
            .color_sets = undefined,
            .occupied_set = self.occupied_set.clone(),
            .active_color = self.active_color,
            .full_moves = self.full_moves,

            .meta = self.meta.clone(),
        };

        @memcpy(res.kind_sets[0..NUM_KINDS], self.kind_sets[0..NUM_KINDS]);
        @memcpy(res.color_sets[0..NUM_COLOR], self.color_sets[0..NUM_COLOR]);

        return res;
    }

    pub fn initHash(self: *Self) void {
        var occupied_iter = self.occupied_set.iterator();

        var zhash: u64 = 0;
        while (occupied_iter.next()) |pos| {
            const p = self.getPos(pos).?;
            zhash ^= HASHER.getPieceNum(p, pos);
        }

        for (0..NUM_COLOR) |color_idx| {
            const color: Color = @enumFromInt(color_idx);

            if (self.meta.castling_rights[color_idx].king_side) {
                zhash ^= HASHER.getCastleRights(color, true);
            }

            if (self.meta.castling_rights[color_idx].queen_side) {
                zhash ^= HASHER.getCastleRights(color, false);
            }
        }

        if (self.meta.en_passant_pos) |ep| {
            zhash ^= HASHER.getEnPassant(ep);
        }

        if (self.active_color == Color.Black) {
            zhash ^= HASHER.black_to_move;
        }

        self.zhash = zhash;
    }

    pub fn getPieceSet(self: *const Self, p: Piece) BoardBitSet {
        const color = self.color_sets[@intFromEnum(p.color)];
        const kind = self.kind_sets[@intFromEnum(p.kind)];

        return color.intersectWith(kind);
    }

    pub fn makeMove(self: *Self, move: *const Move) void {
        const start_peice = self.getPos(move.start) orelse {
            std.debug.panic(
                "attempted to play move: {s} but start piece was not found\nfen: {s}\nmove: {?}",
                .{ move.toSan(), ZigFish.Fen.toFen(self), move },
            );
        };

        const color = self.active_color;
        const color_idx = @intFromEnum(color);
        const kind = move.promotion_kind orelse start_peice.kind;
        const move_piece = Piece{ .color = color, .kind = kind };

        self.setPos(move.start, null);
        self.setPos(move.end, move_piece);

        if (self.meta.en_passant_pos) |ep| {
            self.zhash ^= HASHER.getEnPassant(ep);
            self.meta.en_passant_pos = null;
        }

        if (move.move_flags.contains(MoveType.Capture) or move.kind == Kind.Pawn) {
            self.meta.half_moves = 0;
        } else {
            self.meta.half_moves += 1;
        }

        var captured_pos = move.end;

        // update hash for moved piece
        self.zhash ^= HASHER.getPieceNum(.{
            .color = color,
            .kind = start_peice.kind,
        }, move.start);
        self.zhash ^= HASHER.getPieceNum(move_piece, move.end);

        switch (move.kind) {
            Kind.Pawn => {
                const diff_dir = get_diff_dir(move);
                const rank_diff = diff_dir[0];
                const dir = diff_dir[1];

                if (rank_diff == 2) {
                    const ep_pos = move.start.move_dir(dir);
                    self.meta.en_passant_pos = move.start.move_dir(dir);
                    self.zhash ^= HASHER.getEnPassant(ep_pos);
                }

                if (move.move_flags.contains(MoveType.EnPassant)) {
                    captured_pos = move.end.move_dir(dir.opposite());
                    self.setPos(captured_pos, null);
                }
            },
            Kind.King => {
                if (self.meta.castling_rights[color_idx].king_side) {
                    self.zhash ^= HASHER.getCastleRights(color, true);
                }
                if (self.meta.castling_rights[color_idx].queen_side) {
                    self.zhash ^= HASHER.getCastleRights(color, false);
                }

                self.meta.castling_rights[color_idx].king_side = false;
                self.meta.castling_rights[color_idx].queen_side = false;

                if (move.move_flags.contains(MoveType.Castling)) {
                    const all_castling_info = Precompute.CASTLING_INFO[color_idx];
                    const castling_info = all_castling_info.from_king_end(move.end).?;

                    const rook = Piece{
                        .color = color,
                        .kind = Kind.Rook,
                    };

                    self.zhash ^= HASHER.getPieceNum(rook, castling_info.rook_start);
                    self.zhash ^= HASHER.getPieceNum(rook, castling_info.rook_end);

                    self.setPos(castling_info.rook_start, null);
                    self.setPos(castling_info.rook_end, rook);
                }
            },
            Kind.Rook => {
                const start_file = move.start.toRankFile().file;
                if (start_file == 0) {
                    if (self.meta.castling_rights[color_idx].queen_side) {
                        self.zhash ^= HASHER.getCastleRights(color, false);
                    }
                    self.meta.castling_rights[color_idx].queen_side = false;
                } else if (start_file == 7) {
                    if (self.meta.castling_rights[color_idx].king_side) {
                        self.zhash ^= HASHER.getCastleRights(color, true);
                    }
                    self.meta.castling_rights[color_idx].king_side = false;
                }
            },
            else => {},
        }
        // update hash to remove the captured piece
        if (move.captured_kind) |k| {
            const captuered_piece = Piece{ .color = color.get_enemy(), .kind = k };
            self.zhash ^= HASHER.getPieceNum(captuered_piece, captured_pos);
        }

        if (self.active_color == Color.Black) {
            self.full_moves += 1;
        }

        self.active_color = self.active_color.get_enemy();
        self.zhash ^= HASHER.black_to_move;
    }

    pub fn unMakeMove(self: *Self, move: *const Move, meta: BoardMeta) void {
        const old_meta = self.meta;
        if (old_meta.en_passant_pos) |ep| {
            self.zhash ^= HASHER.getEnPassant(ep);
        }
        if (meta.en_passant_pos) |ep| {
            self.zhash ^= HASHER.getEnPassant(ep);
        }

        for (0..NUM_COLOR) |color_idx| {
            const color: Color = @enumFromInt(color_idx);
            const old_castle = old_meta.castling_rights[color_idx];
            const new_castle = meta.castling_rights[color_idx];

            if (old_castle.king_side != new_castle.king_side) {
                self.zhash ^= HASHER.getCastleRights(color, true);
            }
            if (old_castle.queen_side != new_castle.queen_side) {
                self.zhash ^= HASHER.getCastleRights(color, false);
            }
        }

        self.meta = meta;

        const piece_color = self.active_color.get_enemy();

        const start_piece = Piece{ .color = piece_color, .kind = move.kind };
        self.zhash ^= HASHER.getPieceNum(start_piece, move.start);
        self.setPos(move.start, start_piece);

        const end_piece = if (move.promotion_kind) |k| Piece{ .color = piece_color, .kind = k } else start_piece;
        self.zhash ^= HASHER.getPieceNum(end_piece, move.end);

        const maybe_captured_piece = if (move.captured_kind) |k| Piece{
            .color = self.active_color,
            .kind = k,
        } else null;

        var captured_pos: Position = undefined;

        if (move.move_flags.contains(MoveType.EnPassant)) {
            // clear the pawn that took
            self.setPos(move.end, null);

            // get pos of the peice taken
            const diff_dir = get_diff_dir(move);
            const dir = diff_dir[1];
            captured_pos = move.end.move_dir(dir.opposite());
            // self.zhash ^= HASHER.getPieceNum(, end_pos);
        } else {
            captured_pos = move.end;
        }

        if (move.move_flags.contains(MoveType.Castling)) {
            const color_idx = @intFromEnum(piece_color);
            const all_castling_info = Precompute.CASTLING_INFO[color_idx];
            const castling_info = all_castling_info.from_king_end(move.end).?;

            const rook = Piece{
                .color = piece_color,
                .kind = Kind.Rook,
            };

            self.zhash ^= HASHER.getPieceNum(rook, castling_info.rook_end);
            self.zhash ^= HASHER.getPieceNum(rook, castling_info.rook_start);

            self.setPos(castling_info.rook_end, null);
            self.setPos(castling_info.rook_start, rook);
        }

        self.setPos(captured_pos, maybe_captured_piece);
        if (maybe_captured_piece) |captured| {
            self.zhash ^= HASHER.getPieceNum(captured, captured_pos);
        }

        if (self.active_color == Color.White) {
            self.full_moves -= 1;
        }

        self.active_color = self.active_color.get_enemy();
        self.zhash ^= HASHER.black_to_move;
    }

    pub fn getPos(self: *const Self, pos: Position) ?Piece {
        const pos_idx = pos.toIndex();

        if (!self.occupied_set.isSet(pos_idx)) {
            return null;
        }

        const color: Color = for (0..NUM_COLOR) |idx| {
            if (self.color_sets[idx].isSet(pos_idx)) {
                break @enumFromInt(idx);
            }
        } else {
            std.debug.panic("No color found when occupied was set", .{});
        };

        const kind: Kind = for (0..NUM_KINDS) |idx| {
            if (self.kind_sets[idx].isSet(pos_idx)) {
                break @enumFromInt(idx);
            }
        } else {
            std.debug.panic("No kind found when occupied was set", .{});
        };

        return Piece{ .color = color, .kind = kind };
    }

    pub fn setPos(self: *Self, pos: Position, maybe_piece: ?Piece) void {
        const pos_idx = pos.toIndex();

        // unset the position first to remove any piece that might be there
        for (&self.color_sets) |*bs| {
            bs.unset(pos_idx);
        }
        for (&self.kind_sets) |*bs| {
            bs.unset(pos_idx);
        }
        self.occupied_set.unset(pos_idx);

        if (maybe_piece) |p| {
            self.color_sets[@intFromEnum(p.color)].set(pos_idx);
            self.kind_sets[@intFromEnum(p.kind)].set(pos_idx);
            self.occupied_set.set(pos_idx);
        }
    }

    pub fn king_in_check(self: *const Self) bool {
        const attack_info = ZigFish.MoveGen.allAttackedSqaures(self);

        return attack_info.king_attackers.count() > 0;
    }
};

test "parse pos str" {
    const pos = Position.fromStr("e4");

    try std.testing.expect(pos.eql(Position.fromRankFile(.{ .rank = 3, .file = 4 })));

    // std.log.debug("{s}", .{pos.toStr()});

    try std.testing.expect(std.mem.eql(u8, &pos.toStr(), "e4"));
}

test "pos to str" {
    const pos = Position.fromRankFile(.{ .rank = 0, .file = 0 });

    // std.log.debug("{s}", .{pos.toStr()});

    try std.testing.expect(std.mem.eql(u8, &pos.toStr(), "a1"));
}
