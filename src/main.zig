const std = @import("std");
const rl = @import("raylib");

const sprite = @import("sprite.zig");
const Piece = @import("piece.zig").Piece;

const game_types = @import("game.zig");
const GameManager = game_types.GameManager;

const board_types = @import("board.zig");
const BoardBitSet = board_types.BoardBitSet;
const Position = board_types.Position;
const Move = board_types.Move;

const MoveList = game_types.MoveList;

const MovingPiece = struct {
    start: Position,
    piece: Piece,
    valid_moves: MoveList,
};

const cell_size: usize = 150;
const screen_size: usize = cell_size * 8;

fn clamp_to_screen(val: i32) usize {
    const clamped = std.math.clamp(val, 0, @as(i32, @intCast(screen_size)));
    return @intCast(clamped);
}

fn sub_ignore_overflow(a: anytype, b: anytype) @TypeOf(a, b) {
    return a -| b;
}

fn indexOf(comptime T: type, list: []const T, elem: T) ?usize {
    for (list, 0..) |x, index| {
        if (std.meta.eql(x, elem)) return index;
    }
    return null;
}

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------

    rl.initAudioDevice(); // Initialize audio device
    rl.initWindow(screen_size, screen_size, "ZigFish");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)
    const texture: rl.Texture = rl.Texture.init("resources/Chess_Pieces_Sprite.png"); // Texture loading
    defer rl.unloadTexture(texture); // Texture unloading

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // Used for move generation so we can reset after each move taken
    const move_allocator = arena.allocator();

    var move_history = try std.ArrayList(Move).initCapacity(gpa_allocator, 30);

    // var game = try GameManager.init(gpa_allocator);

    // std.debug.print("moves: {}", .{try game.getAllValidMoves(move_allocator)});

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
    var game = try GameManager.from_fen(gpa_allocator, "rnB2k1r/pp2bppp/2p5/8/2B5/8/PPP1NnPP/RNBqK2R w KQ - 0 9");

    var moving_piece: ?MovingPiece = null;

    // var attacked_sqaures = game.allAttackedSqaures(game.board.active_color.get_enemy());

    const sprite_manager = sprite.SpriteManager.init(texture, &game, cell_size);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        const mouse_x: usize = clamp_to_screen(rl.getMouseX());
        const mouse_y: usize = clamp_to_screen(rl.getMouseY());

        if (moving_piece == null and rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
            const pos = sprite_manager.mouse_to_pos(mouse_x, mouse_y);
            const maybe_piece = game.getPos(pos);
            if (maybe_piece) |p| {
                if (p.color == game.board.active_color) {
                    const moves = try game.get_valid_moves_at_pos(move_allocator, pos);
                    moving_piece = MovingPiece{ .start = pos, .piece = p, .valid_moves = moves };
                    game.setPos(pos, null);
                }
            }
        } else if (moving_piece != null and !rl.isMouseButtonDown(rl.MouseButton.mouse_button_left)) {
            const pos = sprite_manager.mouse_to_pos(mouse_x, mouse_y);

            const mp = moving_piece.?;

            // reset the piece so board can do its own moving logic
            game.setPos(mp.start, mp.piece);

            for (mp.valid_moves.items) |move| {
                // TODO: select promotion if possible, should always be queen right now
                if (move.end.eql(pos)) {
                    std.debug.print("{s}\n", .{move.toSan()});
                    try game.makeMove(move);
                    try move_history.append(move);
                    // attacked_sqaures = game.allAttackedSqaures(game.board.active_color.get_enemy());
                    break;
                }
            }

            moving_piece = null;
            // only reset once we are done using the possible moves
            defer _ = arena.reset(.retain_capacity);
        } else if (moving_piece == null and rl.isKeyPressed(rl.KeyboardKey.key_left)) {
            // undo move
            const maybe_move = move_history.popOrNull();
            if (maybe_move) |move| {
                game.unMakeMove(move);
            }
        }

        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.ray_white);
        sprite_manager.draw_board();

        // var attacked_iter = attacked_sqaures.bit_set.iterator(.{});
        // while (attacked_iter.next()) |p_idx| {
        //     sprite_manager.draw_move_marker(Position.fromIndex(p_idx), rl.Color.blue);
        // }

        if (moving_piece) |p| {
            for (p.valid_moves.items) |move| {
                sprite_manager.draw_move_marker(move.end, rl.Color.red);
            }

            const offset = cell_size / 2; // make sprite under mouse cursor

            // TODO: this seems fine for the top / left sides, peice is half cut off on right / bottom
            sprite_manager.draw_piece(
                p.piece,
                @as(f32, @floatFromInt(sub_ignore_overflow(mouse_x, offset))),
                @as(f32, @floatFromInt(sub_ignore_overflow(mouse_y, offset))),
            );
        }

        //----------------------------------------------------------------------------------
    }
}
