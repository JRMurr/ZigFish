const std = @import("std");

const ZigFish = @import("root.zig");

const GameManager = ZigFish.GameManager;

const Allocator = std.mem.Allocator;

pub const Move = ZigFish.Move;

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

test "parse pgn" {
    const pgn =
        \\ 1. e4 e5 2. Nf3 Nc6 3. Bb5 a6
        \\ 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7
        \\ 11. c4 c6 12. cxb5 axb5 13. Nc3 Bb7 14. Bg5 b4 15. Nb1 h6 16. Bh4 c5 17. dxe5
        \\ Nxe4 18. Bxe7 Qxe7 19. exd6 Qf6 20. Nbd2 Nxd6 21. Nc4 Nxc4 22. Bxc4 Nb6
        \\ 23. Ne5 Rae8 24. Bxf7+ Rxf7 25. Nxf7 Rxe1+ 26. Qxe1 Kxf7 27. Qe3 Qg5 28. Qxg5
        \\ hxg5 29. b3 Ke6 30. a3 Kd6 31. axb4 cxb4 32. Ra5 Nd5 33. f3 Bc8 34. Kf2 Bf5
        \\ 35. Ra7 g6 36. Ra6+ Kc5 37. Ke1 Nf4 38. g3 Nxh3 39. Kd2 Kb5 40. Rd6 Kc5 41. Ra6
        \\ Nf2 42. g4 Bd3 43. Re6 1/2-1/2
    ;

    const game = try fromPgn(pgn, std.testing.allocator);
    defer game.deinit();
}

test "parse pgn to fen" {
    const pgn =
        \\ 1. e4 d6 
        \\ 2. Nf3  Nf6 
        \\ 3. Bd3  e5 
        \\ 4. Qe2  Nc6 
        \\ 5. Bc4  Nb4 
        \\ 6. c3  Nc2+ 
        \\ 7. Kd1  Nxa1 
        \\ 8. d4  Bg4 
        \\ 9. Bg5  h6 
        \\10. Bh4 g5 
        \\11. Bg3 c6 
        \\12. dxe5 dxe5+ 
        \\13. Qd2 Bxf3+ 
        \\14. gxf3 Qxd2+ 
        \\15. Kxd2 O-O-O+ 
        \\16. Kc1 Nd7 
        \\17. Nd2 Nb6 
        \\18. Bxe5 Nxc4 
        \\19. Bxh8 Rxd2 
        \\20. Rd1 Rxd1+ 
        \\21. Kxd1 Nxb2+ 
        \\22. Kc1 Nd3+ 
        \\23. Kb1 Nb3 
        \\24. Kc2 Nbc5 
        \\25. c4 Ne1+ 
        \\26. Kd1 Nxf3 
        \\27. Ke2 Nd7 
        \\28. Kxf3 a5 
        \\29. Bb2 b6 
        \\30. c5 Bd6 
        \\31. cxd6 Kb7 
        \\32. e5 c5 
        \\33. Ke4 Kc6 
        \\34. Kf5 1-0
    ;

    const game = try fromPgn(pgn, std.testing.allocator);
    defer game.deinit();

    const fen_str = fen.toFen(game.board);

    try std.testing.expectStringStartsWith(&fen_str, "8/3n1p2/1pkP3p/p1p1PKp1/8/8/PB3P1P/8 b - - 3 34");
}
