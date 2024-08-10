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
const MoveList = ZigFish.MoveList;
const Piece = ZigFish.Piece;
const Color = Piece.Color;
const Kind = Piece.Kind;
const Precompute = ZigFish.Precompute;
const Score = ZigFish.Score;
const Eval = ZigFish.Eval;

const MIN_SCORE = Eval.MIN_SCORE;
const MAX_SCORE = Eval.MAX_SCORE;

const evaluate = Eval.evaluate;

const Allocator = std.mem.Allocator;

pub const GamePhase = enum { Opening, Middle, End };

pub const SearchOpts = struct {
    max_depth: usize = 100,
    time_limit_millis: ?usize = null,
    quiesce_depth: usize = 5,
    max_extensions: usize = 10,
};

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

// fn scoreAndSort(movesList: *MoveList, ctx: MoveCompareCtx) Allocator.Error![]MoveScored {
//     const moves = try movesList.toOwnedSlice();

//     var scored = try std.ArrayList(MoveScored).initCapacity(moves.len);

//     for (moves) |m| {
//         scored.appendAssumeCapacity(MoveScored.init(m, ctx));
//     }

//     const res = try scored.toOwnedSlice();

//     std.mem.sort(MoveScored, res, .{}, compareScored);

//     return res;
// }

const Self = @This();

const Diagnostics = struct {
    num_nodes_analyzed: usize = 0,
};

transposition: TranspostionTable,
allocator: Allocator,
board: *Board,
stop_search: Thread.ResetEvent,
search_done: Thread.ResetEvent,
move_gen: *MoveGen,
best_move: ?Move,
best_score: Score,
search_opts: SearchOpts,
diagnostics: Diagnostics = .{},

pub fn init(allocator: Allocator, board: *Board, search_opts: SearchOpts) Allocator.Error!Self {
    var transposition = TranspostionTable.init(allocator);
    try transposition.ensureTotalCapacity(10_000);

    return Self{
        .allocator = allocator,
        .board = board,
        .transposition = transposition,
        .stop_search = Thread.ResetEvent{},
        .best_move = null,
        .best_score = MIN_SCORE,
        .search_opts = search_opts,
        .search_done = Thread.ResetEvent{},
        .move_gen = try MoveGen.init(allocator, board),
    };
}

fn getAllValidMoves(self: *Self, comptime captures_only: bool) ZigFish.MoveGen.GeneratedMoves {
    return self.move_gen.getAllValidMoves(captures_only);
}

pub fn deinit(self: *Self) void {
    self.transposition.deinit();
    self.allocator.destroy(self.move_gen);
    self.* = undefined;
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
    depth: usize,
    alpha_init: Score,
    beta: Score,
) Allocator.Error!SearchRes {
    const start_eval = evaluate(self.board);
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

    const generated_moves = &(self.getAllValidMoves(true));
    var moves = generated_moves.moves;

    const gen_info = generated_moves.gen_info;

    const sort_ctx = MoveCompareCtx{
        .gen_info = gen_info,
    };

    // const sorted = try scoreAndSort(&moves, sort_ctx);
    moves.sort(sort_ctx, compare_moves);

    var best_move: ?Move = null;

    // const start_hash = self.board.zhash;
    // const start_fen = ZigFish.Fen.toFen(self.board);

    for (moves.items()) |*move| {
        // if (start_hash != self.board.zhash) {
        //     std.debug.panic(
        //         "Q start_hash: {}\tboard_hash {}\tmove_idx: {}\nmove {}\nstart_fen: {s}\n  end_fen: {s}\n",
        //         .{ start_hash, self.board.zhash, idx, move, start_fen, ZigFish.Fen.toFen(self.board) },
        //     );
        // }
        // const move = move_score.move;
        self.diagnostics.num_nodes_analyzed += 1;
        std.debug.assert(move.captured_kind != null);

        // make, score, unmake
        const meta = self.board.meta;
        self.board.makeMove(move);
        const res = try self.quiesceSearch(depth - 1, negate_score(beta), negate_score(alpha));
        const score = negate_score(res.score);
        self.board.unMakeMove(move, meta);

        if (score >= beta) {
            //  fail hard beta-cutoff
            return SearchRes.initCut(beta, move.*);
        }
        if (score > alpha) {
            alpha = score;
            best_move = move.*;
        }

        if (self.stop_search.isSet()) {
            return SearchRes.canceledWithBest(alpha, best_move);
        }
    }
    return SearchRes.initBest(alpha, best_move);
}

