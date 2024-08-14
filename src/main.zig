const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib");
const ZigFish = @import("zigfish");

const Thread = std.Thread;

const SpriteManager = @import("./ui/sprite.zig");
const UiState = @import("./ui/state.zig");

const Position = ZigFish.Position;
const Piece = ZigFish.Piece;
const MoveList = ZigFish.MoveList;
const Move = ZigFish.Move;
const GameManager = ZigFish.GameManager;

const cell_size: usize = 150;
const screen_size: usize = cell_size * 8;
const sidebar_width: usize = cell_size * 3;

const MAX_DEPTH = 100;
const SEARCH_TIME = 5; // seconds
const QUIESCE_DEPTH = 5;
const PLAYER_COLOR = Piece.Color.White;
const AI_ON: bool = true;

const SearchRes = struct { move: ?Move, done_search: Thread.ResetEvent };

const Allocator = std.mem.Allocator;

fn searchInBackground(game: *GameManager, search_res: *SearchRes) !void {
    const move = try game.findBestMove(.{
        .max_depth = MAX_DEPTH,
        .time_limit_millis = SEARCH_TIME,
    });

    search_res.move = move;
    search_res.done_search.set();
}

inline fn getAllocator() Allocator {
    if (builtin.target.isWasm()) {
        return std.heap.wasm_allocator;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    return gpa.allocator();
}

fn mainLoop() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------

    rl.initAudioDevice(); // Initialize audio device
    rl.initWindow(screen_size + sidebar_width, screen_size, "ZigFish");
    defer rl.closeWindow(); // Close window and OpenGL context

    var ui_state = try UiState.init(getAllocator(), cell_size, .{
        .search_time = SEARCH_TIME,
        .ai_on = AI_ON,
        // .start_pos = "r1bqkb1r/pppp1ppp/2nn4/1B2p3/3P4/5N2/PPP2PPP/RNBQ1RK1 w kq - 1 6",
    });
    defer ui_state.deinit();

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        rl.clearBackground(rl.Color.black);
        try ui_state.update();

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        try ui_state.draw();

        //----------------------------------------------------------------------------------
    }
}

pub fn exit() void { // TODO: see if this can be called from wasm for better exits?
    rl.closeWindow();
}

pub fn main() void {
    mainLoop() catch |e| {
        std.log.warn("error running main: {}", .{e});
    };
}

test {
    @import("std").testing.refAllDecls(@This());
}

// var game = try GameManager.from_fen(gpa_allocator, "4kr1r/p6p/6p1/8/2P1n3/5NP1/P3PPBP/R3K1R1 b k - 4 26");

// an italian opening
// var game = try GameManager.from_fen(gpa_allocator, "r1bq1rk1/bpp2ppp/p2p1nn1/4p3/P1BPP3/2P2N1P/1P3PP1/RNBQR1K1 w - - 1 11");

// std.log.debug("moves: {}", .{try game.getAllValidMoves(move_allocator)});

// pin should be able to capture
// var game = try GameManager.from_fen(gpa_allocator, "8/2rk4/8/2p5/b3q3/1NRP4/2K5/8 w - - 0 1");

// about to promote
// var game = try GameManager.from_fen(gpa_allocator, "3r1q2/4P3/6K1/1k6/8/8/8/8 w - - 0 1");

// castling
// var game = try GameManager.from_fen(gpa_allocator, "r3k2r/8/8/4b3/8/8/6P1/R3K2R w KQkq - 0 1");

// postion 5 in perft examples
// var game = try GameManager.from_fen(gpa_allocator, "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8");
// rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPPKNnPP/RNBQ3R b - - 2 8
// var game = try GameManager.from_fen(gpa_allocator, "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPPKNnPP/RNBQ3R b - - 2 8");

// test positon for debugging
// var game = try GameManager.from_fen(gpa_allocator, "8/2p5/3p4/KP5r/6pk/8/4P1P1/8 w - - 1 1");

// const perf = try game.perft(6,  true);
// std.log.debug("nodes: {}", .{perf});

// const best_move = (try game.findBestMove( 6)).?;
// std.log.debug("search_res: {}", .{best_move});

// std.log.debug("score: {}", .{game.evaluate()});

// var attacked_sqaures = game.allAttackedSqaures(game.board.active_color.get_enemy());
