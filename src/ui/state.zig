const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib");
const ZigFish = @import("zigfish");

const BoardUI = @import("./board_ui.zig");
const Gui = @import("gui.zig");

const Thread = std.Thread;

const Position = ZigFish.Position;
const Piece = ZigFish.Piece;
const MoveList = ZigFish.MoveList;
const Move = ZigFish.Move;
const GameManager = ZigFish.GameManager;

const SearchRes = struct { move: ?Move, done_search: Thread.ResetEvent };

pub const CELL_SIZE: usize = if (builtin.target.isWasm()) 90 else 150;
// pub const CELL_SIZE: usize = 90;
pub const BOARD_SIZE: usize = CELL_SIZE * 8;
pub const SIDEBAR_WIDTH: usize = CELL_SIZE * 3;

// these are the "target" sizes, we will scale to match this ratio
// https://github.com/raysan5/raylib/blob/master/examples/core/core_smooth_pixelperfect.c
pub const GAME_WIDTH: usize = BOARD_SIZE + SIDEBAR_WIDTH;
pub const GAME_HEIGHT: usize = BOARD_SIZE;

pub const UiScale = struct {
    // a lil gross but global vars for scale....
    pub var scale: f32 = 1;
    // var x: f32 = 1;
    // var y: f32 = 1;

    pub fn update() void {
        const width: f32 = @floatFromInt(rl.getScreenWidth());
        const height: f32 = @floatFromInt(rl.getScreenHeight());

        const width_ratio = width / @as(f32, @floatFromInt(GAME_WIDTH));
        const height_ratio = height / @as(f32, @floatFromInt(GAME_HEIGHT));

        scale = @min(width_ratio, height_ratio);
    }

    pub fn screen_width() f32 {
        return @floatFromInt(rl.getScreenWidth());
    }

    pub fn screen_height() f32 {
        return @floatFromInt(rl.getScreenHeight());
    }

    pub fn game_width() f32 {
        return @floatFromInt(GAME_WIDTH);
    }

    pub fn game_height() f32 {
        return @floatFromInt(GAME_HEIGHT);
    }

    pub fn scale_rect() rl.Rectangle {
        const scaled_width: f32 = GAME_WIDTH * scale;
        const scaled_height: f32 = GAME_HEIGHT * scale;

        return rl.Rectangle.init(
            (screen_width() - scaled_width) * 0.5,
            (screen_height() - scaled_height) * 0.5,
            scaled_width,
            scaled_height,
        );

        // return rl.Rectangle.init(
        //     -scale,
        //     -scale,
        //     screen_width() + (scale * 2),
        //     screen_height() + (scale * 2),
        // );
    }
};

const MovingPiece = struct {
    start: Position,
    piece: Piece,
    valid_moves: MoveList,
};

const Allocator = std.mem.Allocator;

pub const GameOptions = struct {
    /// seconds
    search_time: f32 = 5.0,
    player_color: Piece.Color = Piece.Color.White,
    ai_on: bool = true,
    use_opening_book: bool = true,
    start_pos: ?[]const u8 = null,
};

const MAX_DEPTH = 100;

fn searchInBackground(game: *GameManager, search_res: *SearchRes, search_opts: ZigFish.Search.SearchOpts, game_opts: *const GameOptions) !void {
    var cloned_game = try game.clone();

    const opening_dist: ?ZigFish.NormalDist = if (game_opts.use_opening_book) .{ .mean = 20, .std_dev = 20 } else null;

    const move = try cloned_game.findBestMove(search_opts, opening_dist);

    search_res.move = move;
    search_res.done_search.set();
}

fn sub_ignore_overflow(a: anytype, b: anytype) @TypeOf(a, b) {
    return a -| b;
}

const ClampedMousePos = struct {
    x: usize,
    y: usize,
};

const UiState = @This();

pub const MoveHist = struct {
    /// Move played
    move: Move,
    /// The board after the move was played
    board: ZigFish.Board,
};

const OPENING_PGN = if (builtin.target.isWasm()) "" else @embedFile("../openings/Balsa_v110221.pgn");

game: GameManager,
options: GameOptions,
move_history: std.ArrayList(MoveHist),
board_ui: BoardUI,
gui: Gui,
search_res: SearchRes,
// scale: UiScale,
search_thread: ?Thread = null,
moving_piece: ?MovingPiece = null,
hist_index: ?usize = null,
game_status: ZigFish.GameStatus,

