const std = @import("std");

const ZigFish = @import("zigfish");

// const piece_types = @import("piece.zig");
// const Piece = piece_types.Piece;

// const game_types = @import("game.zig");
// const GameManager = game_types.GameManager;

// const ZigFish = @import("root");
// const BoardBitSet = ZigFish.BoardBitSet;
// const Position = ZigFish.Position;
// const Move = ZigFish.Move;

// const MoveList = game_types.MoveList;

// const ZHashing = @import("zhash.zig").ZHashing;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // Used for move generation so we can reset after each move taken
    const move_allocator = arena.allocator();

    // var move_history = try std.ArrayList(Move).initCapacity(gpa_allocator, 30);

    var game = try ZigFish.GameManager.init(gpa_allocator);

    const move = try game.findBestMove(move_allocator, .{});

    std.debug.print("{}\n", .{move.?});
}
