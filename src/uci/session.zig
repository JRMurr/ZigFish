const std = @import("std");
const Thread = std.Thread;
const Allocator = std.mem.Allocator;

const ZigFish = @import("zigfish");
const Uci = @import("root.zig");
const Command = Uci.Commands.Command;
const Search = ZigFish.Search;

// pub fn

const Writer = std.fs.File.Writer; // std.io.BufferedWriter(4096, std.fs.File.Writer).Writer;

const Threads = struct {
    search: Thread,
    time: Thread,
    joined: bool = false,

    pub fn join(self: *Threads) void {
        if (self.joined) {
            return;
        }
        self.joined = true;
        self.search.join();
        self.time.join();
    }
};

// reader: std.io.Reader,
writer: Writer,
// arena: *std.heap.ArenaAllocator,
allocator: Allocator,
game: *ZigFish.GameManager,
write_lock: Thread.Mutex,
// arena_lock: Thread.Mutex,
search: ?*ZigFish.Search = null,
threads: ?Threads = null,

const Self = @This();

pub fn init(allocator: Allocator, game: *ZigFish.GameManager, writer: Writer) Self {
    return .{
        // .arena = arena,
        .allocator = allocator,
        .game = game,
        .writer = writer,
        .write_lock = Thread.Mutex{},
        // .arena_lock = Thread.Mutex{},
    };
}

fn reset(self: *Self, join_threads: bool) !void {
    if (self.search) |s| {
        _ = try s.stopSearch();
        s.deinit();
        self.allocator.destroy(s);
        self.search = null;
    }
    if (join_threads) {
        if (self.threads) |*t| {
            t.join();
            self.threads = null;
        }
    }
}

pub fn deinit(self: Self) void {
    if (self.search) |s| {
        s.deinit();
        self.allocator.destroy(s);
    }
}

fn writeLn(self: *Self, buf: []const u8) !void {
    try self.printLock("{s}\n", .{buf});
}

fn printLock(self: *Self, comptime format: []const u8, args: anytype) !void {
    // lock so background monitor doesnt clobber...
    self.write_lock.lock();
    defer self.write_lock.unlock();
    try self.writer.print(format, args);
}

fn startInner(self: *Self) !void {
    self.search.?.startSearch() catch |e| {
        std.debug.panic("error running search: {}", .{e});
    };
}

fn waitForSearchToStop(self: *Self) !void {
    if (self.search) |s| {
        if (s.stop_search.isSet()) {
            try s.search_done.timedWait(10 * std.time.ns_per_ms);
        }
    }
}

fn startSearch(self: *Self, opts: Search.SearchOpts) !void {
    try self.reset(true);
    self.search = try self.allocator.create(Search);
    self.search.?.* = try self.game.getSearch(.{});

    const search_thread = try std.Thread.spawn(.{}, startInner, .{self});
    const monitor_thread = try std.Thread.spawn(.{}, monitorTimeLimit, .{ self, opts.time_limit_millis.? });
    self.threads = .{
        .search = search_thread,
        .time = monitor_thread,
    };
}

fn getCurrTimeInMilli() u64 {
    return @intCast(std.time.milliTimestamp());
}

fn monitorTimeLimit(session: *Self, timeLimitMillis: u64) !void {
    const startTime = getCurrTimeInMilli();
    const endTime = startTime + timeLimitMillis;

    while (true) {
        const currentTime = getCurrTimeInMilli();
        const search = session.search orelse return;
        if (search.search_done.isSet() or currentTime >= endTime) {
            const move = try search.stopSearch();
            const score = search.best_score;
            try session.printLock("info score cp {} multipv 1\n", .{score});
            if (move) |m| {
                try session.printLock("bestmove {s}\n", .{m.toSimple().toStr()});
            } else {
                try session.printLock("bestmove 0000\n", .{});
            }
            break;
        }
        std.time.sleep(10 * std.time.ns_per_ms);
    }
}

