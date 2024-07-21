const std = @import("std");
const ZigFish = @import("zigfish");
const Utils = ZigFish.Utils;

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

        inline for (Utils.enum_fields(CommandKind)) |f| {
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

const PositionArgs = struct {
    fen: []const u8,
    moves: SimpleMoveList,
};

const SimpleMove = struct {
    start: ZigFish.Position,
    end: ZigFish.Position,

    pub fn fromStr(str: []const u8) !SimpleMove {
        if (str.len != 4) {
            return error.InvalidMove;
        }

        const start = ZigFish.Position.fromStr(str[0..2]);
        const end = ZigFish.Position.fromStr(str[2..4]);
        return .{ .start = start, .end = end };
    }
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

const GoArgs = union(enum) {
    SearchMoves: SimpleMoveList,
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

        const go_str = iter.next() orelse {
            return error.EmptyInput;
        };

        // TODO: multiple go commands can be on the same line
        // go infinite searchmoves e2e4 d2d4
        inline for (Utils.unionFields(GoArgs)) |f| {
            if (std.ascii.eqlIgnoreCase(f.name, go_str)) {
                if (f.type == void) {
                    return @unionInit(GoArgs, f.name, {});
                }
                if (f.type == usize) {
                    const int_str = iter.next() orelse {
                        return error.EmptyInput;
                    };
                    const parsedInt = try std.fmt.parseInt(usize, int_str, 10);
                    return @unionInit(GoArgs, f.name, parsedInt);
                }

                return @unionInit(GoArgs, f.name, try consumeIterToMoves(allocator, &iter));
            }
        }

        return error.InvalidCommand;
    }
};

pub const OptionArgs = struct { name: []const u8, value: ?[]const u8 };

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
                var name: ?[]u8 = null;
                var value: ?[]u8 = null;
                while (iter.next()) |s| {
                    if (std.ascii.eqlIgnoreCase(s, "value")) {
                        name = try strList.toOwnedSlice();
                    }
                    try strList.appendSlice(s);
                }
                if (name == null) {
                    name = try strList.toOwnedSlice();
                } else {
                    value = try strList.toOwnedSlice();
                }

                break :blk Command{ .SetOption = .{ .name = name.?, .value = value } };
            },
            .Position => blk: {
                const fenOrStartPos = iter.next() orelse return error.EndOfInput;
                const fen = if (std.mem.eql(u8, fenOrStartPos, "startpos"))
                    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
                else
                    fenOrStartPos;
                const moves = try consumeIterToMoves(allocator, &iter);

                break :blk Command{ .Position = .{ .fen = fen, .moves = moves } };
            },
            .Go => blk: {
                const args = try GoArgs.fromStr(allocator, iter.rest());
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
