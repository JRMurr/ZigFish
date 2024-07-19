const std = @import("std");

const ZigFish = @import("zigfish");

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

    std.log.debug("{}", .{move.?});
}
