const std = @import("std");

const ZigFish = @import("root.zig");

const Dir = ZigFish.Dir;

const BitSet = ZigFish.BitSet;

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

    pub fn flipRank(self: Position) Position {
        const rankFile = self.toRankFile();
        return Position.fromRankFile(.{ .file = rankFile.file, .rank = (7 - rankFile.rank) });
    }

    pub fn fromStr(str: []const u8) Position {
        const file_char = std.ascii.toLower(str[0]);
        const file = file_char - 'a';

        const rank_char = str[1];
        const rank = rank_char - '1';
        return Position.fromRankFile(.{ .rank = rank, .file = file });
    }

    pub fn toStr(self: Position) [2]u8 {
        const rankFile = self.toRankFile();
        const file_char = rankFile.file + 'a';
        const rank_char = rankFile.rank + '1';

        return .{ file_char, rank_char };
    }

    pub fn toFile(self: Position) u8 {
        return self.index % 8;
    }

    pub fn toRank(self: Position) u8 {
        return @divFloor(self.index, 8);
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

    pub fn fileMask(self: Position) BitSet.MaskInt {
        const file = self.toFile();
        return BitSet.fileMask(file);
    }

    pub fn all_positions() [64]Position {
        var positions: [64]Position = undefined;
        inline for (0..64) |i| {
            positions[i] = Position.fromIndex(i);
        }

        return positions;
    }
};
