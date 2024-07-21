const std = @import("std");
const Thread = std.Thread;
const Allocator = std.mem.Allocator;

const ZigFish = @import("zigfish");
const Uci = @import("root.zig");
const Command = Uci.Commands.Command;
const Search = ZigFish.Search;

// pub fn

const Writer = std.fs.File.Writer; // std.io.BufferedWriter(4096, std.fs.File.Writer).Writer;

// reader: std.io.Reader,
writer: Writer,
arena: std.heap.ArenaAllocator,
game: *ZigFish.GameManager,
write_lock: *Thread.Mutex,
search: ?ZigFish.Search = null,

const Self = @This();

pub fn init(arena: std.heap.ArenaAllocator, game: *ZigFish.GameManager, writer: Writer) Self {
    // const thread = try std.Thread.spawn(.{}, searchMonitor, .{16});
    // thread.detach();

    var mtx = Thread.Mutex{};
    return .{
        .arena = arena,
        .game = game,
        .writer = writer,
        .write_lock = &mtx,
    };
}

pub fn deinit(self: Self) void {
    self.arena.deinit();
}

fn writeLn(self: Self, buf: []const u8) !void {
    // lock so background monitor doesnt clobber...
    self.write_lock.lock();
    defer self.write_lock.unlock();
    try self.writer.print("{s}\n", .{buf});
}

fn printLock(self: Self, comptime format: []const u8, args: anytype) !void {
    // lock so background monitor doesnt clobber...
    self.write_lock.lock();
    defer self.write_lock.unlock();
    try self.writer.print(format, args);
}

// fn searchMonitor(self: *Self, sleep_time_milli: u64) !void {
//     while (true) {
//         if (self.search) |search| {
//             if (search.search_done.isSet()) {}
//         }
//         std.time.sleep(sleep_time_milli * std.time.ns_per_ms); // Sleep for 1 millisecond to avoid busy waiting
//     }
// }

fn startInner(search: *Search, move_allocator: Allocator) !void {
    return search.startSearch(move_allocator) catch |e| {
        std.debug.panic("error running search: {}", .{e});
    };
}

fn startSearch(self: *Self, opts: Search.SearchOpts) !void {
    const move_allocator = self.arena.allocator();
    self.search = try self.game.getSearch(opts);

    const thread = try std.Thread.spawn(.{ .allocator = move_allocator, .stack_size = 100 * 1024 * 1024 }, startInner, .{ &self.search.?, move_allocator });
    thread.detach();
}

fn getCurrTimeInMilli() u64 {
    return @intCast(std.time.milliTimestamp());
}

fn monitorTimeLimit(session: *Self, timeLimitMillis: u64) !void {
    const startTime = getCurrTimeInMilli();
    const endTime = startTime + timeLimitMillis;

    while (true) {
        const currentTime = getCurrTimeInMilli();
        if (currentTime >= endTime) {
            if (session.search) |*s| {
                const move = s.stopSearch();
                const score = s.best_score;
                try session.printLock("info score cp {} multipv 1\n", .{score});
                if (move) |m| {
                    try session.printLock("bestmove {s}\n", .{m.toSimple().toStr()});
                } else {
                    try session.printLock("bestmove 0000\n", .{});
                }
                break;
            }
        }
        std.time.sleep(1 * std.time.ns_per_ms); // Sleep for 1 millisecond to avoid busy waiting
    }
}

pub fn handleCommand(self: *Self, command: Command) !void {
    switch (command) {
        .Uci => {
            // send id and option comamnds
            try self.writeLn("id name ZigFish");
            try self.writeLn("id author JRMurr");
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
            std.debug.panic("Option not supported: {s}", .{opts.name.items});
        },
        .Register => {},
        .UciNewGame => {},
        .Position => |args| {
            const fen = args.fen;
            self.game.reinitFen(fen);
            for (args.moves.items) |m| {
                try self.game.makeSimpleMove(m);
            }
        },
        .Go => |args| {
            var search_opts = Search.SearchOpts{};
            for (args.items) |arg| {
                switch (arg) {
                    .Movetime => |t| {
                        search_opts.time_limit_millis = t;
                    },
                    else => std.debug.panic("go arg {any} not supported", .{arg}),
                }
            }
            try self.startSearch(search_opts);
            const monitorThread = try std.Thread.spawn(.{}, monitorTimeLimit, .{ self, search_opts.time_limit_millis.? });
            monitorThread.detach();
        },
        .Stop => {},
        .PonderHit => {},
        .Quit => {},
    }
}
