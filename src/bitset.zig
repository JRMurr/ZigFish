const std = @import("std");

const piece_types = @import("piece.zig");
const Color = piece_types.Color;

pub const BitSet = std.bit_set.IntegerBitSet(64);
pub const MaskInt = BitSet.MaskInt;

pub const MAIN_DIAG = 0x8040201008040201; // A1 to H8
pub const ANTI_DIAG = 0x0102040810204080; // H1 to A8

// https://www.chessprogramming.org/On_an_empty_Board#By_Calculation_3
pub fn rankMask(mask: MaskInt) MaskInt {
    return 0xFF << (mask & 56);
}

pub fn fileMask(mask: MaskInt) MaskInt {
    return 0x0101010101010101 << (mask & 7);
}

pub fn diagonalMask(mask: MaskInt) MaskInt {
    const diag = 8 * (mask & 7) - (mask & 56);
    const nort = -diag & (diag >> 31);
    const sout = diag & (-diag >> 31);
    return (MAIN_DIAG >> sout) << nort;
}

pub fn antiDiagMask(mask: MaskInt) MaskInt {
    const diag = 56 - 8 * (mask & 7) - (mask & 56);
    const nort = -diag & (diag >> 31);
    const sout = diag & (-diag >> 31);
    return (ANTI_DIAG >> sout) << nort;
}

pub const FILE_A = 0x0101010101010101;
pub const FILE_H = 0x8080808080808080;
pub const RANK_3 = 0x0000000000FF0000;
pub const RANK_6 = 0x0000FF0000000000;

pub const NOT_FILE_A = 0xfefefefefefefefe;
pub const NOT_FILE_H = 0x7f7f7f7f7f7f7f7f;

pub const NOT_FILE_GH: u64 = 0x3f3f3f3f3f3f3f3f;
pub const NOT_FILE_AB: u64 = 0xfcfcfcfcfcfcfcfc;

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

pub const BoardBitSet = packed struct {
    const Self = @This();

    bit_set: BitSet,

    /// Creates a bit set with no elements present.
    pub fn initEmpty() Self {
        return .{ .bit_set = BitSet.initEmpty() };
    }

    pub fn initWithIndex(index: usize) Self {
        var bs = BitSet.initEmpty();
        bs.set(index);
        return .{ .bit_set = bs };
    }

    pub fn fromMask(mask: MaskInt) Self {
        return .{ .bit_set = BitSet{ .mask = mask } };
    }

    pub fn fromBitSet(bit_set: BitSet) Self {
        return .{ .bit_set = bit_set };
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

    pub fn differenceWith(self: Self, other: Self) Self {
        var result = self;
        result.bit_set.setIntersection(other.bit_set.complement());
        return result;
    }

    pub fn clone(self: Self) Self {
        return self.fromMask(self.bit_set.mask);
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

        const left_attacks = shift_color(color, mask, 7) & NOT_FILE_A;
        const right_attacks = shift_color(color, mask, 9) & NOT_FILE_H;

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
