const std = @import("std");
const rl = @import("raylib");

const sprite = @import("sprite.zig");
const piece = @import("piece.zig");

const MAX_FRAME_SPEED = 15;
const MIN_FRAME_SPEED = 1;

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 1920;
    const screenHeight = 1080;

    rl.initAudioDevice(); // Initialize audio device
    rl.initWindow(screenWidth, screenHeight, "ZigFish");
    defer rl.closeWindow(); // Close window and OpenGL context

    // NOTE: Textures MUST be loaded after Window initialization (OpenGL context is required)
    const texture: rl.Texture = rl.Texture.init("resources/Chess_Pieces_Sprite.png"); // Texture loading
    defer rl.unloadTexture(texture); // Texture unloading

    const sprite_manager = sprite.init(texture);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------

        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.ray_white);

        // const p = piece.Piece{
        //     .color = piece.Color.White,
        //     .kind = piece.Kind.Bishop,
        // };

        const x_gap = 300;
        const y_gap = 300;

        for (0..2) |color| {
            for (0..6) |kind| {
                const p = piece.Piece{
                    .color = @enumFromInt(color),
                    .kind = @enumFromInt(kind),
                };
                const x = 100 + (x_gap * kind);
                const y = 100 + (y_gap * color);

                sprite_manager.draw_piece_scaled(
                    p,
                    @as(f32, @floatFromInt(x)),
                    @as(f32, @floatFromInt(y)),
                    0.5,
                );
            }
        }

        //----------------------------------------------------------------------------------
    }
}