pub fn init(allocator: Allocator, options: GameOptions) !UiState {
    // TODO: make a "base unit" for sizing. Use this everywhere. Can update on resizes to keep scale
    rl.initWindow(BOARD_SIZE + SIDEBAR_WIDTH, BOARD_SIZE, "ZigFish");

    var game = if (options.start_pos) |fen|
        try GameManager.from_fen(allocator, fen)
    else
        try GameManager.init(allocator);

    try game.readPgnOpening(OPENING_PGN);

    var move_history = try std.ArrayList(MoveHist).initCapacity(allocator, 30);
    // add a dummy first move that is the start pos
    move_history.appendAssumeCapacity(.{ .board = game.board.clone(), .move = undefined });

    // const font = rl.Font.initEx("resources/FiraCode-Bold.otf", 32, null);

    const board_ui = BoardUI.init();

    const gui = Gui.init(
        @floatFromInt(BOARD_SIZE),
        // font,
    );

    // for (game.getAllValidMoves().items()) |m| {
    //     std.debug.print("{s}\n", .{m.toStrSimple()});
    // }

    return UiState{
        .game = game,
        .options = options,
        .move_history = move_history,
        .board_ui = board_ui,
        .gui = gui,
        .search_res = SearchRes{ .move = null, .done_search = Thread.ResetEvent{} },
        .game_status = game.gameStatus(),
        // .scale = UiScale.init(),
    };
}

pub fn deinit(self: *UiState) void {
    self.board_ui.deinit();
    self.game.deinit();
    self.move_history.deinit();
    self.gui.deint();
    rl.closeWindow();
}

fn clamp_to_screen(val: i32) usize {
    const clamped = std.math.clamp(val, 0, @as(i32, @intCast(BOARD_SIZE + SIDEBAR_WIDTH)));
    return @intCast(clamped);
}

fn mouse_to_pos(x: usize, y: usize) ?Position {
    const file = @divFloor(x, CELL_SIZE);
    const rank = 7 - @divFloor(y, CELL_SIZE);

    if (file > 7) {
        // clicking on gui so ignore
        return null;
    }

    return Position.fromRankFile(.{
        .rank = @intCast(rank),
        .file = @intCast(file),
    });
}

fn draw_move_marker(pos: Position, color: rl.Color) void {
    const rank_file = pos.toRankFile();
    const pos_x = CELL_SIZE * rank_file.file;
    const pos_y = CELL_SIZE * (7 - rank_file.rank);

    const rect = rl.Rectangle.init(
        @as(f32, @floatFromInt(pos_x)),
        @as(f32, @floatFromInt(pos_y)),
        @as(f32, @floatFromInt(CELL_SIZE)),
        @as(f32, @floatFromInt(CELL_SIZE)),
    );

    rl.drawRectangleLinesEx(rect, 10, color);
}

pub fn isPlayerTurn(self: *const UiState) bool {
    return if (self.options.ai_on)
        self.game.board.active_color == self.options.player_color
    else
        true;
}

pub fn update(self: *UiState) !void {
    if (self.game_status != .InProgress) {
        return;
    }

    // for (self.game.getOpeningMoves()) |opening| {
    //     std.debug.print("opening move: {s}\ttimes_played:{}\n", .{ opening.move.toStrSimple(), opening.times_played });
    // }

    const mouse_x: usize = clamp_to_screen(rl.getMouseX());
    const mouse_y: usize = clamp_to_screen(rl.getMouseY());

    const is_player_turn = self.isPlayerTurn();

    if (self.options.ai_on == false and self.search_thread != null) {
        self.search_thread.?.detach(); // kinda wasteful since the search will still run but wont affect us..
        self.search_thread = null;
    }

    // TODO: should the player be able to play for the ai in old position to mess around?
    // Need to do something to make it obvious they are in an old position and cant do anything if not
    if (self.search_thread == null and !is_player_turn and self.hist_index == null) {
        self.search_res.done_search.reset();
        self.search_res.move = null;
        const search_time = @as(usize, @intFromFloat(self.options.search_time * 1000));

        self.search_thread = try std.Thread.spawn(.{}, searchInBackground, .{
            &self.game,
            &self.search_res,
            .{ .time_limit_millis = search_time },
            &self.options,
        });
        return;
    }

    if (self.search_thread != null and self.search_res.done_search.isSet() and self.hist_index == null) {
        self.search_thread.?.join();
        self.search_thread = null;
        if (self.search_res.move) |m| {
            try self.game.makeMove(&m);
            try self.move_history.append(.{ .move = m, .board = self.game.board.clone() });
            self.game_status = self.game.gameStatus();
        }
        return;
    }

    if (!is_player_turn) {
        return;
    }

    // check if clicked a piece
    if (self.moving_piece == null and rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
        const maybe_pos = mouse_to_pos(mouse_x, mouse_y);
        const pos = if (maybe_pos) |p| p else return;
        const maybe_piece = self.game.getPos(pos);
        if (maybe_piece) |p| {
            if (p.color == self.game.board.active_color) {
                const moves = try self.game.getValidMovesAt(pos);
                self.moving_piece = MovingPiece{ .start = pos, .piece = p, .valid_moves = moves };
                self.game.setPos(pos, null);
            }
        }
        return;
    }

    // check if they can place the piece they picked up
    if (self.moving_piece != null and !rl.isMouseButtonDown(rl.MouseButton.mouse_button_left)) {
        const maybe_pos = mouse_to_pos(mouse_x, mouse_y);
        const pos = if (maybe_pos) |p| p else return;
        const mp = self.moving_piece.?;

        // reset the piece so board can do its own moving logic
        self.game.setPos(mp.start, mp.piece);

        for (mp.valid_moves.items()) |*move| {
            // TODO: select promotion if possible, should always be queen right now
            if (move.end.eql(pos)) {
                // std.log.debug("{s}", .{move.toSan()});
                try self.game.makeMove(move);

                // we are playing a move while looking at an old postion, we need to delete the history after this
                if (self.hist_index) |idx| {
                    self.move_history.shrinkAndFree(idx + 1);
                    self.hist_index = null;
                }

                try self.move_history.append(.{ .move = move.*, .board = self.game.board.clone() });
                self.game_status = self.game.gameStatus();

                // std.log.debug("make hash: {d}", .{game.board.zhash});

                // attacked_sqaures = game.allAttackedSqaures(game.board.active_color.get_enemy());
                break;
            }
        }

        self.moving_piece = null;
        return;
    }

    // // move undo
    // if (self.moving_piece == null and rl.isKeyPressed(rl.KeyboardKey.key_left)) {
    //     const maybe_move = self.move_history.popOrNull();
    //     if (maybe_move) |move| {
    //         self.game.unMakeMove(&move);
    //         // std.log.debug("unmake hash: {d}", .{game.board.zhash});
    //     }

    //     return;
    // }
}

