// Port of https://github.com/raysan5/raylib/blob/master/examples/textures/textures_sprite_anim.c to zig

const std = @import("std");
const rl = @import("raylib");

const sprite = @import("sprite.zig");

const MAX_FRAME_SPEED = 15;
const MIN_FRAME_SPEED = 1;

// fn draw_piece_scaled(tx: rl.Texture, scale: f32) void {
//     const position = rl.Rectangle.init(
//         350.0,
//         280.0,
//         @as(f32, @floatFromInt(@divFloor(chess_pieces.width, 6))) * scale,
//         @as(f32, @floatFromInt(chess_pieces.height)) * scale,
//     );
//     chess_pieces.drawPro(frameRec, position, rl.Vector2.zero(), 0, rl.Color.white);
// }

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

    const pieces = sprite.init(texture);

    // const position = rl.Vector2.init(350.0, 280.0);
    // var frameRec = rl.Rectangle.init(
    //     0,
    //     0,
    //     @as(f32, @floatFromInt(@divFloor(chess_pieces.width, 6))),
    //     @as(f32, @floatFromInt(chess_pieces.height)),
    // );
    // var currentFrame: u8 = 0;

    // var framesCounter: u8 = 0;
    // var framesSpeed: u8 = 8; // Number of spritesheet frames shown by second

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // framesCounter += 1;

        // if (framesCounter >= (60 / framesSpeed)) {
        //     framesCounter = 0;
        //     currentFrame += 1;

        //     if (currentFrame > 5) currentFrame = 0;

        //     frameRec.x = @as(f32, @floatFromInt(currentFrame)) * @as(f32, @floatFromInt(@divFloor(chess_pieces.width, 6)));
        // }

        // // Control frames speed
        // if (rl.isKeyPressed(rl.KeyboardKey.key_right)) {
        //     framesSpeed += 1;
        // } else if (rl.isKeyPressed(rl.KeyboardKey.key_left)) {
        //     framesSpeed -= 1;
        // }

        // if (framesSpeed > MAX_FRAME_SPEED) {
        //     framesSpeed = MAX_FRAME_SPEED;
        // } else if (framesSpeed < MIN_FRAME_SPEED) {
        //     framesSpeed = MIN_FRAME_SPEED;
        // }

        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.ray_white);

        pieces.draw_piece_scaled(0.5);

        //----------------------------------------------------------------------------------
    }
}
