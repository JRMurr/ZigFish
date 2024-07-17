const std = @import("std");
const utils = @import("utils.zig");

const piece_types = @import("piece.zig");
const Color = piece_types.Color;

const precompute = @import("precompute.zig");

const Position = @import("board.zig").Position;

pub const BitSet = std.bit_set.IntegerBitSet(64);

pub const MaskInt = BitSet.MaskInt;
pub const ShiftInt = BitSet.ShiftInt;

pub const MAIN_DIAG: MaskInt = 0x8040201008040201; // A1 to H8
pub const ANTI_DIAG: MaskInt = 0x0102040810204080; // H1 to A8

pub const RANK_0: MaskInt = 0x00000000000000FF;
pub const RANK_3: MaskInt = 0x0000000000FF0000;
pub const RANK_6: MaskInt = 0x0000FF0000000000;

pub const FILE_A: MaskInt = 0x0101010101010101;
pub const FILE_H: MaskInt = 0x8080808080808080;

pub const NOT_FILE_A = 0xfefefefefefefefe;
pub const NOT_FILE_H = 0x7f7f7f7f7f7f7f7f;

pub const NOT_FILE_GH: u64 = 0x3f3f3f3f3f3f3f3f;
pub const NOT_FILE_AB: u64 = 0xfcfcfcfcfcfcfcfc;

pub fn toMaskInt(x: anytype) MaskInt {
    return @as(MaskInt, @intCast(x));
}

pub fn toShiftInt(x: anytype) ShiftInt {
    return @as(ShiftInt, @intCast(x));
}

// https://www.chessprogramming.org/On_an_empty_Board#By_Calculation_3
pub fn rankMask(sq: u32) MaskInt {
    return RANK_0 << toShiftInt(sq & 56);
}

pub fn fileMask(sq: u32) MaskInt {
    return FILE_A << toShiftInt(sq & 7);
}

inline fn mainDiagonalMask(sq: u32) MaskInt {
    const sq_i32 = @as(i32, @intCast(sq));

    const diag: i32 = (sq_i32 & 7) - (sq_i32 >> 3);
    return if (diag >= 0)
        MAIN_DIAG >> (toShiftInt(diag) * 8)
    else
        MAIN_DIAG << (toShiftInt(-diag) * 8);
}

inline fn antiDiagonalMask(sq: u32) MaskInt {
    const sq_i32 = @as(i32, @intCast(sq));
    const diag: i32 = 7 - (sq_i32 & 7) - (sq_i32 >> 3);
    return if (diag >= 0)
        ANTI_DIAG >> (toShiftInt(diag) * 8)
    else
        ANTI_DIAG << (toShiftInt(-diag) * 8);
}

fn southOneMask(mask: MaskInt) MaskInt {
    return mask >> 8;
}

fn northOneMask(mask: MaskInt) MaskInt {
    return mask << 8;
}

fn eastOneMask(mask: MaskInt) MaskInt {
    return mask << 1 & NOT_FILE_A;
}

fn westOneMask(mask: MaskInt) MaskInt {
    return mask >> 1 & NOT_FILE_H;
}

pub const MoveFn = fn (self: BoardBitSet) BoardBitSet;

pub const Line = enum {
    Rank,
    File,
    MainDiag,
    AntiDiag,

    pub fn compute_line(self: Line, sqaure: BoardBitSet) BoardBitSet {
        const sq = sqaure.toSquare();

        const mask = switch (self) {
            .Rank => rankMask(sq),
            .File => fileMask(sq),
            .MainDiag => mainDiagonalMask(sq),
            .AntiDiag => antiDiagonalMask(sq),
        };

        return BoardBitSet.fromMask(mask);
    }
};

pub const NUM_LINES = utils.enum_len(Line);

