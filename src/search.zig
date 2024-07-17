const std = @import("std");
const builtin = @import("builtin");
const utils = @import("utils.zig");

const Thread = std.Thread;

const board_types = @import("board.zig");
const Board = board_types.Board;
const Position = board_types.Position;
const Move = board_types.Move;
const MoveType = board_types.MoveType;

const bit_set_types = @import("bitset.zig");

const MoveGen = @import("move_gen.zig");
const MoveList = MoveGen.MoveList;
const MoveGenInfo = MoveGen.MoveGenInfo;

const piece = @import("piece.zig");
const Color = piece.Color;
const Kind = piece.Kind;
const Piece = piece.Piece;

const precompute = @import("precompute.zig");
const Score = precompute.Score;

const evaluate = @import("eval.zig").evaluate;

const Allocator = std.mem.Allocator;

pub const GamePhase = enum { Opening, Middle, End };

pub const SearchOpts = struct {
    max_depth: usize = 100,
    time_limit_millis: usize = 1000,
    quiesce_depth: usize = 5,
};

const MIN_SCORE = std.math.minInt(Score);
const MAX_SCORE = std.math.maxInt(Score);

fn negate_score(x: Score) Score {
    return switch (x) {
        MIN_SCORE => MAX_SCORE,
        MAX_SCORE => MIN_SCORE,
        else => -%x,
    };
}

const TranspositionEntry = struct {
    depth: usize,
    score: Score,
};

const TranspostionTable = std.AutoHashMap(u64, TranspositionEntry);

fn score_move(ctx: MoveCompareCtx, move: Move) Score {
    var score: Score = 0;

    if (ctx.best_move) |best| {
        if (best.eql(move)) {
            return MAX_SCORE;
        }
    }

    const move_val = precompute.PIECE_SCORES.get(move.kind);

    if (move.move_flags.contains(MoveType.Castling)) {
        score += 100;
    }

    if (move.captured_kind) |k| {
        const captured_score = precompute.PIECE_SCORES.get(k);

        score += 10 * captured_score - move_val;
    } else {
        score += move_val;
    }

    if (move.promotion_kind) |k| {
        score += precompute.PIECE_SCORES.get(k);
    }

    if (ctx.gen_info.enemy_attacked_sqaures.isSet(move.end.toIndex())) {
        score -= (@divFloor(move_val, 2));
    }

    return score;
}

const MoveCompareCtx = struct {
    gen_info: MoveGenInfo,
    best_move: ?Move = null,
};

fn compare_moves(ctx: MoveCompareCtx, a: Move, b: Move) bool {
    // sort descending
    return score_move(ctx, a) > score_move(ctx, b);
}

const Self = @This();

const Diagnostics = struct {
    num_nodes_analyzed: usize = 0,
};

transposition: TranspostionTable,
board: *Board,
move_gen: MoveGen,
stop_search: Thread.ResetEvent,
best_move: ?Move,
best_score: Score,
search_opts: SearchOpts,
diagnostics: Diagnostics = .{},

pub fn init(allocator: Allocator, board: *Board, search_opts: SearchOpts) Allocator.Error!Self {
    var transposition = TranspostionTable.init(allocator);
    try transposition.ensureTotalCapacity(10_000);
    const move_gen = MoveGen{ .board = board };

    const stop_search = Thread.ResetEvent{};

    return Self{
        .board = board,
        .move_gen = move_gen,
        .transposition = transposition,
        .stop_search = stop_search,
        .best_move = null,
        .best_score = MIN_SCORE,
        .search_opts = search_opts,
    };
}

pub fn deinit(self: *Self) void {
    self.transposition.deinit();
}

