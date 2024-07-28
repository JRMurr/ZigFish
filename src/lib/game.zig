const std = @import("std");
const builtin = @import("builtin");
const utils = ZigFish.Utils;

const ZigFish = @import("root.zig");
const Board = ZigFish.Board;
const Position = ZigFish.Position;
const Move = ZigFish.Move;
const MoveType = ZigFish.MoveType;
const MoveFlags = ZigFish.MoveFlags;
const BoardMeta = ZigFish.BoardMeta;

const BoardBitSet = ZigFish.BoardBitSet;
const Dir = ZigFish.Dir;

const Piece = @import("piece.zig");
const Color = Color;
const Kind = Kind;

const precompute = @import("precompute.zig");
const Score = precompute.Score;

const Fen = ZigFish.Fen;

const Search = ZigFish.Search;

const MoveGen = ZigFish.MoveGen;
const MoveList = ZigFish.MoveList;

const Allocator = std.mem.Allocator;

const HistoryStack = std.ArrayList(BoardMeta);

pub const GameResult = enum {
    Draw,
    WhiteWin,
    BlackWin,
    InProgress,
};

pub const GameManager = struct {
    const Self = @This();

    allocator: Allocator,

    board: Board,
    history: HistoryStack,

    pub fn init(allocator: Allocator) Allocator.Error!Self {
        return Self.from_fen(allocator, Fen.START_POS);
    }

    pub fn reinitFen(self: *Self, fen_str: []const u8) void {
        self.history.clearAndFree();
        const board = Fen.parse(fen_str);

        self.board = board;
    }

    pub fn reinit(self: *Self) void {
        self.reinitFen(Fen.START_POS);
    }

    pub fn deinit(self: Self) void {
        self.history.deinit();
    }

    pub fn clone(self: *Self) !Self {
        const board_clone = self.board.clone();
        const history_clone = try self.history.clone();

        return Self{ .allocator = self.allocator, .board = board_clone, .history = history_clone };
    }

    pub fn from_fen(allocator: Allocator, fen_str: []const u8) Allocator.Error!Self {
        const board = Fen.parse(fen_str);
        const history = try HistoryStack.initCapacity(allocator, 30);

        return Self{
            .allocator = allocator,
            .board = board,
            .history = history,
        };
    }

    pub fn getPos(self: Self, pos: Position) ?Piece {
        return self.board.getPos(pos);
    }

    pub fn setPos(self: *Self, pos: Position, maybe_piece: ?Piece) void {
        self.board.setPos(pos, maybe_piece);
    }

    pub fn makeMove(self: *Self, move: *const Move) Allocator.Error!void {
        try self.history.append(self.board.meta);
        self.board.makeMove(move);
    }

    pub fn makeSimpleMove(self: *Self, move: ZigFish.SimpleMove) !void {
        const validMoves = try self.getValidMovesAt(move.start);
        for (validMoves.items()) |m| {
            if (move.promotion_kind) |pk| {
                if (m.promotion_kind == null) {
                    continue;
                }
                if (m.promotion_kind.? != pk) {
                    continue;
                }
            }

            if (m.end.eql(move.end)) {
                return try self.makeMove(&m);
            }
        }
        std.debug.panic("could not make simple move {}", .{move});
    }

    pub fn unMakeMove(self: *Self, move: *const Move) void {
        const meta = self.history.pop();
        self.board.unMakeMove(move, meta);
    }

    pub fn getAllValidMoves(
        self: *Self,
    ) Allocator.Error!MoveList {
        const move_gen = MoveGen{ .board = &self.board };
        const res = move_gen.getAllValidMoves(false);

        return res.moves;
    }

    pub fn getValidMovesAt(self: *Self, pos: Position) Allocator.Error!MoveList {
        const maybe_peice = self.getPos(pos);
        const move_gen = MoveGen{ .board = &self.board };

        var moves = MoveList.init();

        const p = if (maybe_peice) |p| p else return moves;

        const gen_info = move_gen.getGenInfo();

        move_gen.getValidMoves(&moves, &gen_info, pos, p, false);

        return moves;
    }

    pub fn findBestMove(self: *Self, search_opts: Search.SearchOpts) !?Move {
        var search = try Search.init(self.allocator, &self.board, search_opts);
        defer search.deinit();

        return search.findBestMove();
    }

    pub fn getSearch(self: *Self, search_opts: Search.SearchOpts) !Search {
        return try Search.init(self.allocator, &self.board, search_opts);
    }

    // https://www.chessprogramming.org/Perft
    pub fn perft(self: *Self, depth: usize, print_count_per_move: bool) Allocator.Error!usize {
        var nodes: usize = 0;
        if (depth == 0) {
            return 1;
        }

        const move_gen = MoveGen{ .board = &self.board };

        const moves = (move_gen.getAllValidMoves(false)).moves;

        if (depth == 1 and !print_count_per_move) {
            // dont need to actually make these last ones
            return moves.count();
        }

        for (moves.items()) |*move| {
            try self.makeMove(move);
            const num_leafs = try self.perft(depth - 1, false);
            if (print_count_per_move) {
                std.log.debug("{s}: {d}", .{ move.toStrSimple(), num_leafs });
            }
            nodes += num_leafs;
            self.unMakeMove(move);
        }

        return nodes;
    }
};

