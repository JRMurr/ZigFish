const std = @import("std");

const Allocator = std.mem.Allocator;

const ZigFish = @import("zigfish");
const Uci = @import("root.zig");
const Command = Uci.Commands.Command;

// pub fn

// reader: std.io.Reader,
writer: std.io.BufferedWriter(4096, std.fs.File.Writer).Writer,
arena: std.heap.ArenaAllocator,
game: *ZigFish.GameManager,

const Self = @This();

pub fn init(arena: std.heap.ArenaAllocator, game: *ZigFish.GameManager, writer: anytype) Self {
    return .{ .arena = arena, .game = game, .writer = writer };
}

pub fn deinit(self: Self) void {
    self.arena.deinit();
}

fn writeLn(self: Self, buf: []const u8) !void {
    return self.writer.print("{s}\n", .{buf});
}

pub fn handleCommand(self: Self, command: Command) !void {
    switch (command) {
        .Uci => {
            // send id and option comamnds
            try self.writeLn("id name ZigFish");
            try self.writeLn("id authort JRMurr");
            // TODO: send options
            try self.writeLn("uciok");
        },
        .Debug => |enabled| {
            _ = enabled;
        },
        .IsReady => {
            try self.writeLn("readyok");
        },
        .SetOption => |opts| {
            _ = opts;
        },
        .Register => {},
        .UciNewGame => {},
        .Position => |args| {
            const fen = args.fen;
            // TODO: play moves;
            self.game.reinitFen(fen);
        },
        .Go => |args| {
            _ = args;
        },
        .Stop => {},
        .PonderHit => {},
        .Quit => {},
    }
}
