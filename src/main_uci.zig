const std = @import("std");

const ZigFish = @import("zigfish");
const Uci = @import("uci");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var game = try ZigFish.GameManager.init(gpa_allocator);

    // TODO: should these be buffered?
    const stdin = std.io.getStdIn().reader();

    const out = std.io.getStdOut();
    var buf = std.io.bufferedWriter(out.writer());

    var session = Uci.Session.init(arena, &game, buf.writer());

    var msg_buf: [4096]u8 = undefined;

    while (true) {
        const msg = try stdin.readUntilDelimiterOrEof(&msg_buf, '\n') orelse continue;
        const command_parsed = try Uci.Commands.Command.fromStr(gpa_allocator, msg);
        const command = command_parsed.parsed;
        defer command.deinit();
        try session.handleCommand(command);
        try buf.flush();
    }

    // const move = try game.findBestMove(move_allocator, .{});

    // std.log.debug("{}", .{move.?});
}

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
