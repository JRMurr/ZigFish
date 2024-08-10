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

const GameOptions = struct {
    /// milli seconds
    search_time: usize = 5000,
    player_color: Piece.Color = Piece.Color.White,
    ai_on: bool = true,
};

const UiState = struct {
    game: GameManager,
    move_history: std.ArrayList(Move),
    sprite_manager: SpriteManager,
    serch_res: SearchRes,
    search_thread: ?Thread = null,
};
