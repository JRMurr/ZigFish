const std = @import("std");
const mecha = @import("mecha");

const ZigFish = @import("root.zig");

const GameManager = ZigFish.GameManager;

const Allocator = std.mem.Allocator;

const Move = ZigFish.Move;
const GameResult = ZigFish.GameResult;
const Kind = ZigFish.Piece.Kind;
const Position = ZigFish.Position;

pub const Pgn = struct {
    const Move = struct {
        kind: Kind,

        start_file: ?usize,
        start_rank: ?usize,

        is_capture: bool,
        end: Position,
        promotion_kind: ?Kind,
        check_flag: ?u8,
    };

    const FullMove = struct {
        white: []const u8,
        black: ?[]const u8,
    };

    const Tag = struct {
        name: []const u8,
        value: []const u8,
    };

    tags: []Tag,
    moves: []FullMove,
    result: ZigFish.GameResult,

    /// need to parse in the allocator used to parse
    pub fn deinit(self: Pgn, allocator: Allocator) void {
        allocator.free(self.tags);
        allocator.free(self.moves);
    }
};

const PgnParser = struct {
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
    }).asStr();

    fn fileToInt(f: u8) usize {
        return f - 'a';
    }

    fn rankToInt(r: u8) usize {
        return r - '1';
    }

    const file = mecha.ascii.range('a', 'h').map(fileToInt);
    const rank = mecha.ascii.range('1', '8').map(rankToInt);

    pub const square = mecha.combine(.{ file, rank }).asStr().map(Position.fromStr);

    const promotion = mecha.combine(.{ mecha.ascii.char('='), piece_char }).asStr();

    const check_or_mate = mecha.oneOf(.{ mecha.ascii.char('+'), mecha.ascii.char('#') }).asStr();

    const capture_char = mecha.ascii.char('x');

    fn optToBool(v: anytype) bool {
        return if (v == null) false else true;
    }

    const move_end = mecha.combine(.{
        mecha.opt(capture_char).map(optToBool),
        square,
    }).asStr();

    // fn toOptional(T: type) fn (v: T) ?T {
    //     const mapper = struct {
    //         fn mapp(v: T) ?T {
    //             return v;
    //         }
    //     }.mapper;

    //     return mapper;
    // }

    fn toOptional(v: usize) ?usize {
        return v;
    }

    fn toNull(_: anytype) ?usize {
        return null;
    }

    const maxium_selector = mecha.combine(.{
        piece_char,
        file.map(toOptional),
        rank.map(toOptional),
        move_end,
    });

    const file_selector = mecha.combine(.{
        piece_char,
        file.map(toOptional),
        mecha.noop.map(toNull),
        move_end,
    });

    const rank_selector = mecha.combine(.{
        piece_char,
        mecha.noop.map(toNull),
        rank.map(toOptional),
        move_end,
    });

    const no_selector = mecha.combine(.{
        piece_char,
        mecha.noop.map(toNull),
        mecha.noop.map(toNull),
        move_end,
    }).asStr();

    const non_pawn_move = mecha.oneOf(.{
        maxium_selector,
        no_selector,
        rank_selector,
        file_selector,
    }).asStr();

    const pawn_capture = mecha.combine(.{
        mecha.noop.mapConst(Kind.Pawn),
        file,
        mecha.noop.map(toNull),
        capture_char.mapConst(true),
        square,
    }).asStr();

    const pawn_no_captrue = mecha.combine(.{
        mecha.noop.mapConst(Kind.Pawn),
        file,
        mecha.noop.map(toNull),
        mecha.noop.mapConst(false),
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
        mecha.string("1/2-1/2").mapConst(GameResult.Draw),
        mecha.string("1-0").mapConst(GameResult.WhiteWin),
        mecha.string("0-1").mapConst(GameResult.BlackWin),
        mecha.string("*").mapConst(GameResult.InProgress),
    });

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
}

test "parse pgn full move" {
    try anyParser(PgnParser.full_move, "1. e4 c5");
    try anyParser(PgnParser.full_move, "2. Nf3 d6");
    try anyParser(PgnParser.full_move, "3. d4 cxd4");
    try anyParser(PgnParser.full_move, "4. Nxd4");
}

