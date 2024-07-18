const std = @import("std");
const rl = @import("raylib");
const Piece = @import("../piece.zig");
const game_types = @import("../game.zig");
const GameManager = game_types.GameManager;
const board_types = @import("../board.zig");
const Position = board_types.Position;
const Move = board_types.Move;

const num_piece_types = 6;
const num_colors = 2;

const SpriteManager = @This();

texture: rl.Texture,
game_manager: *GameManager,
sprite_w: f32,
sprite_h: f32,
cell_size: u32,
scale: f32,

pub fn init(texture: rl.Texture, game_manager: *GameManager, cell_size: u32) SpriteManager {
    const sprite_w = @as(f32, @floatFromInt(@divFloor(texture.width, num_piece_types)));
    const sprite_h = @as(f32, @floatFromInt(@divFloor(texture.height, num_colors)));
    const scale = @as(f32, @floatFromInt(cell_size)) / sprite_w;

    return .{
        .texture = texture,
        .game_manager = game_manager,
        .sprite_w = sprite_w,
        .sprite_h = sprite_h,
        .scale = scale,
        .cell_size = cell_size,
    };
}

pub fn draw_board(self: SpriteManager, last_move: ?Move) void {
    for (0..8) |rank| {
        for (0..8) |file| {
            const flipped_rank = 7 - rank;
            const pos_x = self.cell_size * file;
            const pos_y = self.cell_size * (rank);

            const pos = Position.fromRankFile(.{ .rank = @intCast(flipped_rank), .file = @intCast(file) });

            const is_white_cell = @mod(rank + file, 2) == 0;

            var cell_color = if (is_white_cell) rl.Color.light_gray else rl.Color.dark_gray;

            if (last_move) |move| {
                if (move.start.eql(pos) or move.end.eql(pos)) {
                    cell_color = rl.Color.beige;
                }
            }

            rl.drawRectangle(
                @intCast(pos_x),
                @intCast(pos_y),
                @intCast(self.cell_size),
                @intCast(self.cell_size),
                cell_color,
            );

            if (self.game_manager.getPos(pos)) |p| {
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
