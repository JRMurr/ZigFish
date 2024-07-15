const std = @import("std");
const piece = @import("piece.zig");
const Piece = piece.Piece;
const fen = @import("fen.zig");
const utils = @import("utils.zig");

const ZHashing = @import("zhash.zig").ZHashing;

const precompute = @import("precompute.zig");

const bitset = @import("bitset.zig");

const Dir = bitset.Dir;

pub const BoardBitSet = @import("bitset.zig").BoardBitSet;

pub const PositionRankFile = packed struct {
    rank: u8,
    file: u8,

    pub fn toPosition(self: PositionRankFile) Position {
        return Position.fromRankFile(self);
    }
};

pub const Position = packed struct {
    index: u8, // only really needs to be a u6....

    pub fn fromRankFile(p: PositionRankFile) Position {
        return Position.fromIndex(p.rank * 8 + p.file);
    }

    pub fn fromStr(str: []const u8) Position {
        const file_char = std.ascii.toLower(str[0]);
        const file = file_char - 97;

        const rank_char = str[1];
        const rank = rank_char - 49; // 48 is where 0 is, need an extra -1 since we are 0 indexed

        return Position.fromRankFile(.{ .rank = rank, .file = file });
    }

    pub fn toStr(self: Position) [2]u8 {
        const rankFile = self.toRankFile();
        const file_char = rankFile.file + 97;
        const rank_char = rankFile.rank + 49;

        return .{ file_char, rank_char };
    }

    pub fn toRankFile(self: Position) PositionRankFile {
        const file = self.index % 8;
        const rank = @divFloor(self.index, 8);
        return .{ .file = file, .rank = rank };
    }

    pub fn toIndex(self: Position) usize {
        return self.index;
    }

    pub fn fromIndex(idx: usize) Position {
        return Position{ .index = @intCast(idx) };
    }

    pub fn eql(self: Position, other: Position) bool {
        return self.index == other.index;
    }

    pub fn move_dir(self: Position, dir: Dir) Position {
        const new_idx = @as(i8, @intCast(self.index)) + dir.to_offset();
        return Position.fromIndex(@intCast(new_idx));
    }

    pub fn all_positions() [64]Position {
        var positions: [64]Position = undefined;
        inline for (0..64) |i| {
            positions[i] = Position.fromIndex(i);
        }

        return positions;
    }
};

pub const MoveType = enum {
    Capture,
    Promotion,
    EnPassant,
    Castling,
};

pub const MoveFlags = std.enums.EnumSet(MoveType);

const SAN_LEN = 8;

fn initStr(char: u8, comptime len: usize) [len]u8 {
    var str: [len]u8 = undefined;
    for (0..len) |i| {
        str[i] = char;
    }

    return str;
}

pub const Move = struct {
    start: Position,
    end: Position,
    kind: piece.Kind,
    move_flags: MoveFlags,
    captured_kind: ?piece.Kind = null,
    promotion_kind: ?piece.Kind = null,

    pub fn toSan(self: Move) [SAN_LEN]u8 {
        // https://www.chessprogramming.org/Algebraic_Chess_Notation#SAN
        // TODO: san can omit info depening on if the move is unambiguous.
        // for now duing "full"
        // TODO: castling

        const from_str = self.start.toStr();
        const to_str = self.end.toStr();

        const capture_str = if (self.move_flags.contains(MoveType.Capture)) "x" else "";

        const piece_symbol = self.kind.to_symbol();

        const promotion_symbol = if (self.promotion_kind) |k| k.to_symbol() else "";

        var str = comptime initStr(' ', SAN_LEN);
        _ = std.fmt.bufPrint(&str, "{s}{s}{s}{s}{s}", .{ piece_symbol, from_str, capture_str, to_str, promotion_symbol }) catch {
            std.debug.panic("Bad san format for {any}", .{self});
        };

        return str;
    }

    pub fn toStrSimple(self: Move) [5]u8 {
        const from_str = self.start.toStr();
        const to_str = self.end.toStr();
        const promotion_symbol = if (self.promotion_kind) |k| k.to_symbol() else "";

        var str = comptime initStr(' ', 5);
        _ = std.fmt.bufPrint(&str, "{s}{s}{s}", .{ from_str, to_str, promotion_symbol }) catch {
            std.debug.panic("Bad move format for {any}", .{self});
        };

        return str;
    }
};

pub const CastlingRights = struct {
    queen_side: bool,
    king_side: bool,

    pub fn initNone() CastlingRights {
        return .{ .queen_side = false, .king_side = false };
    }
};