test "parse pgn many moves" {
    try anyParser(PgnParser.many_moves, "1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4");
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

    try testing.expectEqual(GameResult.InProgress, parsed.result);
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

fn isResult(str: []const u8) bool {
    if (std.mem.eql(u8, str, "1/2-1/2")) {
        // draw
        return true;
    }
    if (std.mem.eql(u8, str, "1-0")) {
        // white win
        return true;
    }
    if (std.mem.eql(u8, str, "0-1")) {
        // black win
        return true;
    }

    return false;
}

pub fn fromPgn(pgn: []const u8, allocator: Allocator) Allocator.Error!GameManager {
    var game = try GameManager.init(allocator);

    var it = std.mem.tokenizeAny(u8, pgn, " \n");

    // TODO: handle results

    // 1. e4 e5 2. d4 d5
    main_loop: while (it.next()) |move_num| {
        if (isResult(move_num)) {
            break :main_loop;
        }
        // should start each loop with a move num
        std.debug.assert(std.ascii.isDigit(move_num[0]));
        std.debug.assert(std.mem.endsWith(u8, move_num, "."));

        for (0..2) |_| {
            const moves = try game.getAllValidMoves(allocator);

            const move_str = it.next() orelse {
                std.debug.panic("expected move but got nothing {s}\n", .{pgn});
            };

            const move = Move.fromSan(move_str, moves.items);
            try game.makeMove(move);

            if (it.peek()) |peeked| {
                if (isResult(peeked)) {
                    break :main_loop;
                }
            }
        }
    }

    return game;
}

const fen = @import("fen.zig");

// test "parse pgn" {
//     const pgn =
//         \\ 1. e4 e5 2. Nf3 Nc6 3. Bb5 a6
//         \\ 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7
//         \\ 11. c4 c6 12. cxb5 axb5 13. Nc3 Bb7 14. Bg5 b4 15. Nb1 h6 16. Bh4 c5 17. dxe5
//         \\ Nxe4 18. Bxe7 Qxe7 19. exd6 Qf6 20. Nbd2 Nxd6 21. Nc4 Nxc4 22. Bxc4 Nb6
//         \\ 23. Ne5 Rae8 24. Bxf7+ Rxf7 25. Nxf7 Rxe1+ 26. Qxe1 Kxf7 27. Qe3 Qg5 28. Qxg5
//         \\ hxg5 29. b3 Ke6 30. a3 Kd6 31. axb4 cxb4 32. Ra5 Nd5 33. f3 Bc8 34. Kf2 Bf5
//         \\ 35. Ra7 g6 36. Ra6+ Kc5 37. Ke1 Nf4 38. g3 Nxh3 39. Kd2 Kb5 40. Rd6 Kc5 41. Ra6
//         \\ Nf2 42. g4 Bd3 43. Re6 1/2-1/2
//     ;

//     const game = try fromPgn(pgn, std.testing.allocator);
//     defer game.deinit();
// }

// test "parse pgn to fen" {
//     const pgn =
//         \\ 1. e4 d6
//         \\ 2. Nf3  Nf6
//         \\ 3. Bd3  e5
//         \\ 4. Qe2  Nc6
//         \\ 5. Bc4  Nb4
//         \\ 6. c3  Nc2+
//         \\ 7. Kd1  Nxa1
//         \\ 8. d4  Bg4
//         \\ 9. Bg5  h6
//         \\10. Bh4 g5
//         \\11. Bg3 c6
//         \\12. dxe5 dxe5+
//         \\13. Qd2 Bxf3+
//         \\14. gxf3 Qxd2+
//         \\15. Kxd2 O-O-O+
//         \\16. Kc1 Nd7
//         \\17. Nd2 Nb6
//         \\18. Bxe5 Nxc4
//         \\19. Bxh8 Rxd2
//         \\20. Rd1 Rxd1+
//         \\21. Kxd1 Nxb2+
//         \\22. Kc1 Nd3+
//         \\23. Kb1 Nb3
//         \\24. Kc2 Nbc5
//         \\25. c4 Ne1+
//         \\26. Kd1 Nxf3
//         \\27. Ke2 Nd7
//         \\28. Kxf3 a5
//         \\29. Bb2 b6
//         \\30. c5 Bd6
//         \\31. cxd6 Kb7
//         \\32. e5 c5
//         \\33. Ke4 Kc6
//         \\34. Kf5 1-0
//     ;

//     const game = try fromPgn(pgn, std.testing.allocator);
//     defer game.deinit();

//     const fen_str = fen.toFen(game.board);

//     try std.testing.expectStringStartsWith(&fen_str, "8/3n1p2/1pkP3p/p1p1PKp1/8/8/PB3P1P/8 b - - 3 34");
// }
