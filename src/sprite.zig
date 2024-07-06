const rl = @import("raylib");
const Piece = @import("piece.zig").Piece;
const Board = @import("board.zig").Board;

const num_piece_types = 6;
const num_colors = 2;

pub const SpriteManager = struct {
    texture: rl.Texture,
    sprite_w: f32,
    sprite_h: f32,

    pub fn init(texture: rl.Texture) SpriteManager {
        return .{
            .texture = texture,
            .sprite_w = @as(f32, @floatFromInt(@divFloor(texture.width, num_piece_types))),
            .sprite_h = @as(f32, @floatFromInt(@divFloor(texture.height, num_colors))),
        };
    }

    pub fn draw_board(self: SpriteManager, board: Board, cell_size: f32) void {
        const scale = cell_size / self.sprite_w;

        for (board.cells, 0..) |rank_cells, file| {
            for (rank_cells, 0..) |cell, rank| {
                const pos_x = cell_size * @as(f32, @floatFromInt(rank));
                const pos_y = cell_size * @as(f32, @floatFromInt(file));

                switch (cell) {
                    .piece => |p| self.draw_piece_scaled(
                        p,
                        pos_x,
                        pos_y,
                        scale,
                    ),
                    .empty => {},
                }
            }
        }
    }

    pub fn draw_piece_scaled(
        self: SpriteManager,
        p: Piece,
        pos_x: f32,
        pos_y: f32,
        scale: f32,
    ) void {
        const sprite_id_x = @intFromEnum(p.kind);
        const sprite_id_y = @intFromEnum(p.color);
        self.draw_sprite_scaled(sprite_id_x, sprite_id_y, pos_x, pos_y, scale);
    }

    fn draw_sprite_scaled(
        self: SpriteManager,
        sprite_id_x: u8,
        sprite_id_y: u8,
        pos_x: f32,
        pos_y: f32,
        scale: f32,
    ) void {
        // const sprite_id_x: u8 = @rem(sprite_id, num_piece_types);
        // const sprite_id_y: u8 = if (sprite_id > num_piece_types) 1 else 0;

        const frameRec = rl.Rectangle.init(
            @as(f32, @floatFromInt(sprite_id_x)) * self.sprite_h,
            @as(f32, @floatFromInt(sprite_id_y)) * self.sprite_w,
            self.sprite_w,
            self.sprite_h,
        );

        const position = rl.Rectangle.init(
            pos_x,
            pos_y,
            self.sprite_w * scale,
            self.sprite_h * scale,
        );

        self.texture.drawPro(frameRec, position, rl.Vector2.zero(), 0, rl.Color.white);
    }
};
