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

fn reset(self: *Self, join_threads: bool) void {
    // self.arena_lock.lock();
    // defer self.arena_lock.unlock();
    if (self.search) |s| {
        _ = s.stopSearch();
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
    // _ = self.arena.reset(.{ .retain_with_limit = 1024 * 1000 * 50 }); // save 50 mb...

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
    return self.search.?.startSearch() catch |e| {
        std.debug.panic("error running search: {}", .{e});
    };
}

fn waitForSearchToStop(self: *Self) void {
    if (self.search) |s| {
        if (s.stop_search.isSet()) {
            s.search_done.wait();
        }
    }
}

fn startSearch(self: *Self, opts: Search.SearchOpts) !void {
    self.reset(true);
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
        if (search.search_done.isSet()) {
            return;
        }
        if (currentTime >= endTime) {
            const move = search.stopSearch();
            const score = search.best_score;
            try session.printLock("info score cp {} multipv 1\n", .{score});
            if (move) |m| {
                try session.printLock("bestmove {s}\n", .{m.toSimple().toStr()});
            } else {
                try session.printLock("bestmove 0000\n", .{});
            }
            break;
        }
        std.time.sleep(10 * std.time.ns_per_ms); // Sleep for 1 millisecond to avoid busy waiting
    }
}

fn stopSearch(self: *Self) void {
    if (self.search) |s| {
        _ = s.stopSearch();
    }
}

/// handles command, returns true if should exit
pub fn handleCommand(self: *Self, command: Command) !bool {
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
        .UciNewGame => {
            self.reset(true);
        },
        .Position => |args| {
            // TODO: might only need to apply the last move if we have been initalized before
            self.reset(true);
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
            self.stopSearch();
        },
        .PonderHit => {},
        .Quit => {
            self.stopSearch();
            self.reset(true);
            std.time.sleep(10 * std.time.ns_per_ms); // wait for things to cleanup..
            return true;
        },
    }

    return false;
}

test "search for a move" {
    var game = try ZigFish.GameManager.init(std.testing.allocator);
    defer game.deinit();
    // var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    // defer arena.deinit();

    const out = std.io.getStdOut();
    var session = Uci.Session.init(std.testing.allocator, &game, out.writer());
    defer session.deinit();

    const command_parsed = try Uci.Commands.Command.fromStr(std.testing.allocator, "go movetime 100");
    const command = command_parsed.parsed;
    defer command.deinit();
    _ = try session.handleCommand(command);
    std.time.sleep(10 * std.time.ns_per_ms);
    session.waitForSearchToStop();
    defer session.reset(true);

    try std.testing.expect(session.search.?.best_move != null);
}
