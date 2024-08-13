const std = @import("std");
const mecha = @import("mecha");

const ZigFish = @import("root.zig");

const GameManager = ZigFish.GameManager;

const Allocator = std.mem.Allocator;

pub const Move = ZigFish.Move;

pub const Pgn = @This();

const FullMove = struct {
    white: []const u8,
    black: ?[]const u8,

    pub fn moves(self: *const FullMove) std.BoundedArray([]const u8, 2) {
        var arr = std.BoundedArray([]const u8, 2).init(0) catch |err| {
            std.debug.panic("error making bounded arr: {}", .{err});
        };

        arr.appendAssumeCapacity(self.white);
        if (self.black) |b| {
            arr.appendAssumeCapacity(b);
        }

        return arr;
    }
};

const Tag = struct { name: []const u8, value: []const u8 };

tags: []Tag,
moves: []FullMove,
result: []const u8,

/// need to pass in the allocator used to parse
pub fn deinit(self: Pgn, allocator: Allocator) void {
    allocator.free(self.tags);
    allocator.free(self.moves);
}

pub const PgnParser = struct {
    pub const pgn = mecha.combine(.{
        many_tags,
        ws.discard(),
        many_moves,
        ws.discard(),
        result,
        ws.discard(),
    }).map(mecha.toStruct(Pgn));

    pub const many_pgn = mecha.many(pgn, .{ .separator = ws });

    // based slightly on https://github.com/Hejsil/mecha/blob/master/example/json.zig

    const space = mecha.ascii.char(' ');
    const new_line = mecha.ascii.char('\n');
    const carriage_return = mecha.ascii.char('\r');
    const tab = mecha.ascii.char('\t');
    const ws = mecha.oneOf(.{
        space,
        new_line,
        carriage_return,
        tab,
    }).many(.{ .collect = false }).discard();

    const chars = char.many(.{ .collect = false, .min = 1 });

    // https://www.asciitable.com/
    const char = mecha.oneOf(.{
        mecha.ascii.range(35, 126), // most normal chars expect ! and quote
        mecha.ascii.char('!'),
    }).asStr();

    fn token(comptime parser: anytype) mecha.Parser(void) {
        return mecha.combine(.{ parser.discard(), ws });
    }

    const lbracket = token(mecha.ascii.char('['));
    const rbracket = token(mecha.ascii.char(']'));

    pub const quote = token(mecha.ascii.char('"'));

    const in_quote_char = mecha.oneOf(.{
        char.asStr(),
        space.asStr(),
        mecha.string("\\\""),
    }).asStr();
    const in_quote_chars = mecha.many(in_quote_char, .{ .collect = false });

    const quote_string = mecha.combine(.{ quote, in_quote_chars, quote });

    pub const tag = mecha.combine(.{
        lbracket.discard(),
        chars,
        space.discard(),
        quote_string,
        rbracket.discard(),
    }).map(mecha.toStruct(Pgn.Tag));

    pub const many_tags = mecha.combine(.{ mecha.opt(ws).discard(), mecha.many(tag, .{ .separator = ws }) });

    // TODO: could replace the manual san parsing with this
    // mecha.noop will probably be needed to make the many different paths have the same parse type

    const castle = mecha.oneOf(.{
        mecha.string("O-O-O"),
        mecha.string("O-O"),
    });

    const piece_char = mecha.oneOf(.{
        mecha.ascii.char('K'),
        mecha.ascii.char('N'),
        mecha.ascii.char('B'),
        mecha.ascii.char('R'),
        mecha.ascii.char('Q'),
    }).asStr();

    const file = mecha.ascii.range('a', 'h').asStr();
    const rank = mecha.ascii.range('1', '8').asStr();

    pub const square = mecha.combine(.{ file, rank }).asStr();

    const promotion = mecha.combine(.{ mecha.ascii.char('='), piece_char }).asStr();

    const check_or_mate = mecha.oneOf(.{ mecha.ascii.char('+'), mecha.ascii.char('#') }).asStr();

    const capture_char = mecha.ascii.char('x');

    const move_end = mecha.combine(.{
        mecha.opt(capture_char),
        square,
    }).asStr();

    const maxium_selector = mecha.combine(.{
        piece_char,
        file,
        rank,
        move_end,
    }).asStr();

    const file_selector = mecha.combine(.{
        piece_char,
        file,
        move_end,
    }).asStr();

    const rank_selector = mecha.combine(.{
        piece_char,
        rank,
        move_end,
    }).asStr();

    const no_selector = mecha.combine(.{ piece_char, move_end }).asStr();

    const non_pawn_move = mecha.oneOf(.{
        maxium_selector,
        no_selector,
        rank_selector,
        file_selector,
    }).asStr();

    const pawn_capture = mecha.combine(.{
        file,
        capture_char,
        square,
    }).asStr();

    const pawn_move = mecha.oneOf(.{
        pawn_capture,
        move_end,
    }).asStr();

    const move_start = mecha.oneOf(.{
        non_pawn_move,
        pawn_move,
    }).asStr();

    pub const non_castle = mecha.combine(.{
        move_start,
        mecha.opt(promotion),
    }).asStr();

    const move_no_check = mecha.oneOf(.{
        non_castle,
        castle,
    }).asStr();

    pub const move = mecha.combine(.{ move_no_check, mecha.opt(check_or_mate) }).asStr();

    const result = mecha.oneOf(.{
        mecha.string("1/2-1/2"),
        mecha.string("1-0"),
        mecha.string("0-1"),
        mecha.string("*"),
    }).asStr();

    const digits = mecha.intToken(.{ .base = 10, .parse_sign = false });
    const move_num = mecha.combine(.{ digits, mecha.ascii.char('.') }).asStr();

    pub const full_move = mecha.combine(.{
        move_num.discard(),
        ws.discard(),
        move,
        ws.discard(),
        mecha.opt(move),
    }).map(mecha.toStruct(Pgn.FullMove));

    const many_moves = mecha.many(full_move, .{ .separator = ws });
};