pub const Dir = enum(u3) {
    North = 0,
    South = 1,
    West = 2,
    East = 3,
    NorthWest = 4,
    NorthEast = 5,
    SouthWest = 6,
    SouthEast = 7,

    pub fn compute_ray(self: Dir, sqaure: BoardBitSet) BoardBitSet {
        // https://www.chessprogramming.org/On_an_empty_Board#Rays_by_Line
        const line = self.to_line();

        const single_bit = sqaure.bit_set.mask;
        const sq = sqaure.toSquare();

        const line_attacks = precompute.LINES[sq][@intFromEnum(line)];

        var ray_mask: MaskInt = undefined;
        if (self.is_positive()) {
            const shifted = single_bit << 1;
            // creates a mask where all bits to the left of the original single bit (including the bit itself)
            // are set to 0 and all bits to the right are set to 1.
            ray_mask = 0 -% shifted;
        } else {
            // creates a mask where all bits to the right of the single bit are set to 1
            // and all bits to the left (including the bit itself) are set to 0.
            ray_mask = single_bit -| 1;
        }

        return BoardBitSet.fromMask(line_attacks.bit_set.mask & ray_mask);
    }

    pub fn first_hit_on_ray(self: Dir, ray: BoardBitSet) usize {
        std.debug.assert(ray.bit_set.mask != 0);
        if (self.is_positive()) {
            return ray.bitScanForward();
        } else {
            return ray.bitScanReverse();
        }
    }

    pub fn to_offset(self: Dir) i8 {
        return switch (self) {
            .North => 8,
            .South => -8,
            .West => -1,
            .East => 1,
            .NorthWest => 7,
            .NorthEast => 9,
            .SouthWest => -9,
            .SouthEast => -7,
        };
    }

    pub fn opposite(self: Dir) Dir {
        return switch (self) {
            .North => Dir.South,
            .South => Dir.North,
            .West => Dir.East,
            .East => Dir.West,
            .NorthWest => Dir.SouthEast,
            .NorthEast => Dir.SouthWest,
            .SouthWest => Dir.NorthEast,
            .SouthEast => Dir.NorthWest,
        };
    }

    pub fn is_positive(self: Dir) bool {
        return switch (self) {
            .North => true,
            .South => false,
            .West => false,
            .East => true,
            .NorthWest => true,
            .NorthEast => true,
            .SouthWest => false,
            .SouthEast => false,
        };
    }

    pub fn to_line(self: Dir) Line {
        return switch (self) {
            .North => Line.File,
            .South => Line.File,
            .West => Line.Rank,
            .East => Line.Rank,
            .NorthWest => Line.AntiDiag,
            .NorthEast => Line.MainDiag,
            .SouthWest => Line.MainDiag,
            .SouthEast => Line.AntiDiag,
        };
    }
};

pub const NUM_DIRS = utils.enum_len(Dir);

