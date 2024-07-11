const std = @import("std");
const piece = @import("piece.zig");
const Piece = piece.Piece;
const fen = @import("fen.zig");
const utils = @import("utils.zig");

pub const BoardBitSet = @import("bitset.zig").BoardBitSet;

// TODO: yeet
pub const Cell = union(enum) {
    empty,
    piece: piece.Piece,

    pub fn is_freindly(self: Cell, other: piece.Piece) bool {
        return switch (self) {
            .piece => |p| p.color == other.color,
            .empty => false,
        };
    }

    pub fn is_enemy(self: Cell, other: piece.Piece) bool {
        return switch (self) {
            .piece => |p| p.color != other.color,
            .empty => false,
        };
    }
};

inline fn difference(a: usize, b: usize) usize {
    var diff = @as(i8, @intCast(a)) - @as(i8, @intCast(b));

    if (diff < 0) {
        diff *= -1;
    }

    return @as(usize, @intCast(diff));
}

pub const Position = struct {
    rank: usize,
    file: usize,

    pub inline fn to_index(self: Position) usize {
        std.debug.assert(self.rank < 8);
        std.debug.assert(self.file < 8);
        return self.rank * 8 + self.file;
    }

    pub inline fn from_index(idx: usize) Position {
        const file = idx % 8;
        const rank = @divFloor(idx, 8);
        return Position{ .file = file, .rank = rank };
    }

    pub fn all_positions() [64]Position {
        var positions: [64]Position = undefined;
        inline for (0..8) |rank| {
            inline for (0..8) |file| {
                const pos = Position{ .rank = rank, .file = file };
                positions[pos.to_index()] = pos;
            }
        }

        return positions;
    }

    /// taxicab distance btwn positons
    pub inline fn dist(self: Position, other: Position) usize {
        return difference(self.rank, other.rank) + difference(self.file, other.file);
    }
};

pub const Move = struct {
    start: Position,
    end: Position,
};

const NUM_KINDS = utils.enum_len(piece.Kind);
const NUM_COLOR = utils.enum_len(piece.Color);

pub const Board = struct {
    const Self = @This();
    kind_sets: [NUM_KINDS]BoardBitSet,
    color_sets: [NUM_COLOR]BoardBitSet,

    /// redudent set for easy check if a square is occupied
    occupied_set: BoardBitSet,

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

        return Self{ .kind_sets = kind_sets, .color_sets = color_sets, .occupied_set = occupied_set };
    }

    pub fn get_piece_set(self: Self, p: Piece) BoardBitSet {
        const color = self.color_sets[@intFromEnum(p.color)];
        const kind = self.kind_sets[@intFromEnum(p.kind)];

        return color.intersectWith(kind);
    }

    pub fn get_pos(self: Self, pos: Position) ?Piece {
        const pos_idx = pos.to_index();

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
        const pos_idx = pos.to_index();

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

test "north moves off the edge of the board should be removed" {
    const pos = Position{ .rank = 7, .file = 1 };

    const idx = pos.to_index();

    var bs = BoardBitSet.initEmpty();

    bs.set(idx);

    const moved = bs.northOne();

    try std.testing.expect(moved.count() == 0);
}

test "east moves off the edge of the board should be removed" {
    const pos = Position{ .rank = 0, .file = 7 };

    const idx = pos.to_index();

    var bs = BoardBitSet.initEmpty();

    bs.set(idx);

    const moved = bs.eastOne();

    try std.testing.expect(moved.count() == 0);
}

test "north east moves off the edge of the board should be removed" {
    const pos = Position{ .rank = 4, .file = 7 };

    const idx = pos.to_index();

    var bs = BoardBitSet.initEmpty();

    bs.set(idx);

    const moved = bs.noEaOne();

    try std.testing.expect(moved.count() == 0);
}

test "west moves off the edge of the board should be removed" {
    const pos = Position{ .rank = 0, .file = 0 };

    const idx = pos.to_index();

    var bs = BoardBitSet.initEmpty();

    bs.set(idx);

    const moved = bs.westOne();

    try std.testing.expect(moved.count() == 0);
}