const NUM_KINDS = utils.enum_len(piece.Kind);
const NUM_COLOR = utils.enum_len(piece.Color);

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
};

fn get_diff_dir(move: Move) std.meta.Tuple(&.{ u8, Dir }) {
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

pub const Board = struct {
    const Self = @This();
    kind_sets: [NUM_KINDS]BoardBitSet,
    color_sets: [NUM_COLOR]BoardBitSet,
    /// redudent set for easy check if a square is occupied
    occupied_set: BoardBitSet,

    active_color: piece.Color = piece.Color.White,
    full_moves: usize = 0,

    meta: BoardMeta,

    hasher: ZHashing,

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
            .hasher = ZHashing.init(),
        };
    }

    pub fn initHash(self: *Self) void {
        var occupied_iter = self.occupied_set.iterator();

        var zhash: u64 = 0;
        while (occupied_iter.next()) |pos| {
            const p = self.getPos(pos).?;
            zhash ^= self.hasher.getPieceNum(p, pos);
        }

        for (0..NUM_COLOR) |color_idx| {
            const color: piece.Color = @enumFromInt(color_idx);

            if (self.meta.castling_rights[color_idx].king_side) {
                zhash ^= self.hasher.getCastleRights(color, true);
            }

            if (self.meta.castling_rights[color_idx].queen_side) {
                zhash ^= self.hasher.getCastleRights(color, false);
            }
        }

        if (self.meta.en_passant_pos) |ep| {
            zhash ^= self.hasher.getEnPassant(ep);
        }

        if (self.active_color == piece.Color.Black) {
            zhash ^= self.hasher.black_to_move;
        }

        self.zhash = zhash;
    }

    pub fn getPieceSet(self: Self, p: Piece) BoardBitSet {
        const color = self.color_sets[@intFromEnum(p.color)];
        const kind = self.kind_sets[@intFromEnum(p.kind)];

        return color.intersectWith(kind);
    }

    pub fn makeMove(self: *Self, move: Move) void {
        const start_peice = self.getPos(move.start).?;

        const color = self.active_color;
        const color_idx = @intFromEnum(color);
        const kind = move.promotion_kind orelse start_peice.kind;
        const move_piece = Piece{ .color = color, .kind = kind };

        self.setPos(move.start, null);
        self.setPos(move.end, move_piece);

        self.meta.en_passant_pos = null;

        if (move.move_flags.contains(MoveType.Capture) or move.kind == piece.Kind.Pawn) {
            self.meta.half_moves = 0;
        } else {
            self.meta.half_moves += 1;
        }

        var captured_pos = move.end;

        // update hash for moved piece
        self.zhash ^= self.hasher.getPieceNum(.{
            .color = color,
            .kind = start_peice.kind,
        }, move.start);
        self.zhash ^= self.hasher.getPieceNum(move_piece, move.end);

        switch (move.kind) {
            piece.Kind.Pawn => {
                const diff_dir = get_diff_dir(move);
                const rank_diff = diff_dir[0];
                const dir = diff_dir[1];

                if (rank_diff == 2) {
                    self.meta.en_passant_pos = move.start.move_dir(dir);
                }

                if (move.move_flags.contains(MoveType.EnPassant)) {
                    captured_pos = move.end.move_dir(dir.opposite());
                    self.setPos(captured_pos, null);
                }
            },
            piece.Kind.King => {
                self.meta.castling_rights[color_idx].king_side = false;
                self.meta.castling_rights[color_idx].queen_side = false;

                self.zhash ^= self.hasher.getCastleRights(color, true);
                self.zhash ^= self.hasher.getCastleRights(color, false);

                if (move.move_flags.contains(MoveType.Castling)) {
                    const all_castling_info = precompute.CASTLING_INFO[color_idx];
                    const castling_info = all_castling_info.from_king_end(move.end).?;

                    const rook = Piece{
                        .color = color,
                        .kind = piece.Kind.Rook,
                    };

                    self.zhash ^= self.hasher.getPieceNum(rook, castling_info.rook_start);
                    self.zhash ^= self.hasher.getPieceNum(rook, castling_info.rook_end);

                    self.setPos(castling_info.rook_start, null);
                    self.setPos(castling_info.rook_end, rook);
                }
            },
            piece.Kind.Rook => {
                const start_file = move.start.toRankFile().file;
                if (start_file == 0) {
                    self.meta.castling_rights[color_idx].queen_side = false;
                    self.zhash ^= self.hasher.getCastleRights(color, false);
                } else if (start_file == 7) {
                    self.meta.castling_rights[color_idx].king_side = false;
                    self.zhash ^= self.hasher.getCastleRights(color, true);
                }
            },
            else => {},
        }
        // update hash to remove the captured piece
        if (move.captured_kind) |k| {
            const captuered_piece = Piece{ .color = color.get_enemy(), .kind = k };
            self.zhash ^= self.hasher.getPieceNum(captuered_piece, captured_pos);
        }

        if (self.active_color == piece.Color.Black) {
            self.full_moves += 1;
        }

        self.active_color = self.active_color.get_enemy();
        self.zhash ^= self.hasher.black_to_move;
    }

    pub fn unMakeMove(self: *Self, move: Move, meta: BoardMeta) void {
        const old_meta = self.meta;
        if (old_meta.en_passant_pos) |ep| {
            self.zhash ^= self.hasher.getEnPassant(ep);
        }
        if (meta.en_passant_pos) |ep| {
            self.zhash ^= self.hasher.getEnPassant(ep);
        }

        for (0..NUM_COLOR) |color_idx| {
            const color: piece.Color = @enumFromInt(color_idx);
            const old_castle = old_meta.castling_rights[color_idx];
            const new_castle = old_meta.castling_rights[color_idx];

            if (old_castle.king_side != new_castle.king_side) {
                self.zhash ^= self.hasher.getCastleRights(color, true);
            }
            if (old_castle.queen_side != new_castle.queen_side) {
                self.zhash ^= self.hasher.getCastleRights(color, false);
            }
        }
        self.meta = meta;

        const piece_color = self.active_color.get_enemy();

        const start_piece = Piece{ .color = piece_color, .kind = move.kind };
        self.zhash ^= self.hasher.getPieceNum(start_piece, move.start);
        self.setPos(move.start, start_piece);

        const end_piece = if (move.promotion_kind) |k| Piece{ .color = piece_color, .kind = k } else start_piece;
        self.zhash ^= self.hasher.getPieceNum(end_piece, move.end);

        const maybe_captured_piece = if (move.captured_kind) |k| Piece{
            .color = self.active_color,
            .kind = k,
        } else null;

        const end_pos = if (move.move_flags.contains(MoveType.EnPassant)) blk: {
            // clear the pawn that took
            self.setPos(move.end, null);

            // get pos of the peice taken
            const diff_dir = get_diff_dir(move);
            const dir = diff_dir[1];
            break :blk move.end.move_dir(dir.opposite());
        } else move.end;

        if (move.move_flags.contains(MoveType.Castling)) {
            const color_idx = @intFromEnum(piece_color);
            const all_castling_info = precompute.CASTLING_INFO[color_idx];
            const castling_info = all_castling_info.from_king_end(move.end).?;

            const rook = Piece{
                .color = piece_color,
                .kind = piece.Kind.Rook,
            };

            self.zhash ^= self.hasher.getPieceNum(rook, castling_info.rook_end);
            self.zhash ^= self.hasher.getPieceNum(rook, castling_info.rook_start);

            self.setPos(castling_info.rook_end, null);
            self.setPos(castling_info.rook_start, rook);
        }

        self.setPos(end_pos, maybe_captured_piece);
        if (maybe_captured_piece) |captured| {
            self.zhash ^= self.hasher.getPieceNum(captured, move.end);
        }

        if (self.active_color == piece.Color.White) {
            self.full_moves -= 1;
        }

        self.active_color = self.active_color.get_enemy();
        self.zhash ^= self.hasher.black_to_move;
    }

    pub fn getPos(self: Self, pos: Position) ?Piece {
        const pos_idx = pos.toIndex();

        if (!self.occupied_set.isSet(pos_idx)) {
            return null;
        }

        const color: piece.Color = for (0..NUM_COLOR) |idx| {
            if (self.color_sets[idx].isSet(pos_idx)) {
                break @enumFromInt(idx);
            }
        } else {
            std.debug.panic("No color found when occupied was set", .{});
        };

        const kind: piece.Kind = for (0..NUM_KINDS) |idx| {
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
};

test "parse pos str" {
    const pos = Position.fromStr("e4");

    try std.testing.expect(pos.eql(Position.fromRankFile(.{ .rank = 3, .file = 4 })));

    // std.debug.print("{s}\n", .{pos.toStr()});

    try std.testing.expect(std.mem.eql(u8, &pos.toStr(), "e4"));
}

test "pos to str" {
    const pos = Position.fromRankFile(.{ .rank = 0, .file = 0 });

    // std.debug.print("{s}\n", .{pos.toStr()});

    try std.testing.expect(std.mem.eql(u8, &pos.toStr(), "a1"));
}
