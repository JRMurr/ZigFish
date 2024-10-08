const std = @import("std");

const ZigFish = @import("root.zig");
const Move = ZigFish.Move;
const Position = ZigFish.Position;
const MoveFlags = ZigFish.MoveFlags;

pub const MAX_MOVES: usize = 218;

const MoveArr = std.BoundedArray(Move, MAX_MOVES);

moves: MoveArr,
const MoveList = @This();

pub fn init() MoveList {
    const moves = MoveArr.init(0) catch {
        std.debug.panic("could not init MoveList\n", .{});
    };
    return .{ .moves = moves };
}

pub fn append(self: *MoveList, move: Move) void {
    self.moves.appendAssumeCapacity(move);
}

pub fn items(self: *const MoveList) []const Move {
    return self.moves.constSlice();
}

pub fn count(self: *const MoveList) usize {
    return self.moves.len;
}

pub fn sort(
    self: *MoveList,
    context: anytype,
    comptime lessThanFn: fn (@TypeOf(context), lhs: Move, rhs: Move) bool,
) void {
    std.mem.sort(Move, self.moves.slice(), context, lessThanFn);
}

// pub fn iterator(self: MoveList) Iterator() {
//     return .{ .idx = 0, .moves = &self };
// }

// fn Iterator() type {
//     return struct {
//         const IterSelf = @This();
//         idx: usize,
//         moves: *const MoveList,

//         /// Returns the index of the next unvisited set bit
//         /// in the bit set, in ascending order.
//         pub fn next(self: *IterSelf) ?Move {
//             if (self.idx >= self.moves.count) return null;

//             const move = self.moves.moves[self.idx];
//             self.idx += 1;
//             return move;
//         }
//     };
// }

test "move items should only return valid moves" {
    var moves = MoveList.init();

    const moveOne = Move{
        .start = Position.fromStr("e2"),
        .end = Position.fromStr("e4"),
        .kind = ZigFish.Kind.Pawn,
        .move_flags = MoveFlags{},
    };

    const moveTwo = Move{
        .start = Position.fromStr("b1"),
        .end = Position.fromStr("c3"),
        .kind = ZigFish.Kind.Knight,
        .move_flags = MoveFlags{},
    };

    const moveThree = Move{
        .start = Position.fromStr("f1"),
        .end = Position.fromStr("f4"),
        .kind = ZigFish.Kind.Pawn,
        .move_flags = MoveFlags{},
    };

    const test_moves = [_]Move{ moveOne, moveTwo, moveThree };

    for (test_moves) |m| {
        moves.append(m);
    }

    const move_slice = moves.items();

    try std.testing.expectEqual(3, move_slice.len);

    for (move_slice, test_moves) |actual, expected| {
        // std.debug.print("move: {}\n", .{actual});
        try std.testing.expectEqualStrings(&expected.toSan(), &actual.toSan());
        try std.testing.expect(actual.eql(expected));
    }
}

fn sortByStart(_: @TypeOf(.{}), a: Move, b: Move) bool {
    return a.start.index < b.start.index;
}

test "sort" {
    var moves = MoveList.init();

    const moveOne = Move{
        .start = Position.fromIndex(10),
        .end = Position.fromStr("e4"),
        .kind = ZigFish.Kind.Pawn,
        .move_flags = MoveFlags{},
    };

    const moveTwo = Move{
        .start = Position.fromIndex(3),
        .end = Position.fromStr("c3"),
        .kind = ZigFish.Kind.Knight,
        .move_flags = MoveFlags{},
    };

    const moveThree = Move{
        .start = Position.fromIndex(9),
        .end = Position.fromStr("f4"),
        .kind = ZigFish.Kind.Pawn,
        .move_flags = MoveFlags{},
    };

    const test_moves = [_]Move{ moveOne, moveTwo, moveThree };

    const sorted_moves = [_]Move{ moveTwo, moveThree, moveOne };

    for (test_moves) |m| {
        moves.append(m);
    }

    moves.sort(.{}, sortByStart);
    const sorted_slice = moves.items();

    try std.testing.expectEqual(3, sorted_slice.len);

    for (sorted_slice, sorted_moves) |actual, expected| {
        // std.debug.print("move: {}\n", .{actual});
        try std.testing.expectEqualStrings(&expected.toSan(), &actual.toSan());
        try std.testing.expect(actual.eql(expected));
    }
}
