const std = @import("std");
const rl = @import("raylib");
const ZigFish = @import("zigfish");
const Position = ZigFish.Position;
const Move = ZigFish.Move;

const Piece = ZigFish.Piece;
const GameManager = ZigFish.GameManager;

const num_piece_types = 6;
const num_colors = 2;

const SpriteManager = @This();

texture: rl.Texture,
sprite_w: f32,
sprite_h: f32,
cell_size: u32,
scale: f32,
dark_sqaure_color: rl.Color,
light_square_color: rl.Color,

pub fn init(texture: rl.Texture, cell_size: u32) SpriteManager {
    const sprite_w = @as(f32, @floatFromInt(@divFloor(texture.width, num_piece_types)));
    const sprite_h = @as(f32, @floatFromInt(@divFloor(texture.height, num_colors)));
    const scale = @as(f32, @floatFromInt(cell_size)) / sprite_w;

    return .{
        .texture = texture,
        .sprite_w = sprite_w,
        .sprite_h = sprite_h,
        .scale = scale,
        .cell_size = cell_size,
        .dark_sqaure_color = rl.Color.init(140, 77, 42, 255),
        .light_square_color = rl.Color.init(224, 186, 151, 255),
    };
}

pub fn deinit(self: *SpriteManager) void {
    rl.unloadTexture(self.texture);
}

pub fn clamp_to_screen(self: *SpriteManager, val: i32) usize {
    const screen_size: usize = self.cell_size * 8;

    const clamped = std.math.clamp(val, 0, @as(i32, @intCast(screen_size)));
    return @intCast(clamped);
}

pub fn draw_board(self: SpriteManager, board: *const ZigFish.Board, last_move: ?Move) void {
    for (0..8) |rank| {
        for (0..8) |file| {
            const flipped_rank = 7 - rank;
            const pos_x = self.cell_size * file;
            const pos_y = self.cell_size * (rank);

            const pos = Position.fromRankFile(.{ .rank = @intCast(flipped_rank), .file = @intCast(file) });

            const is_white_cell = @mod(rank + file, 2) == 0;

            var cell_color = if (is_white_cell) self.light_square_color else self.dark_sqaure_color;
            const opposite_color = if (is_white_cell) self.dark_sqaure_color else self.light_square_color;

            if (last_move) |move| {
                if (move.start.eql(pos) or move.end.eql(pos)) {
                    cell_color = rl.Color.dark_gray;
                }
            }

            rl.drawRectangle(
                @intCast(pos_x),
                @intCast(pos_y),
                @intCast(self.cell_size),
                @intCast(self.cell_size),
                cell_color,
            );

            if (flipped_rank == 0) {
                const text_offset = (8 * @divFloor(self.cell_size, 9));
                const char: u8 = @as(u8, @intCast(file)) + 'a';
                const str = [1:0]u8{char};
                rl.drawText(&str, @intCast(pos_x + text_offset), @intCast(pos_y + text_offset), 20, opposite_color);
            }

            if (file == 0) {
                const text_offset = @divFloor(self.cell_size, 9);
                const char: u8 = @as(u8, @intCast(flipped_rank)) + '1';
                const str = [1:0]u8{char};
                rl.drawText(&str, @intCast(pos_x + text_offset), @intCast(pos_y + text_offset), 20, opposite_color);
            }

            if (board.getPos(pos)) |p| {
                self.draw_piece(
                    p,
                    @as(f32, @floatFromInt(pos_x)),
                    @as(f32, @floatFromInt(pos_y)),
                );
            }
        }
    }
}

pub fn mouse_to_pos(self: SpriteManager, x: usize, y: usize) Position {
    const file = @divFloor(x, self.cell_size);
    const rank = 7 - @divFloor(y, self.cell_size);

    return Position.fromRankFile(.{
        .rank = @intCast(rank),
        .file = @intCast(file),
    });
}

pub fn draw_piece(
    self: SpriteManager,
    p: Piece,
    pos_x: f32,
    pos_y: f32,
) void {
    const sprite_id_x = @intFromEnum(p.kind);
    const sprite_id_y = @intFromEnum(p.color);
    self.draw_sprite(sprite_id_x, sprite_id_y, pos_x, pos_y);
}

pub fn draw_move_marker(self: SpriteManager, pos: Position, color: rl.Color) void {
    const rank_file = pos.toRankFile();
    const pos_x = self.cell_size * rank_file.file;
    const pos_y = self.cell_size * (7 - rank_file.rank);

    const rect = rl.Rectangle.init(
        @as(f32, @floatFromInt(pos_x)),
        @as(f32, @floatFromInt(pos_y)),
        @as(f32, @floatFromInt(self.cell_size)),
        @as(f32, @floatFromInt(self.cell_size)),
    );

    rl.drawRectangleLinesEx(rect, 10, color);
}

fn draw_sprite(
    self: SpriteManager,
    sprite_id_x: u8,
    sprite_id_y: u8,
    pos_x: f32,
    pos_y: f32,
) void {
    const frameRec = rl.Rectangle.init(
        @as(f32, @floatFromInt(sprite_id_x)) * self.sprite_h,
        @as(f32, @floatFromInt(sprite_id_y)) * self.sprite_w,
        self.sprite_w,
        self.sprite_h,
    );

    const position = rl.Rectangle.init(
        pos_x,
        pos_y,
        self.sprite_w * self.scale,
        self.sprite_h * self.scale,
    );

    self.texture.drawPro(frameRec, position, rl.Vector2.zero(), 0, rl.Color.white);
}
