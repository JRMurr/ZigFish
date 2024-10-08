const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib");
const ZigFish = @import("zigfish");

const Thread = std.Thread;

const UiState = @import("./ui/state.zig");

const UiScale = UiState.UiScale;

const Position = ZigFish.Position;
const Piece = ZigFish.Piece;
const MoveList = ZigFish.MoveList;
const Move = ZigFish.Move;
const GameManager = ZigFish.GameManager;

const MAX_DEPTH = 100;
const SEARCH_TIME = 5; // seconds
const QUIESCE_DEPTH = 5;
const PLAYER_COLOR = Piece.Color.White;
const AI_ON: bool = true;

const Allocator = std.mem.Allocator;

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

    // rl.initAudioDevice(); // Initialize audio device
    rl.setConfigFlags(rl.ConfigFlags{
        // can still be manually resized but doesnt let browser do it automagically
        .window_resizable = !builtin.target.isWasm(),
        .vsync_hint = true,
    });

    var ui_state = try UiState.init(getAllocator(), .{
        .search_time = SEARCH_TIME,
        .ai_on = AI_ON,
        // .start_pos = "r1bqkb1r/pppp1ppp/2nn4/1B2p3/3P4/5N2/PPP2PPP/RNBQ1RK1 w kq - 1 6",
    });
    defer ui_state.deinit();

    const target = rl.RenderTexture2D.init(UiState.BOARD_SIZE + UiState.SIDEBAR_WIDTH, UiState.BOARD_SIZE);
    rl.setTextureFilter(target.texture, .texture_filter_anisotropic_16x);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        rl.clearBackground(rl.Color.black);
        UiScale.update();
        const scale_rect = UiScale.scale_rect();

        rl.setMouseOffset(@intFromFloat(-scale_rect.x), @intFromFloat(-scale_rect.y));
        rl.setMouseScale(1 / UiScale.scale, 1 / UiScale.scale);

        // rl.setMouseOffset(offsetX: i32, offsetY: i32)
        //SetMouseOffset(-(GetScreenWidth() - (gameScreenWidth*scale))*0.5f, -(GetScreenHeight() - (gameScreenHeight*scale))*0.5f);
        //SetMouseScale(1/scale, 1/scale);
        try ui_state.update();

        // Draw
        //----------------------------------------------------------------------------------

        {
            rl.beginTextureMode(target);
            rl.clearBackground(rl.Color.black);
            defer rl.endTextureMode();
            try ui_state.draw();
            // rl.drawText(rl.textFormat("Default Mouse: [%i , %i]", (int)mouse.x, (int)mouse.y), 350, 25, 20, GREEN);
            // rl.drawText(rl.textFormat("Virtual Mouse: [%i , %i]", (int)virtualMouse.x, (int)virtualMouse.y), 350, 55, 20, YELLOW);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        // need negative on height or its all flipped....
        // TODO: https://github.com/raysan5/raylib/blob/master/examples/core/core_window_letterbox.c
        // need to update the mouse offsets for clicking gui to still work
        const source_rect = rl.Rectangle.init(0, 0, @floatFromInt(target.texture.width), @floatFromInt(-target.texture.height));
        rl.drawTexturePro(target.texture, source_rect, UiScale.scale_rect(), rl.Vector2.zero(), 0, rl.Color.white);

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

// var attacked_squares = game.allAttackedSqaures(game.board.active_color.get_enemy());