pub fn draw(self: *UiState) !void {
    const hist = self.move_history.items;
    var last_move: ?Move = null;
    if (self.hist_index) |idx| {
        last_move = if (idx > 0) hist[idx].move else null;
    } else if (hist.len > 1) {
        last_move = self.move_history.getLast().move;
    }

    self.board_ui.draw_board(&self.game.board, last_move);

    // var attacked_iter = attacked_sqaures.bit_set.iterator(.{});
    // while (attacked_iter.next()) |p_idx| {
    //     board_ui.draw_move_marker(Position.fromIndex(p_idx), rl.Color.blue);
    // }

    try self.gui.draw(self);

    if (self.moving_piece) |p| {
        const mouse_x: usize = clamp_to_screen(rl.getMouseX());
        const mouse_y: usize = clamp_to_screen(rl.getMouseY());

        for (p.valid_moves.items()) |move| {
            draw_move_marker(move.end, rl.Color.red);
        }

        const offset = CELL_SIZE / 2; // make sprite under mouse cursor

        // TODO: this seems fine for the top / left sides, peice is half cut off on right / bottom
        self.board_ui.draw_piece(
            p.piece,
            @as(f32, @floatFromInt(sub_ignore_overflow(mouse_x, offset))),
            @as(f32, @floatFromInt(sub_ignore_overflow(mouse_y, offset))),
        );
    }
}

fn setBoard(self: *UiState) void {
    // TODO: either don't allow changing pos during search or cancel it here
    const hist = self.move_history.items;
    if (hist.len == 0) {
        return;
    }
    const idx = if (self.hist_index) |idx| idx else hist.len -| 1;
    std.debug.assert(idx < hist.len);
    self.game.board = self.move_history.items[idx].board.clone();
    self.game_status = self.game.gameStatus();
}

pub fn selectHist(self: *UiState, idx: usize) void {
    defer self.setBoard();
    const move_hist = self.move_history.items;
    std.debug.assert(idx < move_hist.len);
    self.hist_index = idx;
}

pub fn prevMove(self: *UiState) void {
    defer self.setBoard();
    if (self.hist_index) |idx| {
        self.hist_index = idx -| 1;
        return;
    }

    const num_moves = self.move_history.items.len;
    if (num_moves > 0) {
        self.hist_index = num_moves - 1;
        return;
    }
    self.hist_index = null;
}

pub fn nextMove(self: *UiState) void {
    defer self.setBoard();

    const num_moves = self.move_history.items.len;

    if (self.hist_index) |idx| {
        const new_idx = idx + 1;
        if (new_idx >= num_moves) {
            self.hist_index = null;
        } else {
            self.hist_index = new_idx;
        }
        return;
    }

    self.hist_index = null;
}

pub fn firstMove(self: *UiState) void {
    defer self.setBoard();

    const num_moves = self.move_history.items.len;

    if (num_moves > 0) {
        self.hist_index = 0;
        return;
    }

    self.hist_index = null;
}

pub fn lastMove(self: *UiState) void {
    defer self.setBoard();

    self.hist_index = null;
}