pub const BoardBitSet = packed struct {
    const Self = @This();

    bit_set: BitSet,

    /// Creates a bit set with no elements present.
    pub fn initEmpty() Self {
        return .{ .bit_set = BitSet.initEmpty() };
    }

    /// Creates a bit set with no elements present.
    pub fn initFull() Self {
        return .{ .bit_set = BitSet.initFull() };
    }

    pub fn initWithIndex(index: usize) Self {
        var bs = BitSet.initEmpty();
        bs.set(index);
        return .{ .bit_set = bs };
    }

    pub fn initWithPos(pos: Position) Self {
        var bs = BitSet.initEmpty();
        bs.set(pos.toIndex());
        return .{ .bit_set = bs };
    }

    pub fn fromMask(mask: MaskInt) Self {
        return .{ .bit_set = BitSet{ .mask = mask } };
    }

    pub fn fromBitSet(bit_set: BitSet) Self {
        return .{ .bit_set = bit_set };
    }

    pub fn debug(self: Self) void {
        var iter = self.bit_set.iterator(.{});
        std.debug.print("-------------\n", .{});
        while (iter.next()) |sqaure| {
            const attacked_pos = Position.fromIndex(sqaure);
            std.debug.print("{s}\n", .{attacked_pos.toStr()});
        }
        std.debug.print("-------------\n", .{});
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

    pub fn setPos(self: *Self, pos: Position) void {
        self.bit_set.set(pos.toIndex());
    }

    /// Removes a specific bit from the bit set
    pub fn unset(self: *Self, index: usize) void {
        self.bit_set.unset(index);
    }

    pub fn count(self: Self) usize {
        return self.bit_set.count();
    }

    pub fn complement(self: Self) BoardBitSet {
        return Self.fromBitSet(self.bit_set.complement());
    }

    pub fn unionWith(self: Self, other: Self) Self {
        var result = self;
        result.bit_set.setUnion(other.bit_set);
        return result;
    }

    pub fn setUnion(self: *Self, other: Self) void {
        self.bit_set.setUnion(other.bit_set);
    }

    pub fn differenceWith(self: Self, other: Self) Self {
        var result = self;
        result.bit_set.setIntersection(other.bit_set.complement());
        return result;
    }

    pub fn remove(self: *Self, other: Self) void {
        self.bit_set.setIntersection(other.bit_set.complement());
    }

    pub fn intersectWith(self: Self, other: Self) Self {
        var result = self;
        result.bit_set.setIntersection(other.bit_set);
        return result;
    }

    pub fn toggleSet(self: *Self, other: Self) void {
        self.bit_set.toggleSet(other.bit_set);
    }

    pub fn xorWith(self: Self, other: Self) Self {
        var result = self;
        result.bit_set.xorWith(other.bit_set);
        return result;
    }

    pub fn clone(self: Self) Self {
        return Self.fromMask(self.bit_set.mask);
    }

    pub fn toSquare(self: Self) u32 {
        std.debug.assert(self.count() == 1);
        return @as(u32, @intCast(self.bit_set.findFirstSet().?));
    }

    pub fn bitScanForward(self: Self) u64 {
        std.debug.assert(self.count() > 0);
        return @ctz(self.bit_set.mask);
    }

    pub fn bitScanReverse(self: Self) u64 {
        std.debug.assert(self.count() > 0);
        const mask = self.bit_set.mask;
        return @bitSizeOf(MaskInt) - 1 - @clz(mask);
    }

    // slight copy from std.bit_set
    pub fn iterator(self: Self) Iterator() {
        return .{ .bits_remain = self.bit_set.mask };
    }

    fn Iterator() type {
        return struct {
            const IterSelf = @This();
            // all bits which have not yet been iterated over
            bits_remain: MaskInt,

            /// Returns the index of the next unvisited set bit
            /// in the bit set, in ascending order.
            pub fn next(self: *IterSelf) ?Position {
                if (self.bits_remain == 0) return null;

                const next_index = @ctz(self.bits_remain);
                self.bits_remain &= self.bits_remain - 1;
                return Position.fromIndex(next_index);
            }
        };
    }

    // https://www.chessprogramming.org/General_Setwise_Operations#OneStepOnly

    /// shift south one
    pub fn southOne(self: Self) Self {
        return Self.fromMask(self.bit_set.mask >> 8);
    }

    /// shift north one
    pub fn northOne(self: Self) Self {
        return Self.fromMask(self.bit_set.mask << 8);
    }

    /// shift east one
    pub fn eastOne(self: Self) Self {
        const mask = (self.bit_set.mask << 1) & NOT_FILE_A;
        return Self.fromMask(mask);
    }

    /// shift west one
    pub fn westOne(self: Self) Self {
        const mask = (self.bit_set.mask >> 1) & NOT_FILE_H;
        return Self.fromMask(mask);
    }

    /// shift north east one
    pub fn noEaOne(self: Self) Self {
        const mask = (self.bit_set.mask << 9) & NOT_FILE_A;
        return Self.fromMask(mask);
    }

    /// shift south east one
    pub fn soEaOne(self: Self) Self {
        const mask = (self.bit_set.mask >> 7) & NOT_FILE_A;
        return Self.fromMask(mask);
    }

    /// shift south west one
    pub fn soWeOne(self: Self) Self {
        const mask = (self.bit_set.mask >> 9) & NOT_FILE_H;
        return Self.fromMask(mask);
    }

    /// shift north west one
    pub fn noWeOne(self: Self) Self {
        const mask = (self.bit_set.mask << 7) & NOT_FILE_H;
        return Self.fromMask(mask);
    }

    // returns all non capture pawn moves
    pub fn pawnMoves(self: Self, empty_squares: BoardBitSet, color: Color) Self {
        const mask = self.bit_set.mask;
        const empty = empty_squares.bit_set.mask;

        const rank_mask: u64 = switch (color) {
            Color.White => RANK_3,
            Color.Black => RANK_6,
        };

        const single_step = shift_color(color, mask, 8) & empty;
        const double_step = shift_color(color, single_step & rank_mask, 8) & empty;

        return Self.fromMask(single_step | double_step);
    }

    pub fn pawnAttacks(self: Self, color: Color, maybe_enemy_sqaures: ?BoardBitSet) Self {
        const mask = self.bit_set.mask;

        const left_amt: BitSet.ShiftInt = if (color == Color.White) 7 else 9;
        const right_amt: BitSet.ShiftInt = if (color == Color.White) 9 else 7;

        const left_attacks = shift_color(color, mask, left_amt) & NOT_FILE_H;
        const right_attacks = shift_color(color, mask, right_amt) & NOT_FILE_A;

        var possible_attacks = left_attacks | right_attacks;

        if (maybe_enemy_sqaures) |enemy_sqaures| {
            const enemies = enemy_sqaures.bit_set.mask;
            possible_attacks &= enemies;
        }
        return Self.fromMask(possible_attacks);
    }

    pub fn knightMoves(self: Self) Self {
        // https://www.chessprogramming.org/Knight_Pattern#Multiple_Knight_Attacks
        const mask = self.bit_set.mask;

        const l1 = (mask >> 1) & NOT_FILE_H;
        const l2 = (mask >> 2) & NOT_FILE_GH;
        const r1 = (mask << 1) & NOT_FILE_A;
        const r2 = (mask << 2) & NOT_FILE_AB;
        const h1 = l1 | r1;
        const h2 = l2 | r2;
        return Self.fromMask((h1 << 16) | (h1 >> 16) | (h2 << 8) | (h2 >> 8));
    }

    pub fn kingMoves(self: Self) Self {
        // https://www.chessprogramming.org/King_Pattern#by_Calculation
        var kingSet = self.bit_set.mask;

        var attacks = eastOneMask(kingSet) | westOneMask(kingSet);
        kingSet |= attacks;
        attacks |= northOneMask(kingSet) | southOneMask(kingSet);
        return Self.fromMask(attacks);
    }
};

// used mostly for pawn moves
fn shift_color(color: Color, x: MaskInt, amount: BitSet.ShiftInt) MaskInt {
    return switch (color) {
        Color.White => x << amount,
        Color.Black => x >> amount,
    };
}