fn printRes(val: mecha.Result([]const u8)) void {
    std.log.warn("\nval: ({s})\nrest: ({s})\n", .{ val.value, val.rest });
}

const testing = std.testing;

test "parse pgn tag" {
    const pgn_str = "[Event \"Balsa 110221\"]";

    const allocator = testing.allocator;
    const a = (try (comptime PgnParser.tag).parse(allocator, pgn_str));

    // printRes(a);

    try testing.expectEqualStrings("Event", a.value.name);
    try testing.expectEqualStrings("Balsa 110221", a.value.value);
}

test "parse pgn many tags" {
    const tag_str =
        \\ [Event "Balsa 110221"]
        \\ [Site "?"]
        \\ [Date "2019.08.25"]
    ;

    const allocator = testing.allocator;
    const a = (try (comptime PgnParser.many_tags).parse(allocator, tag_str));
    defer allocator.free(a.value);

    try testing.expectEqualStrings("Date", a.value[2].name);
    try testing.expectEqualStrings("2019.08.25", a.value[2].value);
}

fn testStrParser(parser: mecha.Parser([]const u8), val: []const u8) !void {
    // To ignore leaks in the helper just used a stack alloactor
    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const res = try parser.parse(allocator, val);
    // printRes(res);
    try testing.expectEqualStrings(val, res.value);
}

fn anyParser(comptime parser: anytype, val: []const u8) !void {
    return testStrParser(parser.asStr(), val);
}

test "parse pgn square" {
    try testStrParser(PgnParser.square, "e4");
}

test "parse pgn non castle move" {
    try testStrParser(PgnParser.non_castle, "N2e4");
    try testStrParser(PgnParser.non_castle, "e4");
}

