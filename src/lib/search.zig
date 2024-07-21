const std = @import("std");
const builtin = @import("builtin");
const utils = ZigFish.Utils;

const Thread = std.Thread;

const ZigFish = @import("root.zig");
const Board = ZigFish.Board;
const Position = ZigFish.Position;
const Move = ZigFish.Move;
const MoveType = ZigFish.MoveType;
const MoveGen = ZigFish.MoveGen;
const MoveList = MoveGen.MoveList;
const Piece = ZigFish.Piece;
const Color = Piece.Color;
const Kind = Piece.Kind;
const Precompute = ZigFish.Precompute;
const Score = ZigFish.Score;

const evaluate = @import("eval.zig").evaluate;

const Allocator = std.mem.Allocator;

pub const GamePhase = enum { Opening, Middle, End };

pub const SearchOpts = struct {
    max_depth: usize = 100,
    time_limit_millis: ?usize = null,
    quiesce_depth: usize = 5,
    max_extensions: usize = 10,
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

const MoveScored = struct {
    move: Move,
    score: Score,

    pub fn init(move: Move, ctx: MoveCompareCtx) MoveScored {
        return .{
            .move = move,
            .score = score_move(ctx, move),
        };
    }
};

const TranspositionEntry = struct {
    depth: usize,
    search_res: SearchRes,
};

const TranspostionTable = std.AutoHashMap(u64, TranspositionEntry);

fn score_move(ctx: MoveCompareCtx, move: Move) Score {
    var score: Score = 0;

    if (ctx.best_move) |best| {
        if (best.eql(move)) {
            return MAX_SCORE;
        }
    }

    const move_val = Precompute.PIECE_SCORES.get(move.kind);

    if (move.move_flags.contains(MoveType.Castling)) {
        score += 100;
    }

    if (move.captured_kind) |k| {
        const captured_score = Precompute.PIECE_SCORES.get(k);

        score += 10 * captured_score - move_val;
    }
    //  else {
    //     score += move_val;
    // }

    if (move.promotion_kind) |k| {
        score += Precompute.PIECE_SCORES.get(k);
    }
    const attack_info = ctx.gen_info.attack_info;

    if (attack_info.attackers[@intFromEnum(Kind.Pawn)].isSet(move.end.toIndex())) {
        score -= (@divFloor(move_val, 4));
    } else if (attack_info.attacked_sqaures.isSet(move.end.toIndex())) {
        score -= (@divFloor(move_val, 8));
    }

    return score;
}

const MoveCompareCtx = struct {
    gen_info: MoveGen.MoveGenInfo,
    best_move: ?Move = null,
};

fn compare_moves(ctx: MoveCompareCtx, a: Move, b: Move) bool {
    // sort descending
    return score_move(ctx, a) > score_move(ctx, b);
}

fn compareScored(_: @TypeOf(.{}), a: MoveScored, b: MoveScored) bool {
    // sort descending
    return a.score > b.score;
}

fn scoreAndSort(movesList: *MoveList, move_allocator: Allocator, ctx: MoveCompareCtx) Allocator.Error![]MoveScored {
    const moves = try movesList.toOwnedSlice();

    var scored = try std.ArrayList(MoveScored).initCapacity(move_allocator, moves.len);

    for (moves) |m| {
        scored.appendAssumeCapacity(MoveScored.init(m, ctx));
    }

    const res = try scored.toOwnedSlice();

    std.mem.sort(MoveScored, res, .{}, compareScored);

    return res;
}

const Self = @This();

const Diagnostics = struct {
    num_nodes_analyzed: usize = 0,
};

transposition: TranspostionTable,
board: *Board,
move_gen: MoveGen,
stop_search: Thread.ResetEvent,
search_done: Thread.ResetEvent,
best_move: ?Move,
best_score: Score,
search_opts: SearchOpts,
diagnostics: Diagnostics = .{},

pub fn init(allocator: Allocator, board: *Board, search_opts: SearchOpts) Allocator.Error!Self {
    var transposition = TranspostionTable.init(allocator);
    try transposition.ensureTotalCapacity(10_000);
    const move_gen = MoveGen{ .board = board };

    return Self{
        .board = board,
        .move_gen = move_gen,
        .transposition = transposition,
        .stop_search = Thread.ResetEvent{},
        .best_move = null,
        .best_score = MIN_SCORE,
        .search_opts = search_opts,
        .search_done = Thread.ResetEvent{},
    };
}

pub fn deinit(self: *Self) void {
    self.transposition.deinit();
}

/// update entry only if the passed in depth is greater than the stored
fn addToTransposition(self: *Self, hash: u64, search_res: SearchRes, depth: usize) Allocator.Error!void {
    if (search_res.was_canceled) {
        return;
    }
    const maybe_entry = self.transposition.getEntry(hash);
    if (maybe_entry) |entry| {
        if (entry.value_ptr.depth < depth) {
            entry.value_ptr.* = .{ .depth = depth, .search_res = search_res };
        }
    } else {
        try self.transposition.put(hash, .{ .depth = depth, .search_res = search_res });
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

const SearchRes = struct {
    score: Score,
    best_move: ?Move = null,
    refutation: ?Move = null,
    was_canceled: bool = false,

    pub fn normal(score: Score) SearchRes {
        return .{ .score = score, .was_canceled = false };
    }

    pub fn initBest(alpha: Score, best_move: ?Move) SearchRes {
        return .{ .score = alpha, .best_move = best_move, .was_canceled = false };
    }

    pub fn initCut(beta: Score, refutation: Move) SearchRes {
        return .{ .score = beta, .refutation = refutation, .was_canceled = false };
    }

    pub fn canceledWithBest(score: Score, best_move: ?Move) SearchRes {
        return .{ .score = score, .best_move = best_move, .was_canceled = true };
    }

    pub fn canceled(score: Score) SearchRes {
        return .{ .score = score, .was_canceled = true };
    }
};

// https://www.chessprogramming.org/Quiescence_Search
fn quiesceSearch(
    self: *Self,
    move_allocator: Allocator,
    depth: usize,
    alpha_init: Score,
    beta: Score,
) Allocator.Error!SearchRes {
    const start_eval = evaluate(self.board.*);
    if (self.stop_search.isSet()) {
        return SearchRes.canceled(start_eval);
    }
    var alpha = alpha_init;

    if (depth == 0) {
        return SearchRes.normal(start_eval);
    }

    if (start_eval >= beta)
        return SearchRes.normal(beta);
    if (alpha < start_eval)
        alpha = start_eval;

    const generated_moves = try self.move_gen.getAllValidMoves(move_allocator, true);
    var moves = generated_moves.moves;
    defer moves.deinit();

    const gen_info = generated_moves.gen_info;

    const sort_ctx = MoveCompareCtx{
        .gen_info = gen_info,
    };

    const sorted = try scoreAndSort(&moves, move_allocator, sort_ctx);

    var best_move: ?Move = null;

    for (sorted) |move_score| {
        const move = move_score.move;
        self.diagnostics.num_nodes_analyzed += 1;
        std.debug.assert(move.captured_kind != null);

        // make, score, unmake
        const meta = self.board.meta;
        self.board.makeMove(move);
        var res = try self.quiesceSearch(move_allocator, depth - 1, negate_score(beta), negate_score(alpha));
        res.score = negate_score(res.score);
        self.board.unMakeMove(move, meta);

        if (res.score >= beta) {
            //  fail hard beta-cutoff
            return SearchRes.initCut(beta, move);
        }
        if (res.score > alpha) {
            alpha = res.score;
            best_move = move;
        }

        if (self.stop_search.isSet()) {
            return SearchRes.initBest(alpha, best_move);
        }
    }
    return SearchRes.initBest(alpha, best_move);
}

pub fn search(
    self: *Self,
    move_allocator: Allocator,
    depth_from_root: usize,
    depth_remaing: usize,
    num_extensions: usize,
    alpha_int: Score,
    beta: Score,
) Allocator.Error!SearchRes {
    var best_eval = alpha_int;

    if (self.stop_search.isSet()) {
        return SearchRes.canceled(0);
    }

    if (depth_remaing == 0) {
        const hash = self.board.zhash;
        if (self.getFromTransposition(hash, 0)) |e| {
            return e.search_res;
        }
        const score = try self.quiesceSearch(move_allocator, self.search_opts.quiesce_depth, alpha_int, beta);
        if (self.stop_search.isSet()) {
            return score;
        }
        try self.addToTransposition(hash, score, 0);
        return score;
    }

    const generated_moves = try self.move_gen.getAllValidMoves(move_allocator, false);
    var moves = generated_moves.moves;
    defer moves.deinit();

    const gen_info = generated_moves.gen_info;

    if (moves.items.len == 0) {
        if (gen_info.attack_info.king_attackers.count() > 0) {
            // checkmate
            return SearchRes.normal(MIN_SCORE);
        }
        // draw
        return SearchRes.normal(0);
    }

    var prev_best_move: ?Move = null;

    if (depth_from_root == 0) {
        prev_best_move = self.best_move;
    } else if (self.transposition.get(self.board.zhash)) |e| {
        const prev_res = e.search_res;
        prev_best_move = prev_res.best_move orelse prev_res.refutation;
    }

    const sort_ctx = MoveCompareCtx{
        .gen_info = gen_info,
        .best_move = prev_best_move,
    };

    const sorted = try scoreAndSort(&moves, move_allocator, sort_ctx);

    var best_move: ?Move = null;

    for (sorted) |move_scored| {
        const move = move_scored.move;
        const meta = self.board.meta;
        self.board.makeMove(move);
        const hash = self.board.zhash;
        const res = if (self.getFromTransposition(hash, depth_remaing)) |e| blk: {
            break :blk e.search_res;
        } else blk: {
            var depth_remaing_updated = depth_remaing - 1;
            var num_extensions_updated = num_extensions;
            if (num_extensions_updated < self.search_opts.max_extensions and self.board.king_in_check()) {
                depth_remaing_updated += 1;
                num_extensions_updated += 1;
            }

            var search_res = try self.search(
                move_allocator,
                depth_from_root + 1,
                depth_remaing_updated,
                num_extensions_updated,
                negate_score(beta),
                negate_score(best_eval),
            );
            search_res.score = negate_score(search_res.score);
            break :blk search_res;
        };
        self.board.unMakeMove(move, meta);

        if (res.score >= beta) {
            //  fail hard beta-cutoff
            return SearchRes.initCut(beta, move);
        }

        if (res.score > best_eval) {
            best_eval = res.score;
            best_move = move;
        }

        if (self.stop_search.isSet()) {
            return SearchRes.canceledWithBest(best_eval, best_move);
        }

        try self.addToTransposition(hash, res, depth_remaing);
    }

    return SearchRes.initBest(best_eval, best_move);
}

pub fn iterativeSearch(self: *Self, move_allocator: Allocator, max_depth: usize) Allocator.Error!?Move {
    self.stop_search.reset();
    self.search_done.reset();
    self.best_score = MIN_SCORE;
    self.best_move = null;

    for (1..max_depth) |depth| {
        std.log.debug("checking at depth: {}", .{depth});
        self.diagnostics.num_nodes_analyzed = 0;
        const generated_moves = try self.move_gen.getAllValidMoves(move_allocator, false);
        const moves = generated_moves.moves;
        defer moves.deinit();

        for (moves.items) |move| {
            self.diagnostics.num_nodes_analyzed += 1;
            const meta = self.board.meta;
            // std.log.debug("checking {s}", .{move.toStrSimple()});
            self.board.makeMove(move);
            const enemy_score = try self.search(move_allocator, 0, depth - 1, 0, MIN_SCORE, negate_score(self.best_score));
            const eval = negate_score(enemy_score.score);
            self.board.unMakeMove(move, meta);

            if (eval > self.best_score) {
                self.best_move = move;
                self.best_score = eval;
            }
            if (self.stop_search.isSet()) {
                std.log.debug("Check before stopping: {}", .{self.diagnostics.num_nodes_analyzed});
                self.search_done.set();
                return self.best_move;
            }
        }
        std.log.debug("Checked this iteration: {}", .{self.diagnostics.num_nodes_analyzed});
    }
    self.search_done.set();
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

pub fn stopSearch(self: *Self) ?Move {
    self.stop_search.set();
    self.search_done.wait();
    return self.best_move;
}

pub fn startSearch(self: *Self, move_allocator: Allocator) !void {
    _ = try self.iterativeSearch(move_allocator, self.search_opts.max_depth);
}

pub fn findBestMove(self: *Self, move_allocator: Allocator) !?Move {
    if (self.search_opts.time_limit_millis) |time| {
        const monitorThread = try std.Thread.spawn(.{}, monitorTimeLimit, .{ &(self.stop_search), time });
        monitorThread.detach();
    }
    const best = try self.iterativeSearch(move_allocator, self.search_opts.max_depth);
    std.log.debug("eval: {}", .{self.best_score});
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
//         std.log.debug("checking {s}", .{move.toStrSimple()});
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
//         std.log.debug("best move: {s}", .{move.toStrSimple()});
//     } else {
//         std.log.debug("NO MOVE FOUND", .{});
//     }

//     return bestMove;
// }

test "all" {
    std.testing.refAllDecls(@This());
}
