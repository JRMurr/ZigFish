const std = @import("std");

const ZigFish = @import("root.zig");
const Move = ZigFish.Move;
const Position = ZigFish.Position;
const MoveFlags = ZigFish.MoveFlags;

moves: [MAX_MOVES]Move,
count: usize,
const MoveList = @This();

pub const MAX_MOVES: usize = 218;

pub fn init() MoveList {
    return .{ .moves = undefined, .count = 0 };
}

pub fn append(self: *MoveList, move: Move) void {
    self.moves[self.count] = move;
    self.count += 1;
}

pub fn items(self: MoveList) []const Move {
    return self.moves[0..self.count];
}

pub fn sort(
    self: *MoveList,
    context: anytype,
    comptime lessThanFn: fn (@TypeOf(context), lhs: Move, rhs: Move) bool,
) void {
    std.mem.sort(Move, self.moves[0..self.count], context, lessThanFn);
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

//             const move = self.moves[self.idx];
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
        std.debug.print("move: {}\n", .{actual});
        try std.testing.expect(actual.eql(expected));
    }
}

// test "append inline" {
//     var moves = MoveList.init();

//     // const moveOne = Move{
//     //     .start = Position.fromStr("e2"),
//     //     .end = Position.fromStr("e4"),
//     //     .kind = ZigFish.Kind.Pawn,
//     //     .move_flags = MoveFlags{},
//     // };

//     // const moveTwo = Move{
//     //     .start = Position.fromStr("b1"),
//     //     .end = Position.fromStr("c3"),
//     //     .kind = ZigFish.Kind.Knight,
//     //     .move_flags = MoveFlags{},
//     // };

//     // const moveThree = Move{
//     //     .start = Position.fromStr("f1"),
//     //     .end = Position.fromStr("f4"),
//     //     .kind = ZigFish.Kind.Pawn,
//     //     .move_flags = MoveFlags{},
//     // };

//     moves.append(Move{
//         .start = Position.fromStr("e2"),
//         .end = Position.fromStr("e4"),
//         .kind = ZigFish.Kind.Pawn,
//         .move_flags = MoveFlags{},
//     });

//     moves.append(Move{
//         .start = Position.fromStr("b1"),
//         .end = Position.fromStr("c3"),
//         .kind = ZigFish.Kind.Knight,
//         .move_flags = MoveFlags{},
//     });

//     moves.append(Move{
//         .start = Position.fromStr("f1"),
//         .end = Position.fromStr("f4"),
//         .kind = ZigFish.Kind.Pawn,
//         .move_flags = MoveFlags{},
//     });

//     const move_slice = moves.items();

//     try std.testing.expectEqual(3, move_slice.len);

//     for (move_slice) |m| {
//         std.debug.print("move: {}\n", .{m});
//     }
// }