test "parse pgn move" {
    try testStrParser(PgnParser.move, "Nf3");
    try testStrParser(PgnParser.move, "Rxe1+");
    try testStrParser(PgnParser.move, "e4#");
    try testStrParser(PgnParser.move, "O-O-O#");
    try testStrParser(PgnParser.move, "cxb4");
    try testStrParser(PgnParser.move, "Bxf6");
    try testStrParser(PgnParser.move, "Qxf6");
}

test "parse pgn full move" {
    try anyParser(PgnParser.full_move, "1. e4 c5");
    try anyParser(PgnParser.full_move, "2. Nf3 d6");
    try anyParser(PgnParser.full_move, "3. d4 cxd4");
    try anyParser(PgnParser.full_move, "4. Nxd4");
}

test "parse pgn many moves" {
    try anyParser(PgnParser.many_moves, "1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4");
    try anyParser(PgnParser.many_moves, "1. d4 Nf6 2. c4 e6 3. Nf3 d5 4. Nc3 c6 5. Bg5 h6 6. Bxf6 Qxf6 7. e3 Nd7 8. Be2 g6 *");
}

test "parse pgn" {
    const pgn_str =
        \\ [Event "Balsa 110221"]
        \\ [Site "?"]
        \\ [Date "2019.08.25"]
        \\ [Round "2.42"]
        \\ [White "X"]
        \\ [Black "X"]
        \\ [Result "*"]
        \\ [ECO "B92"]
        \\ [PlyCount "16"]
        \\ [EventDate "2021.01.17"]
        \\ [EventType "simul"]
        \\ [Source "Sedat Canbaz"]
        \\ 
        \\ 1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Be2 e5 7. Nb3 Be7 8. O-O
        \\ *
    ;

    // var buffer: [1000]u8 = undefined;
    // var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = testing.allocator; //fba.allocator();
    const a = (try PgnParser.pgn.parse(allocator, pgn_str));

    const parsed = a.value;

    defer parsed.deinit(allocator);

    // printRes(a);

    const last_tag = parsed.tags[11];
    try testing.expectEqualStrings("Source", last_tag.name);

    const last_move = parsed.moves[7];
    try testing.expectEqualStrings("O-O", last_move.white);
    try testing.expectEqual(null, last_move.black);

    try testing.expectEqualStrings("*", parsed.result);
}

test "parse many pgn" {
    const pgn_str =
        \\ [Event "Balsa 110221"]
        \\ [Site "?"]
        \\ [Date "2019.09.06"]
        \\ [Round "2.11"]
        \\ [White "X"]
        \\ [Black "X"]
        \\ [Result "*"]
        \\ [ECO "A28"]
        \\ [PlyCount "17"]
        \\ [EventDate "2021.01.17"]
        \\ [EventType "simul"]
        \\ [Source "Sedat Canbaz"]
        \\ 
        \\ 1. c4 e5 2. Nc3 Nf6 3. Nf3 Nc6 4. e4 Bb4 5. d3 d6 6. a3 Bc5 7. b4 Bb6 8. Be3
        \\ Bxe3 9. fxe3 *
        \\ 
        \\ [Event "Balsa 110221"]
        \\ [Site "?"]
        \\ [Date "2019.09.06"]
        \\ [Round "2.11"]
        \\ [White "X"]
        \\ [Black "X"]
        \\ [Result "*"]
        \\ [ECO "C89"]
        \\ [PlyCount "22"]
        \\ [EventDate "2021.01.17"]
        \\ [EventType "simul"]
        \\ [Source "Sedat Canbaz"]
        \\ 
        \\ 1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 O-O 8. c3
        \\ d5 9. exd5 Nxd5 10. Nxe5 Nxe5 11. Rxe5 c6 *
    ;

    var buffer: [6000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();
    const a = (try PgnParser.many_pgn.parse(allocator, pgn_str));

    const pgns = a.value;

    try testing.expectEqual(2, pgns.len);

    try testing.expectEqualStrings("c6", pgns[1].moves[10].black.?);
}
