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
            if (std.mem.startsWith(u8, command_str, kind.asStr())) {
                return .{ .parsed = kind, .rest = iter };
            }
        }

        return error.InvalidCommand;
    }
};

const EmptyCommandArgs = void;
const ToDoArgs = u8;

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
        const iter = commandKindRes.rest;

        const command: Command = switch (kind) {
            .Uci, .IsReady, .Register, .UciNewGame, .Stop, .PonderHit, .Quit => |k| blk: {
                break :blk @unionInit(Command, @tagName(k), {});
            },
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
    try std.testing.expectEqual("fen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 e4", parsed.rest.rest());
}

test "parse EmptyCommandArgs" {
    const parsed = try Command.fromStr("ucinewgame");
    try std.testing.expectEqual(.{ .UciNewGame = {} }, parsed.parsed);
}
