const rl = @import("raylib");

const SpriteManager = struct {
    texture: rl.Texture,
    stride_w: f32,
    stride_h: f32,

    pub fn draw_piece_scaled(self: SpriteManager, scale: f32) void {
        const frameRec = rl.Rectangle.init(
            0,
            0,
            self.stride_w,
            self.stride_h,
        );

        const position = rl.Rectangle.init(
            350.0,
            280.0,
            self.stride_w * scale,
            self.stride_h * scale,
        );

        self.texture.drawPro(frameRec, position, rl.Vector2.zero(), 0, rl.Color.white);
    }
};

pub fn init(texture: rl.Texture) SpriteManager {
    return .{
        .texture = texture,
        .stride_w = @as(f32, @floatFromInt(@divFloor(texture.width, 6))),
        .stride_h = @as(f32, @floatFromInt(@divFloor(texture.height, 2))),
    };
}
