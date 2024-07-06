const std = @import("std");
const rl = @import("raylib");

const sprite = @import("sprite.zig");
const Piece = @import("piece.zig").Piece;
const board_types = @import("board.zig");
const Board = board_types.Board;
const Position = board_types.Position;
const Cell = board_types.Cell;

const MovingPiece = struct { start: Position, piece: Piece };

const cell_size: usize = 150;
const screen_size: usize = cell_size * 8;

fn clamp_to_screen(val: i32) usize {
    const clamped = std.math.clamp(val, 0, @as(i32, @intCast(screen_size)));
    return @intCast(clamped);
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

    var board = Board.init();

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
                    moving_piece = MovingPiece{ .start = pos, .piece = p };
                    board.set_cell(pos, .empty);
                },
                .empty => {},
            }
        } else if (!rl.isMouseButtonDown(rl.MouseButton.mouse_button_left)) {
            moving_piece = null;
        }

        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.ray_white);
        sprite_manager.draw_board();

        if (moving_piece) |p| {
            const offset = cell_size / 2; // make sprite under mouse cursor

            sprite_manager.draw_piece(
                p.piece,
                @as(f32, @floatFromInt(mouse_x - offset)),
                @as(f32, @floatFromInt(mouse_y - offset)),
            );
        }

        //----------------------------------------------------------------------------------
    }
}