/// update entry only if the passed in depth is greater than the stored
fn addToTransposition(self: *Self, hash: u64, score: Score, depth: usize) Allocator.Error!void {
    const maybe_entry = self.transposition.getEntry(hash);
    if (maybe_entry) |entry| {
        if (entry.value_ptr.depth < depth) {
            entry.value_ptr.* = .{ .depth = depth, .score = score };
        }
    } else {
        try self.transposition.put(hash, .{ .depth = depth, .score = score });
    }
}

/// Only get entry if stored depth is >= the requested depth
fn getFromTransposition(self: *Self, hash: u64, depth: usize) ?TranspositionEntry {
    const maybe_entry = self.transposition.get(hash);
    if (maybe_entry) |e| {
        if (e.depth >= depth) {
            return e;
        }
    }
    // self.diagnostics.num_nodes_analyzed += 1;
    return null;
}

// https://www.chessprogramming.org/Quiescence_Search
fn quiesceSearch(self: *Self, move_allocator: Allocator, depth: usize, alpha_init: Score, beta: Score) Allocator.Error!Score {
    const start_eval = evaluate(self.board.*);
    if (self.stop_search.isSet()) {
        return start_eval;
    }
    var alpha = alpha_init;

    if (depth == 0) {
        return start_eval;
    }

    if (start_eval >= beta)
        return beta;
    if (alpha < start_eval)
        alpha = start_eval;

    const generated_moves = try self.move_gen.getAllValidMoves(move_allocator, true);
    var moves = generated_moves.moves;
    defer moves.deinit();

    const gen_info = generated_moves.gen_info;
    const to_sort = try moves.toOwnedSlice();

    const sort_ctx = MoveCompareCtx{
        .gen_info = gen_info,
    };

    std.mem.sort(Move, to_sort, sort_ctx, compare_moves);

    for (to_sort) |move| {
        self.diagnostics.num_nodes_analyzed += 1;
        std.debug.assert(move.captured_kind != null);
        const meta = self.board.meta;
        self.board.makeMove(move);
        const score = -%try self.quiesceSearch(move_allocator, depth - 1, negate_score(beta), negate_score(alpha));
        self.board.unMakeMove(move, meta);

        if (score >= beta) {
            //  fail hard beta-cutoff
            return beta;
        }
        alpha = @max(alpha, score);

        if (self.stop_search.isSet()) {
            return alpha;
        }
    }

    return alpha;
}

pub fn search(self: *Self, move_allocator: Allocator, depth_from_root: usize, depth_remaing: usize, alpha: Score, beta: Score) Allocator.Error!Score {
    var best_eval = alpha;

    if (self.stop_search.isSet()) {
        return 0;
    }

    if (depth_remaing == 0) {
        const hash = self.board.zhash;
        if (self.getFromTransposition(hash, 0)) |e| {
            return e.score;
        }
        const score = try self.quiesceSearch(move_allocator, self.search_opts.quiesce_depth, alpha, beta);

        try self.addToTransposition(hash, score, 0);
        return score;
    }

    const generated_moves = try self.move_gen.getAllValidMoves(move_allocator, false);
    var moves = generated_moves.moves;
    defer moves.deinit();

    const gen_info = generated_moves.gen_info;

    if (moves.items.len == 0) {
        if (gen_info.king_attackers.count() > 0) {
            // checkmate
            return MIN_SCORE;
        }
        // draw
        return 0;
    }

    const to_sort = try moves.toOwnedSlice();

    const sort_ctx = MoveCompareCtx{
        .gen_info = gen_info,
        .best_move = if (depth_from_root == 0) self.best_move else null,
    };

    std.mem.sort(Move, to_sort, sort_ctx, compare_moves);

    for (to_sort) |move| {
        const meta = self.board.meta;
        self.board.makeMove(move);
        const hash = self.board.zhash;
        const score = if (self.getFromTransposition(hash, depth_remaing)) |e| blk: {
            break :blk e.score;
        } else blk: {
            const res = -%try self.search(
                move_allocator,
                depth_from_root + 1,
                depth_remaing - 1,
                negate_score(beta),
                negate_score(alpha),
            );
            break :blk res;
        };
        self.board.unMakeMove(move, meta);

        if (score >= beta) {
            //  fail hard beta-cutoff
            return beta;
        }
        best_eval = @max(best_eval, score);

        try self.addToTransposition(hash, score, depth_remaing);

        if (self.stop_search.isSet()) {
            return best_eval;
        }
    }

    return best_eval;
}

