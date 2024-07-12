const std = @import("std");
const piece = @import("piece.zig");
const Piece = piece.Piece;
const fen = @import("fen.zig");
const utils = @import("utils.zig");

const bitset = @import("bitset.zig");

const Dir = bitset.Dir;

pub const BoardBitSet = @import("bitset.zig").BoardBitSet;

pub const PositionRankFile = packed struct {
    rank: u8,
    file: u8,

    pub inline fn toPosition(self: PositionRankFile) Position {
        return Position.fromRankFile(self);
    }
};

pub const Position = packed struct {
    index: u8, // only really needs to be a u6....

    pub inline fn fromRankFile(p: PositionRankFile) Position {
        return Position.fromIndex(p.rank * 8 + p.file);
    }

    pub fn fromStr(str: []const u8) Position {
        const file_str = std.ascii.toLower(str[0]);
        const file = file_str - 97;

        const rank_str = str[1];
        const rank = rank_str - 49; // 48 is where 0 is, need an extra -1 since we are 0 indexed

        return Position.fromRankFile(.{ .rank = rank, .file = file });
    }

    pub inline fn toRankFile(self: Position) PositionRankFile {
        const file = self.index % 8;
        const rank = @divFloor(self.index, 8);
        return .{ .file = file, .rank = rank };
    }

    pub inline fn toIndex(self: Position) usize {
        return self.index;
    }

    pub inline fn fromIndex(idx: usize) Position {
        return Position{ .index = @intCast(idx) };
    }

    pub inline fn eql(self: Position, other: Position) bool {
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
    Normal,
    Capture,
    Promotion,
    EnPassant,
    Castling,
};

pub const Move = struct {
    start: Position,
    end: Position,
    kind: piece.Kind,
    move_type: MoveType = MoveType.Normal,
    captured_kind: ?piece.Kind = null,
    promotion_kind: ?piece.Kind = null,
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

pub const Board = struct {
    const Self = @This();
    kind_sets: [NUM_KINDS]BoardBitSet,
    color_sets: [NUM_COLOR]BoardBitSet,

    castling_rights: [NUM_COLOR]CastlingRights,

    enPassantPos: ?Position = null,

    /// redudent set for easy check if a square is occupied
    occupied_set: BoardBitSet,

    pub fn init() Self {
        var kind_sets: [NUM_KINDS]BoardBitSet = undefined;

        for (0..NUM_KINDS) |i| {
            kind_sets[i] = BoardBitSet.initEmpty();
        }

        var color_sets: [NUM_COLOR]BoardBitSet = undefined;

        var castling_rights: [NUM_COLOR]CastlingRights = undefined;

        for (0..NUM_COLOR) |i| {
            color_sets[i] = BoardBitSet.initEmpty();
            castling_rights[i] = CastlingRights.initNone();
        }

        const occupied_set = BoardBitSet.initEmpty();

        return Self{
            .kind_sets = kind_sets,
            .color_sets = color_sets,
            .occupied_set = occupied_set,
            .castling_rights = castling_rights,
        };
    }

    pub fn get_piece_set(self: Self, p: Piece) BoardBitSet {
        const color = self.color_sets[@intFromEnum(p.color)];
        const kind = self.kind_sets[@intFromEnum(p.kind)];

        return color.intersectWith(kind);
    }

    pub fn get_pos(self: Self, pos: Position) ?Piece {
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

    pub fn set_pos(self: *Self, pos: Position, maybe_piece: ?Piece) void {
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
}
