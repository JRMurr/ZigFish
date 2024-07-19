const std = @import("std");
const Utils = @import("zigfish").Utils;

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

pub const Command = union(CommandKind) {
    Uci,
    Debug: bool,
    IsReady,
    SetOption: ToDoArgs,
    Register,
    UciNewGame,
    Position: ToDoArgs,
    Go: ToDoArgs,
    Stop,
    PonderHit,
    Quit,

    pub fn fromStr(str: []const u8) !ParseRes(Command) {
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
                const toggle_str = iter.next() orelse std.debug.panic("No on/off on debug command {s}\n", .{str});
                if (std.mem.eql(u8, toggle_str, "on")) {
                    break :blk Command{ .Debug = true };
                }
                break :blk Command{ .Debug = false };
            },
            // TODO: make UciOption parser
            // .SetOption => blk: {
            //     consumeConst(iter, "name");
            //     const id = iter.next() orelse return error.missingParam;
            // },
            else => std.debug.panic("TODO:", .{}),
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
    const parsed = try Command.fromStr("ucinewgame");
    try std.testing.expectEqual(Command{ .UciNewGame = {} }, parsed.parsed);
}

test "parse debug on" {
    const parsed = try Command.fromStr("debug on");
    try std.testing.expectEqual(Command{ .Debug = true }, parsed.parsed);
}
