const std = @import("std");
const rl = @import("raylib");
const ZigFish = @import("zigfish");
const Position = ZigFish.Position;
const Move = ZigFish.Move;

const Piece = ZigFish.Piece;
const GameManager = ZigFish.GameManager;

const num_piece_types = 6;
const num_colors = 2;

const BoardUI = @This();

const UiState = @import("state.zig");

const CELL_SIZE = UiState.CELL_SIZE;

texture: rl.Texture,
sprite_w: f32,
sprite_h: f32,
sprite_scale: f32,
dark_sqaure_color: rl.Color,
light_square_color: rl.Color,

pub fn init() BoardUI {
    const texture: rl.Texture = rl.Texture.init("resources/Chess_Pieces_Sprite.png"); // Texture loading

    const sprite_w = @as(f32, @floatFromInt(@divFloor(texture.width, num_piece_types)));
    const sprite_h = @as(f32, @floatFromInt(@divFloor(texture.height, num_colors)));
    const sprite_scale = @as(f32, @floatFromInt(CELL_SIZE)) / sprite_w;

    return .{
        .texture = texture,
        .sprite_w = sprite_w,
        .sprite_h = sprite_h,
        .sprite_scale = sprite_scale,
        .dark_sqaure_color = rl.Color.init(140, 77, 42, 255),
        .light_square_color = rl.Color.init(224, 186, 151, 255),
    };
}

pub fn deinit(self: *BoardUI) void {
    rl.unloadTexture(self.texture);
}

pub fn draw_board(self: BoardUI, board: *const ZigFish.Board, last_move: ?Move) void {
    for (0..8) |rank| {
        for (0..8) |file| {
            const flipped_rank = 7 - rank;
            const pos_x = CELL_SIZE * file;
            const pos_y = CELL_SIZE * (rank);

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
                @intCast(CELL_SIZE),
                @intCast(CELL_SIZE),
                cell_color,
            );

            if (flipped_rank == 0) {
                const text_offset = (8 * @divFloor(CELL_SIZE, 9));
                const char: u8 = @as(u8, @intCast(file)) + 'a';
                const str = [1:0]u8{char};
                rl.drawText(&str, @intCast(pos_x + text_offset), @intCast(pos_y + text_offset), 20, opposite_color);
            }

            if (file == 0) {
                const text_offset = @divFloor(CELL_SIZE, 9);
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

pub fn draw_piece(
    self: BoardUI,
    p: Piece,
    pos_x: f32,
    pos_y: f32,
) void {
    const sprite_id_x = @intFromEnum(p.kind);
    const sprite_id_y = @intFromEnum(p.color);
    self.draw_sprite(sprite_id_x, sprite_id_y, pos_x, pos_y);
}

fn draw_sprite(
    self: BoardUI,
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
        self.sprite_w * self.sprite_scale,
        self.sprite_h * self.sprite_scale,
    );

    self.texture.drawPro(frameRec, position, rl.Vector2.zero(), 0, rl.Color.white);
}
