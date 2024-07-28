const std = @import("std");
const mecha = @import("mecha");

const ZigFish = @import("root.zig");

const GameManager = ZigFish.GameManager;

const Allocator = std.mem.Allocator;

pub const Move = ZigFish.Move;

const zig_str = []u8;
// based on https://github.com/Hejsil/mecha/blob/master/example/json.zig
const Parser = struct {
    pub const Pgn = struct {
        tags: []Tag,
        moves: []zig_str,
        result: zig_str,
    };

    pub const pgn = mecha.combine(.{
        many_tags,
        new_line.discard(),
        many_moves,
        ws.discard(),
        result,
    }).map(mecha.toStruct(Pgn));

    const space = mecha.utf8.char(0x0020);
    const new_line = mecha.utf8.char(0x000A);
    const carriage_return = mecha.utf8.char(0x000D);
    const tab = mecha.utf8.char(0x0009);
    const ws = mecha.oneOf(.{
        space,
        new_line,
        carriage_return,
        tab,
    }).many(.{ .collect = false }).discard();

    const chars = char.many(.{ .collect = false });

    const char = mecha.oneOf(.{
        mecha.utf8.range(0x0020, '"' - 1),
        mecha.utf8.range('"' + 1, '\\' - 1),
        mecha.utf8.range('\\' + 1, 0x10FFFF),
        mecha.combine(.{
            mecha.utf8.char('\\').discard(),
            escape,
        }),
    });

    const escape = mecha.oneOf(.{
        mecha.utf8.char('"'),
        mecha.utf8.char('\\'),
        mecha.utf8.char('/'),
        mecha.utf8.char('b'),
        mecha.utf8.char('f'),
        mecha.utf8.char('n'),
        mecha.utf8.char('r'),
        mecha.utf8.char('t'),
        // mecha.combine(.{ mecha.utf8.char('u'), hex, hex, hex, hex }),
    });

    fn token(comptime parser: anytype) mecha.Parser(void) {
        return mecha.combine(.{ parser.discard(), ws });
    }

    const lbracket = token(mecha.utf8.char('['));
    const rbracket = token(mecha.utf8.char(']'));

    const quote_string = mecha.combine(.{
        mecha.utf8.char('"').discard(),
        chars,
        mecha.utf8.char('"').discard(),
    });

    const Tag = struct { name: []const u8, value: []const u8 };

    const tag = mecha.combine(.{
        lbracket.discard(),
        chars,
        space.discard(),
        quote_string,
        rbracket.discard(),
    }).map(mecha.toStruct(Tag));

    const many_tags = mecha.many(tag, .{ .separator = ws });

    const castle = mecha.oneOf(.{
        mecha.string("O-O-O"),
        mecha.string("O-O"),
    });

    const piece_char = mecha.oneOf(.{
        mecha.utf8.char('K'),
        mecha.utf8.char('N'),
        mecha.utf8.char('B'),
        mecha.utf8.char('R'),
    });

    const file = mecha.utf8.range('a', 'h');
    const rank = mecha.utf8.range('1', '8');

    const square = mecha.combine(.{ file, rank });

    const promotion = mecha.combine(.{ mecha.utf8.char('='), piece_char });

    const check_or_mate = mecha.oneOf(.{ mecha.utf8.char('+'), mecha.utf8.char('#') });
    const move_start = mecha.combine(.{ mecha.opt(piece_char), mecha.opt(file), mecha.opt(rank) });
    const non_castle = mecha.combine(.{ move_start, square, mecha.opt(promotion) });
    const move_no_check = mecha.oneOf(.{
        non_castle,
        castle,
    });

    const move = mecha.combine(.{ move_no_check, mecha.opt(check_or_mate) });

    const result = mecha.oneOf(.{
        mecha.string("1/2-1/2"),
        mecha.string("1-0"),
        mecha.string("0-1"),
        mecha.string("*"),
    });

    const digits = mecha.intToken(.{ .base = 10, .parse_sign = false });
    const move_num = mecha.combine(.{ digits, mecha.utf8.char('.') });

    const full_move = mecha.combine(.{
        move_num.discard(),
        move,
        ws.discard(),
        mecha.oneOf(.{ move, result }),
    });

    const many_moves = mecha.many(full_move, .{ .separator = ws });
};

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

test "parse pgn mecha" {
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
        \\ O-O *
    ;

    const testing = std.testing;
    const allocator = testing.allocator;
    const a = (try Parser.pgn.parse(allocator, pgn_str)).value;

    std.debug.print("res: {}\n", .{a});

    try testing.expectEqualStrings(a.moves[0], "e4");
}

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
