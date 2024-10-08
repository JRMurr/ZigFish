const std = @import("std");
const ZigFish = @import("zigfish");
const Utils = ZigFish.Utils;
const SimpleMove = ZigFish.SimpleMove;

const TokenIter = std.mem.TokenIterator(u8, .scalar);

fn ParseRes(comptime T: anytype) type {
    return struct { parsed: T, rest: TokenIter };
}

//https://gist.github.com/DOBRO/2592c6dad754ba67e6dcaec8c90165bf
pub const CommandKind = enum {
    Uci,
    Debug,
    IsReady,
    SetOption,
    Register,
    UciNewGame,
    Position,
    Go,
    Stop,
    PonderHit,
    Quit,

    fn asStr(self: CommandKind) []const u8 {
        return switch (self) {
            .Uci => "uci",
            .Debug => "debug",
            .IsReady => "isready",
            .SetOption => "setoption",
            .Register => "register",
            .UciNewGame => "ucinewgame",
            .Position => "position",
            .Go => "go",
            .Stop => "stop",
            .PonderHit => "ponderhit",
            .Quit => "quit",
        };
    }

    pub fn fromStr(str: []const u8) !ParseRes(CommandKind) {
        var iter = std.mem.tokenizeScalar(u8, str, ' ');

        const command_str = iter.next() orelse {
            return error.EmptyInput;
        };

        inline for (Utils.enumFields(CommandKind)) |f| {
            const kind: CommandKind = @enumFromInt(f.value);
            if (std.mem.eql(u8, command_str, kind.asStr())) {
                return .{ .parsed = kind, .rest = iter };
            }
        }

        return error.InvalidCommand;
    }
};

const EmptyCommandArgs = void;
const ToDoArgs = u8;

fn consumeConst(iter: *TokenIter, val: []const u8) !void {
    if (iter.next()) |next| {
        if (!std.mem.eql(u8, next, val)) {
            return error.MissingConst;
        }
    }

    return error.EndOfInput;
}

fn consumeMaybeConst(iter: *TokenIter, val: []const u8) !bool {
    if (iter.next()) |next| {
        if (!std.mem.eql(u8, next, val)) {
            return error.MissingConst;
        }
        return true;
    }

    return false;
}

const PositionArgs = struct {
    fen: std.BoundedArray(u8, ZigFish.Fen.MAX_FEN_LEN),
    moves: SimpleMoveList,
};

const Allocator = std.mem.Allocator;
pub const SimpleMoveList = std.ArrayList(SimpleMove);

fn consumeIterToMoves(allocator: Allocator, iter: *TokenIter) !SimpleMoveList {
    var moves = SimpleMoveList.init(allocator);
    errdefer moves.deinit();

    while (iter.next()) |m| {
        try moves.append(try SimpleMove.fromStr(m));
    }

    return moves;
}

const GoArgs = std.ArrayList(GoArg);

const GoArg = union(enum) {
    SearchMoves: SimpleMoveList,
    Perft: usize, // non standard, perft deptch
    Ponder,
    Wtime: usize,
    Btime: usize,
    Winc: usize,
    Binc: usize,
    MovesToGo: usize,
    Depth: usize,
    Nodes: usize,
    Mate: usize,
    Movetime: usize,
    Infinite,

    pub fn fromStr(allocator: Allocator, str: []const u8) !GoArgs {
        var iter = std.mem.tokenizeScalar(u8, str, ' ');

        var args = std.ArrayList(GoArg).init(allocator);

        // ex: infinite searchmoves e2e4 d2d4
        while (iter.next()) |go_str| {
            const arg = blk: inline for (Utils.unionFields(GoArg)) |f| {
                if (std.ascii.eqlIgnoreCase(f.name, go_str)) {
                    if (f.type == void) {
                        break :blk @unionInit(GoArg, f.name, {});
                    } else if (f.type == usize) {
                        const int_str = iter.next() orelse {
                            return error.EmptyInput;
                        };
                        const parsedInt = try std.fmt.parseInt(usize, int_str, 10);
                        break :blk @unionInit(GoArg, f.name, parsedInt);
                    } else {
                        break :blk @unionInit(GoArg, f.name, try consumeIterToMoves(allocator, &iter));
                    }
                }
            } else {
                return error.InvalidCommand;
            };

            try args.append(arg);
        }

        return args;
    }
};

const StringList = std.ArrayList(u8);

pub const OptionArgs = struct {
    name: StringList,
    value: ?StringList,
};