pub fn iterativeSearch(self: *Self, move_allocator: Allocator, max_depth: usize) Allocator.Error!?Move {
    self.stop_search.reset();
    self.best_score = MIN_SCORE;
    self.best_move = null;

    for (1..max_depth) |depth| {
        std.debug.print("checking at depth: {}\n", .{depth});
        self.diagnostics.num_nodes_analyzed = 0;
        const generated_moves = try self.move_gen.getAllValidMoves(move_allocator, false);
        const moves = generated_moves.moves;
        defer moves.deinit();

        for (moves.items) |move| {
            self.diagnostics.num_nodes_analyzed += 1;
            const meta = self.board.meta;
            // std.debug.print("checking {s}\n", .{move.toStrSimple()});
            self.board.makeMove(move);
            const enemy_score = try self.search(move_allocator, 0, depth - 1, MIN_SCORE, negate_score(self.best_score));
            const eval = negate_score(enemy_score);
            self.board.unMakeMove(move, meta);

            if (eval > self.best_score) {
                self.best_move = move;
                self.best_score = eval;
            }
            if (self.stop_search.isSet()) {
                std.debug.print("Check before stopping: {}\n", .{self.diagnostics.num_nodes_analyzed});
                return self.best_move;
            }
        }
        std.debug.print("Checked this iteration: {}\n", .{self.diagnostics.num_nodes_analyzed});
    }

    return self.best_move;
}

fn getCurrTimeInMilli() u64 {
    return @intCast(std.time.milliTimestamp());
}

fn monitorTimeLimit(stop_search: *Thread.ResetEvent, timeLimitMillis: u64) !void {
    const startTime = getCurrTimeInMilli();
    const endTime = startTime + timeLimitMillis;

    while (true) {
        const currentTime = getCurrTimeInMilli();
        if (currentTime >= endTime) {
            stop_search.set();
            break;
        }
        std.time.sleep(1 * std.time.ns_per_ms); // Sleep for 1 millisecond to avoid busy waiting
    }
}

pub fn findBestMove(self: *Self, move_allocator: Allocator) !?Move {
    var monitorThread = try std.Thread.spawn(.{}, monitorTimeLimit, .{ &(self.stop_search), self.search_opts.time_limit_millis });
    const best = try self.iterativeSearch(move_allocator, self.search_opts.max_depth);
    monitorThread.join();

    return best;
}

// pub fn findBestMove(self: *Self, move_allocator: Allocator, depth: usize) Allocator.Error!?Move {
//     var alpha: Score = MIN_SCORE;

//     const generated_moves = try self.move_gen.getAllValidMoves(move_allocator, false);
//     const moves = generated_moves.moves;
//     defer moves.deinit();

//     var bestMove: ?Move = null;

//     for (moves.items) |move| {
//         const meta = self.board.meta;
//         std.debug.print("checking {s}\n", .{move.toStrSimple()});
//         self.board.makeMove(move);
//         const enemy_score = try self.search(move_allocator, 0, depth - 1, MIN_SCORE, negate_score(alpha));
//         const eval = negate_score(enemy_score);
//         self.board.unMakeMove(move, meta);

//         if (eval > alpha) {
//             bestMove = move;
//             alpha = eval;
//         }
//     }
//     if (bestMove) |move| {
//         std.debug.print("best move: {s}\n", .{move.toStrSimple()});
//     } else {
//         std.debug.print("NO MOVE FOUND\n", .{});
//     }

//     return bestMove;
// }