fn testZhashUnMake(game: *GameManager, print: bool) anyerror!void {
    const move_gen = MoveGen{ .board = &game.board };

    const moves = (move_gen.getAllValidMoves(false)).moves;

    for (moves.items()) |*move| {
        const start_hash = game.board.zhash;
        try game.makeMove(move);
        game.unMakeMove(move);
        const end_hash = game.board.zhash;

        if (print) std.log.debug("{s}: {d}\t{d}", .{ move.toStrSimple(), start_hash, end_hash });

        try std.testing.expectEqual(start_hash, end_hash);
    }
}

test "zhash updates correctly - start pos" {
    var game = try GameManager.init(std.testing.allocator);
    defer game.deinit();

    try testZhashUnMake(&game, false);
}

test "zhash updates correctly - could castle" {
    var game = try GameManager.from_fen(std.testing.allocator, "r3k2r/8/8/4b3/8/8/6P1/R3K2R w KQkq - 0 1");
    defer game.deinit();

    try testZhashUnMake(&game, false);
}

test "zhash updates correctly - could promote" {
    var game = try GameManager.from_fen(std.testing.allocator, "3r1q2/4P3/6K1/1k6/8/8/8/8 w - - 0 1");
    defer game.deinit();

    try testZhashUnMake(&game, false);
}

test "zhash updates correctly - en passant" {
    var game = try GameManager.from_fen(std.testing.allocator, "rnbqkbnr/p1pp1ppp/4p3/Pp6/8/8/1PPPPPPP/RNBQKBNR w KQkq b6 0 3");
    defer game.deinit();

    try testZhashUnMake(&game, false);
}

test "zhash updates correctly - many possible captures" {
    var game = try GameManager.from_fen(std.testing.allocator, "r1n1n1b1/1P1P1P1P/1N1N1N2/2RnQrRq/2pKp3/3BNQbQ/k7/4Bq2");
    defer game.deinit();

    try testZhashUnMake(&game, false);
}

test "perft base" {
    var game = try GameManager.init(std.testing.allocator);
    defer game.deinit();

    const perf = try game.perft(5, false);

    try std.testing.expectEqual(4_865_609, perf);
}

test "perft pos 4" {
    var game = try GameManager.from_fen(std.testing.allocator, "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8");
    defer game.deinit();

    try std.testing.expectEqual(62_379, try game.perft(3, false));
}

test "perft normal castling" {
    var game = try GameManager.from_fen(std.testing.allocator, "r3k2r/8/8/4b3/8/8/6P1/R3K2R w KQkq - 0 1");
    defer game.deinit();

    try std.testing.expectEqual(22994, try game.perft(3, false));
}

test "perft weird castling spot" {
    var game = try GameManager.from_fen(std.testing.allocator, "4kr1r/p6p/6p1/8/2P1n3/5NP1/P3PPBP/R3K1R1 b k - 4 26");
    defer game.deinit();

    try std.testing.expectEqual(13315, try game.perft(3, false));
}

test "perft test debug" {
    var game = try GameManager.from_fen(std.testing.allocator, "8/p1p1k2p/4b1p1/P7/2P1q3/4P1P1/1P5P/R3K3 w Q - 0 27");
    defer game.deinit();

    try std.testing.expectEqual(7139288, try game.perft(5, false));
}

// SLOW!!!!!
// test "perft pos 5 depth 5" {
//     var game = try GameManager.from_fen(std.testing.allocator, "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8");
//     defer game.deinit();

//     try std.testing.expectEqual(89_941_194, try game.perft(5, std.testing.allocator, false));
// }
