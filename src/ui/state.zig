const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib");
const ZigFish = @import("zigfish");

const SpriteManager = @import("./sprite.zig");

const Thread = std.Thread;

const Position = ZigFish.Position;
const Piece = ZigFish.Piece;
const MoveList = ZigFish.MoveList;
const Move = ZigFish.Move;
const GameManager = ZigFish.GameManager;

const SearchRes = struct { move: ?Move, done_search: Thread.ResetEvent };

const MovingPiece = struct {
    start: Position,
    piece: Piece,
    valid_moves: MoveList,
};

const Allocator = std.mem.Allocator;

pub const GameOptions = struct {
    /// milli seconds
    search_time: usize = 5000,
    player_color: Piece.Color = Piece.Color.White,
    ai_on: bool = true,
    start_pos: ?[]const u8 = null,
};

const MAX_DEPTH = 100;

fn searchInBackground(game: *GameManager, search_res: *SearchRes, search_opts: ZigFish.Search.SearchOpts) !void {
    const move = try game.findBestMove(search_opts);

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

// allocator: Allocator,
// area: std.heap.ArenaAllocator,

game: GameManager,
options: GameOptions,
move_history: std.ArrayList(Move),
sprite_manager: SpriteManager,
search_res: SearchRes,
search_thread: ?Thread = null,
moving_piece: ?MovingPiece = null,

pub fn init(allocator: Allocator, cell_size: u32, options: GameOptions) !UiState {
    const game = if (options.start_pos) |fen|
        try GameManager.from_fen(allocator, fen)
    else
        try GameManager.init(allocator);

    const move_history = try std.ArrayList(Move).initCapacity(allocator, 30);

    const texture: rl.Texture = rl.Texture.init("resources/Chess_Pieces_Sprite.png"); // Texture loading

    const sprite_manager = SpriteManager.init(texture, cell_size);

    return UiState{
        .game = game,
        .options = options,
        .move_history = move_history,
        .sprite_manager = sprite_manager,
        .search_res = SearchRes{ .move = null, .done_search = Thread.ResetEvent{} },
    };
}

pub fn deinit(self: *UiState) void {
    self.sprite_manager.deinit();
    self.game.deinit();
    self.move_history.deinit();
}

// pub fn getMousePos(self: *UiState) ClampedMousePos {
//     const mouse_x: usize = self.sprite_manager.clamp_to_screen(rl.getMouseX());
//     const mouse_y: usize = self.sprite_manager.clamp_to_screen(rl.getMouseY());

//     return .{ .x = mouse_x, .y = mouse_y };
// }

pub fn update(self: *UiState) !void {
    const mouse_x: usize = self.sprite_manager.clamp_to_screen(rl.getMouseX());
    const mouse_y: usize = self.sprite_manager.clamp_to_screen(rl.getMouseY());

    const is_player_turn = if (self.options.ai_on)
        self.game.board.active_color == self.options.player_color
    else
        true;

    if (self.search_thread == null and !is_player_turn) {
        self.search_res.done_search.reset();
        self.search_res.move = null;
        var cloned_game = try self.game.clone();
        self.search_thread = try std.Thread.spawn(.{}, searchInBackground, .{
            &cloned_game,
            &self.search_res,
            .{ .time_limit_millis = self.options.search_time },
        });
        return;
    }

    if (self.search_thread != null and self.search_res.done_search.isSet()) {
        self.search_thread.?.join();
        self.search_thread = null;
        if (self.search_res.move) |m| {
            try self.game.makeMove(&m);
            try self.move_history.append(m);
        }
        return;
    }

    if (!is_player_turn) {
        return;
    }

    // check if clicked a piece
    if (self.moving_piece == null and rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
        const pos = self.sprite_manager.mouse_to_pos(mouse_x, mouse_y);
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
        const pos = self.sprite_manager.mouse_to_pos(mouse_x, mouse_y);

        const mp = self.moving_piece.?;

        // reset the piece so board can do its own moving logic
        self.game.setPos(mp.start, mp.piece);

        for (mp.valid_moves.items()) |*move| {
            // TODO: select promotion if possible, should always be queen right now
            if (move.end.eql(pos)) {
                // std.log.debug("{s}", .{move.toSan()});
                try self.game.makeMove(move);
                try self.move_history.append(move.*);
                // std.log.debug("make hash: {d}", .{game.board.zhash});

                // attacked_sqaures = game.allAttackedSqaures(game.board.active_color.get_enemy());
                break;
            }
        }

        self.moving_piece = null;
        return;
    }

    // move undo
    if (self.moving_piece == null and rl.isKeyPressed(rl.KeyboardKey.key_left)) {
        const maybe_move = self.move_history.popOrNull();
        if (maybe_move) |move| {
            self.game.unMakeMove(&move);
            // std.log.debug("unmake hash: {d}", .{game.board.zhash});
        }

        return;
    }
}

pub fn draw(self: *UiState) void {
    self.sprite_manager.draw_board(&self.game.board, self.move_history.getLastOrNull());

    // var attacked_iter = attacked_sqaures.bit_set.iterator(.{});
    // while (attacked_iter.next()) |p_idx| {
    //     sprite_manager.draw_move_marker(Position.fromIndex(p_idx), rl.Color.blue);
    // }

    if (self.moving_piece) |p| {
        const mouse_x: usize = self.sprite_manager.clamp_to_screen(rl.getMouseX());
        const mouse_y: usize = self.sprite_manager.clamp_to_screen(rl.getMouseY());

        for (p.valid_moves.items()) |move| {
            self.sprite_manager.draw_move_marker(move.end, rl.Color.red);
        }

        const offset = self.sprite_manager.cell_size / 2; // make sprite under mouse cursor

        // TODO: this seems fine for the top / left sides, peice is half cut off on right / bottom
        self.sprite_manager.draw_piece(
            p.piece,
            @as(f32, @floatFromInt(sub_ignore_overflow(mouse_x, offset))),
            @as(f32, @floatFromInt(sub_ignore_overflow(mouse_y, offset))),
        );
    }
}