pub fn search(
    self: *Self,
    depth_from_root: usize,
    depth_remaing: usize,
    num_extensions: usize,
    alpha_int: Score,
    beta: Score,
) Allocator.Error!SearchRes {
    var alpha = alpha_int;

    if (self.stop_search.isSet()) {
        return SearchRes.canceled(0);
    }

    if (depth_remaing == 0) {
        const hash = self.board.zhash;
        if (self.getFromTransposition(hash, 0)) |e| {
            return e.search_res;
        }
        const score = try self.quiesceSearch(self.search_opts.quiesce_depth, alpha, beta);
        if (self.stop_search.isSet()) {
            return score;
        }
        try self.addToTransposition(hash, score, 0);
        return score;
    }

    const generated_moves = &(self.getAllValidMoves(false));
    var moves = generated_moves.moves;

    const gen_info = generated_moves.gen_info;

    if (moves.items().len == 0) {
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

    moves.sort(sort_ctx, compare_moves);

    var best_move: ?Move = null;
    const move_slice = moves.items();
    // const start_hash = self.board.zhash;
    // const start_fen = ZigFish.Fen.toFen(self.board);

    for (move_slice) |*move| {

        // std.debug.print("move: {s}\n", .{move.toStrSimple()});
        // if (start_hash != self.board.zhash) {
        //     std.debug.panic(
        //         "start_hash: {}\tboard_hash {}\tmove_idx: {}\nmove {}\nstart_fen: {s}\n  end_fen: {s}\n",
        //         .{ start_hash, self.board.zhash, idx, move, start_fen, ZigFish.Fen.toFen(self.board) },
        //     );
        // }

        if (self.stop_search.isSet()) {
            return SearchRes.canceledWithBest(alpha, best_move);
        }

        // const move = move_scored.move;
        const meta = self.board.meta;
        self.board.makeMove(move);
        const hash = self.board.zhash;
        const score = if (self.getFromTransposition(hash, depth_remaing)) |e| blk: {
            break :blk e.search_res.score;
        } else blk: {
            var depth_remaing_updated = depth_remaing - 1;
            var num_extensions_updated = num_extensions;
            if (num_extensions_updated < self.search_opts.max_extensions and self.board.king_in_check()) {
                depth_remaing_updated += 1;
                num_extensions_updated += 1;
            }

            const search_res = try self.search(
                depth_from_root + 1,
                depth_remaing_updated,
                num_extensions_updated,
                negate_score(beta),
                negate_score(alpha),
            );
            break :blk negate_score(search_res.score);
        };
        self.board.unMakeMove(move, meta);

        if (score >= beta) {
            //  fail hard beta-cutoff
            return SearchRes.initCut(beta, move.*);
        }

        if (score > alpha) {
            alpha = score;
            best_move = move.*;
        }

        if (self.stop_search.isSet()) {
            return SearchRes.canceledWithBest(alpha, best_move);
        }

        try self.addToTransposition(hash, SearchRes.normal(score), depth_remaing);
    }

    return SearchRes.initBest(alpha, best_move);
}

pub fn iterativeSearch(self: *Self, max_depth: usize) Allocator.Error!void {
    self.stop_search.reset();
    self.search_done.reset();
    self.best_score = MIN_SCORE;
    self.best_move = null;

    for (1..max_depth) |depth| {
        std.log.debug("checking at depth: {}", .{depth});
        self.diagnostics.num_nodes_analyzed = 0;
        const generated_moves = &(self.getAllValidMoves(false));
        const moves = generated_moves.moves;

        if (moves.count() == 0) {
            break;
        }

        for (moves.items()) |*move| {
            // std.debug.print("move: {s}\n", .{move.toStrSimple()});
            self.diagnostics.num_nodes_analyzed += 1;
            const meta = self.board.meta;
            // std.log.debug("checking {s}", .{move.toStrSimple()});
            self.board.makeMove(move);
            const enemy_score = try self.search(0, depth - 1, 0, MIN_SCORE, MAX_SCORE);
            const eval = negate_score(enemy_score.score);
            self.board.unMakeMove(move, meta);

            if (eval > self.best_score) {
                self.best_move = move.*;
                self.best_score = eval;
            }
            if (self.stop_search.isSet()) {
                // std.log.debug("Check before stopping: {}", .{self.diagnostics.num_nodes_analyzed});
                self.search_done.set();
                return;
            }
        }
        // std.log.debug("Checked this iteration: {}", .{self.diagnostics.num_nodes_analyzed});
    }
    self.search_done.set();
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

pub fn stopSearch(self: *Self) !?Move {
    self.stop_search.set();
    try self.search_done.timedWait(1000 * std.time.ns_per_ms);
    return self.best_move;
}

pub fn startSearch(
    self: *Self,
) !void {
    try self.iterativeSearch(self.search_opts.max_depth);
}

pub fn findBestMove(
    self: *Self,
) !?Move {
    if (self.search_opts.time_limit_millis) |time| {
        const monitorThread = try std.Thread.spawn(.{}, monitorTimeLimit, .{ &(self.stop_search), time });
        monitorThread.detach();
    }
    try self.iterativeSearch(self.search_opts.max_depth);
    std.log.debug("eval: {}", .{self.best_score});
    return self.best_move;
}

// TODO: copied from game, should probably live here anyway
pub fn perft(self: *Self, depth: usize, print_count_per_move: bool) Allocator.Error!usize {
    var nodes: usize = 0;
    if (depth == 0) {
        return 1;
    }

    const moves = (self.getAllValidMoves(false)).moves;

    if (depth == 1 and !print_count_per_move) {
        // dont need to actually make these last ones
        return moves.count();
    }

    for (moves.items()) |*move| {
        const meta = self.board.meta;
        self.board.makeMove(move);
        const num_leafs = try self.perft(depth - 1, false);
        if (print_count_per_move) {
            std.log.debug("{s}: {d}", .{ move.toStrSimple(), num_leafs });
        }
        nodes += num_leafs;
        self.board.unMakeMove(move, meta);
    }

    return nodes;
}

test "all" {
    std.testing.refAllDecls(@This());
}

test "find best move" {
    var board = ZigFish.Fen.START_BOARD;

    var test_search = try Self.init(std.testing.allocator, &board, .{ .time_limit_millis = 100 });
    defer test_search.deinit();

    const move = try test_search.findBestMove();

    try std.testing.expect(move != null);
}
