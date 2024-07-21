const std = @import("std");

const Allocator = std.mem.Allocator;

const ZigFish = @import("zigfish");
const Uci = @import("root.zig");
const Command = Uci.Commands.Command;

// reader: std.io.Reader,
writer: std.io.AnyWriter,
arena: std.heap.ArenaAllocator,
game: ZigFish.GameManager,

const Self = @This();

// pub fn init(reader: std.io.Reader, writer: std.io.Writer, arean: std.heap.ArenaAllocator, game: ZigFish.GameManager,) Self {}

pub fn deinit(self: Self) void {
    self.arena.deinit();
}

pub fn handleCommand(self: Self, command: Command) !void {
    switch (command) {
        .Uci => {
            // send id and option comamnds
            try self.writer.write("id name ZigFish\n");
            try self.writer.write("id authort JRMurr\n");
            // TODO: send options
            try self.writer.write("uciok\n");
        },
        .Debug => |enabled| {
            _ = enabled;
        },
        .IsReady => {
            try self.writer.write("readyok\n");
        },
        .SetOption => |opts| {
            _ = opts;
        },
        .Register => {},
        .UciNewGame => {},
        .Position => |args| {
            const fen = args.fen;
            // TODO: play moves;
            self.game.reinit(fen);
        },
        .Go => |args| {
            _ = args;
        },
        .Stop => {},
        .PonderHit => {},
        .Quit => {},
    }
}
