const std = @import("std");
const piece = @import("piece.zig");
const Piece = piece.Piece;
const fen = @import("fen.zig");

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

const BoardBitSet = packed struct {
    const Self = @This();
    pub const BitSet = std.bit_set.IntegerBitSet(64);

    pub const NotAFile = BitSet{ .mask = 0xfefefefefefefefe };
    pub const NotHFile = BitSet{ .mask = 0x7f7f7f7f7f7f7f7f };

    bit_set: BitSet,

    /// Creates a bit set with no elements present.
    pub fn initEmpty() Self {
        return .{ .bit_set = BitSet.initEmpty() };
    }

    pub fn fromMask(mask: BitSet.MaskInt) Self {
        return .{ .bit_set = BitSet{ .mask = mask } };
    }

    /// Returns true if the bit at the specified index
    /// is present in the set, false otherwise.
    pub fn isSet(self: Self, index: usize) bool {
        return self.bit_set.isSet(index);
    }

    /// Adds a specific bit to the bit set
    pub fn set(self: *Self, index: usize) void {
        self.bit_set.set(index);
    }

    /// Removes a specific bit from the bit set
    pub fn unset(self: *Self, index: usize) void {
        self.bit_set.unset(index);
    }

    pub fn clone(self: Self) BoardBitSet {
        return self.fromMask(self.bit_set.mask);
    }

    // https://www.chessprogramming.org/General_Setwise_Operations#OneStepOnly

    /// shift south one
    pub fn southOne(self: Self) BoardBitSet {
        return Self.fromMask(self.bit_set.mask >> 8);
    }

    /// shift north one
    pub fn northOne(self: Self) BoardBitSet {
        return Self.fromMask(self.bit_set.mask >> 8);
    }

    /// shift east one
    pub fn eastOne(self: Self) BoardBitSet {
        const mask = (self.bit_set.mask << 1) & Self.NotAFile.mask;
        return Self.fromMask(mask);
    }

    /// shift north east one
    pub fn noEaOne(self: Self) BoardBitSet {
        const mask = (self.bit_set.mask << 9) & Self.NotAFile.mask;
        return Self.fromMask(mask);
    }

    /// shift south east one
    pub fn soEaOne(self: Self) BoardBitSet {
        const mask = (self.bit_set.mask >> 7) & Self.NotAFile.mask;
        return Self.fromMask(mask);
    }

    /// shift west one
    pub fn westOne(self: Self) BoardBitSet {
        const mask = (self.bit_set.mask >> 1) & Self.NotHFile.mask;
        return Self.fromMask(mask);
    }

    /// shift south west one
    pub fn soWeOne(self: Self) BoardBitSet {
        const mask = (self.bit_set.mask >> 9) & Self.NotHFile.mask;
        return Self.fromMask(mask);
    }

    /// shift north west one
    pub fn noWeOne(self: Self) BoardBitSet {
        const mask = (self.bit_set.mask << 7) & Self.NotHFile.mask;
        return Self.fromMask(mask);
    }
};

inline fn enum_len(comptime T: type) comptime_int {
    return @typeInfo(T).Enum.fields.len;
}

const NUM_KINDS = enum_len(piece.Kind);
const NUM_COLOR = enum_len(piece.Color);

pub const Board = struct {
    const Self = @This();
    peice_sets: [NUM_KINDS]BoardBitSet,
    color_sets: [NUM_COLOR]BoardBitSet,

    /// redudent set for easy check if a square is occupied
    occupied_set: BoardBitSet,

    pub fn init() Self {
        var peice_sets: [NUM_KINDS]BoardBitSet = undefined;

        for (0..NUM_KINDS) |i| {
            peice_sets[i] = BoardBitSet.initEmpty();
        }

        var color_sets: [NUM_COLOR]BoardBitSet = undefined;

        for (0..NUM_COLOR) |i| {
            color_sets[i] = BoardBitSet.initEmpty();
        }

        const occupied_set = BoardBitSet.initEmpty();

        return Self{ .peice_sets = peice_sets, .color_sets = color_sets, .occupied_set = occupied_set };
    }

    pub fn get_piece(self: Self, pos: Position) ?Piece {
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
            if (self.peice_sets[idx].isSet(pos_idx)) {
                break @enumFromInt(idx);
            }
        } else {
            std.debug.panic("No kind found when occupied was set", .{});
        };

        return Piece{ .color = color, .kind = kind };
    }

    pub fn set_piece(self: *Self, pos: Position, maybe_piece: ?Piece) void {
        const pos_idx = pos.to_index();

        // unset the position first to remove any piece that might be there
        for (&self.color_sets) |*bs| {
            bs.unset(pos_idx);
        }
        for (&self.peice_sets) |*bs| {
            bs.unset(pos_idx);
        }
        self.occupied_set.unset(pos_idx);

        if (maybe_piece) |p| {
            self.color_sets[@intFromEnum(p.color)].set(pos_idx);
            self.peice_sets[@intFromEnum(p.kind)].set(pos_idx);
            self.occupied_set.set(pos_idx);
        }
    }
};