pub const Command = union(CommandKind) {
    Uci,
    Debug: bool,
    IsReady,
    SetOption: OptionArgs,
    Register,
    UciNewGame,
    Position: PositionArgs,
    Go: GoArgs,
    Stop,
    PonderHit,
    Quit,

    pub fn deinit(self: Command) void {
        switch (self) {
            .Position => |args| {
                args.moves.deinit();
            },
            .SetOption => |args| {
                args.name.deinit();
                if (args.value) |v| {
                    v.deinit();
                }
            },
            .Go => |args| {
                args.deinit();
            },
            else => {},
        }
    }

    pub fn fromStr(allocator: Allocator, str: []const u8) !ParseRes(Command) {
        const commandKindRes = try CommandKind.fromStr(str);
        const kind = commandKindRes.parsed;
        var iter = commandKindRes.rest;

        const command: Command = switch (kind) {
            .Uci, .IsReady, .Register, .UciNewGame, .Stop, .PonderHit, .Quit => |k| blk: {
                // init the void commandArgs, need some comptime sadness...
                inline for (Utils.unionFields(Command)) |f| {
                    if (f.type != void) {
                        continue;
                    }
                    if (std.mem.eql(u8, f.name, @tagName(k))) {
                        break :blk @unionInit(Command, f.name, {});
                    }
                }
                std.debug.panic("No match on EmptyCommandArgs for: {s}", .{@tagName(k)});
            },
            .Debug => blk: {
                const toggle_str = iter.next() orelse return error.InvalidCommand;
                if (std.mem.eql(u8, toggle_str, "on")) {
                    break :blk Command{ .Debug = true };
                }
                break :blk Command{ .Debug = false };
            },
            // TODO: make UciOption parser
            .SetOption => blk: {
                var strList = std.ArrayList(u8).init(allocator);
                errdefer strList.deinit();
                try consumeConst(&iter, "name");
                var name: ?std.ArrayList(u8) = null;
                var value: ?std.ArrayList(u8) = null;
                while (iter.next()) |s| {
                    if (std.ascii.eqlIgnoreCase(s, "value")) {
                        name = try strList.clone();
                        strList.clearAndFree();
                    }
                    try strList.appendSlice(s);
                }
                if (name == null) {
                    name = strList;
                } else {
                    value = strList;
                }

                break :blk Command{ .SetOption = .{ .name = name.?, .value = value } };
            },
            .Position => blk: {
                const fenOrStartPos = iter.next() orelse return error.EndOfInput;
                var fen_tokens = try std.BoundedArray(u8, ZigFish.Fen.MAX_FEN_LEN).init(0);

                if (std.mem.eql(u8, fenOrStartPos, "fen")) {
                    while (iter.next()) |tok| {
                        if (std.mem.eql(u8, tok, "moves")) {
                            break;
                        }
                        try fen_tokens.appendSlice(tok);
                        try fen_tokens.append(' ');
                    }
                } else {
                    _ = try consumeMaybeConst(&iter, "moves");
                    try fen_tokens.appendSlice(ZigFish.Fen.START_POS);
                }
                const moves = try consumeIterToMoves(allocator, &iter);

                break :blk Command{ .Position = .{ .fen = fen_tokens, .moves = moves } };
            },
            .Go => blk: {
                const args = try GoArg.fromStr(allocator, iter.rest());
                break :blk Command{ .Go = args };
            },
        };

        return .{ .parsed = command, .rest = iter };
    }
};

test {
    std.testing.refAllDecls(@This());
}

test "parse command kind" {
    const parsed = try CommandKind.fromStr("position fen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 e4");
    try std.testing.expectEqual(CommandKind.Position, parsed.parsed);
    try std.testing.expectEqualDeep("fen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 e4", parsed.rest.rest());
}

test "parse EmptyCommandArgs" {
    const parsed = try Command.fromStr(std.testing.allocator, "ucinewgame");
    try std.testing.expectEqual(Command{ .UciNewGame = {} }, parsed.parsed);
}

test "parse debug on" {
    const parsed = try Command.fromStr(std.testing.allocator, "debug on");
    try std.testing.expectEqual(Command{ .Debug = true }, parsed.parsed);
}

test "parse position fen" {
    const parsed = try Command.fromStr(std.testing.allocator, "position fen 3qk2r/3bnp2/7p/1P1B4/3Q4/2N3P1/PP2PP1P/R2K3R b k - 2 22 moves e2e4");
    defer parsed.parsed.deinit();
    const fen = parsed.parsed.Position.fen;

    var moves = parsed.parsed.Position.moves;

    try std.testing.expectStringStartsWith(fen.slice(), "3qk2r/3bnp2/7p/1P1B4/3Q4/2N3P1/PP2PP1P/R2K3R b k - 2 22");

    try std.testing.expectEqual(SimpleMove.fromStr("e2e4"), moves.pop());
}

test "parse position startpos" {
    const parsed = try Command.fromStr(std.testing.allocator, "position startpos moves e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 f3g5 d7d5 e4d5 c6a5 d2d3 a5c4 d3c4 h7h6 g5f3 e5e4");
    defer parsed.parsed.deinit();
    const fen = parsed.parsed.Position.fen;

    var moves = parsed.parsed.Position.moves;

    try std.testing.expectStringStartsWith(fen.slice(), ZigFish.Fen.START_POS);

    try std.testing.expectEqual(SimpleMove.fromStr("e5e4"), moves.pop());
}