fn stopSearch(self: *Self) !void {
    if (self.search) |s| {
        _ = try s.stopSearch();
    }
}

/// handles command, returns true if should exit
pub fn handleCommand(self: *Self, command: *const Command) !bool {
    switch (command.*) {
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
        .UciNewGame => {
            try self.reset(true);
        },
        .Position => |args| {
            // TODO: might only need to apply the last move if we have been initalized before
            try self.reset(true);
            const fen = args.fen;
            self.game.reinitFen(fen.constSlice());
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
        },
        .Stop => {
            try self.stopSearch();
        },
        .PonderHit => {},
        .Quit => {
            try self.stopSearch();
            try self.reset(true);
            std.time.sleep(10 * std.time.ns_per_ms); // wait for things to cleanup..
            return true;
        },
    }

    return false;
}

// test "search for a move" {
//     var game = try ZigFish.GameManager.init(std.testing.allocator);
//     defer game.deinit();
//     // var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     // defer arena.deinit();

//     const out = std.io.getStdOut();
//     var session = Uci.Session.init(std.testing.allocator, &game, out.writer());
//     defer session.deinit();

//     const command_parsed = try Uci.Commands.Command.fromStr(std.testing.allocator, "go movetime 100");
//     const command = command_parsed.parsed;
//     defer command.deinit();
//     _ = try session.handleCommand(command);
//     std.time.sleep(10 * std.time.ns_per_ms);
//     // try session.waitForSearchToStop();

//     try std.testing.expect(session.search.?.best_move != null);

//     try session.reset(true);
// }

// test "search from sad position move" {
//     var game = try ZigFish.GameManager.init(std.testing.allocator);
//     defer game.deinit();
//     // var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     // defer arena.deinit();

//     const out = std.io.getStdOut();
//     var session = Uci.Session.init(std.testing.allocator, &game, out.writer());
//     defer session.deinit();

//     {
//         const command_parsed = try Uci.Commands.Command.fromStr(std.testing.allocator, "position startpos moves d2d4 d7d5 c2c4 e7e5 d4e5 d5d4 g1f3 b8c6 g2g3 c8g4 f1g2 d8d7 b1d2 f7f6 e5f6 g8f6 e2e3 f8b4 e3d4 c6d4 e1g1 e8c8 f3e5 g4d1 e5d7 d4e2 g1h1 f6d7 f1d1 b4e7 d1e1 e2c1 e1e7 c1d3 a1f1 d7b6 b2b3 h7h6 h2h4 h8g8 g2h3 c8b8 d2e4 d3b4 h3e6 c7c6 f1a1 d8e8 e7e8 g8e8 a1g1 e8e6 g3g4 e6e4 g1d1 e4g4 d1f1 b4a2 f1a1 a2c1 a1c1 g4h4 h1g2 c6c5 c1c2 h6h5 c2e2 h4d4 e2e5 b6d7 e5h5 d4d6 g2f3 d6d3 f3e4 d3d2 e4f3 b7b6 f3e3 d2b2 b3b4 c5b4 h5g5 b2b3 e3d4 b3a3 g5g7 a3f3 d4e4 a7a5 e4f3 d7e5 f3e4 b4b3 e4e5 b3b2 e5d4 b2b1Q c4c5 b1a1 d4d3 a1g7 f2f3 a5a4 c5c6 a4a3 f3f4 a3a2 d3c4 a2a1Q c4d3 g7d4");
//         const command = command_parsed.parsed;
//         defer command.deinit();
//         _ = try session.handleCommand(command);
//     }
//     const command_parsed = try Uci.Commands.Command.fromStr(std.testing.allocator, "go movetime 1000");
//     const command = command_parsed.parsed;
//     defer command.deinit();
//     _ = try session.handleCommand(command);
//     std.time.sleep(10 * std.time.ns_per_ms);
//     // try session.waitForSearchToStop();

//     try std.testing.expect(session.search.?.best_move != null);

//     try session.reset(true);
// }
