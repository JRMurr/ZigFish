const std = @import("std");
const rl = @import("raylib");

const sprite = @import("sprite.zig");
const Piece = @import("piece.zig").Piece;

const game_types = @import("game.zig");
const GameManager = game_types.GameManager;

const board_types = @import("board.zig");
const Position = board_types.Position;
const Cell = board_types.Cell;
const Move = board_types.Move;

const MovingPiece = struct {
    start: Position,
    piece: Piece,
    valid_moves: std.ArrayList(Position),
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
    const allocator = gpa.allocator();

    var arena_allocator = std.heap.ArenaAllocator.init(allocator); // TODO: should this take in not the gpa for perf?
    defer arena_allocator.deinit();

    const arena = arena_allocator.allocator();

    var board = GameManager.init(allocator);
    // var board = Board.from_fen(arena.allocator(), "8/5k2/3p4/1p1Pp2p/pP2Pp1P/P4P1K/8/8 b - - 99 50");

    // var board = Board.from_fen(arena.allocator(), "8/8/8/8/4n3/8/8/8 b - - 99 50");

    var moving_piece: ?MovingPiece = null;

    const sprite_manager = sprite.SpriteManager.init(texture, &board, cell_size);

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
            const cell = board.get_cell(pos);

            switch (cell) {
                .piece => |p| {
                    if (p.color == board.active_color) {
                        const moves = try board.get_valid_moves(arena, pos);
                        moving_piece = MovingPiece{ .start = pos, .piece = p, .valid_moves = moves };
                        board.set_cell(pos, .empty);
                    }
                },
                .empty => {},
            }
        } else if (moving_piece != null and !rl.isMouseButtonDown(rl.MouseButton.mouse_button_left)) {
            const pos = sprite_manager.mouse_to_pos(mouse_x, mouse_y);

            const mp = moving_piece.?;

            // reset the piece so board can do its own moving logic
            board.set_cell(mp.start, .{ .piece = mp.piece });

            const move_idx = indexOf(Position, mp.valid_moves.items, pos);

            if (move_idx != null) {
                board.make_move(Move{ .start = mp.start, .end = pos });
            }

            moving_piece = null;
            // only reset once we are done using the possible moves
            defer _ = arena_allocator.reset(.retain_capacity);
        }

        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.ray_white);
        sprite_manager.draw_board();

        if (moving_piece) |p| {
            for (p.valid_moves.items) |pos| {
                sprite_manager.draw_move_marker(pos);
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
