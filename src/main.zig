const std = @import("std");
const rl = @import("raylib");

const sprite = @import("sprite.zig");
const Piece = @import("piece.zig").Piece;

const game_types = @import("game.zig");
const GameManager = game_types.GameManager;

const board_types = @import("board.zig");
const BoardBitSet = board_types.BoardBitSet;
const Position = board_types.Position;
const Cell = board_types.Cell;
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // var board = GameManager.init();
    // var board = Board.from_fen(arena.allocator(), "8/5k2/3p4/1p1Pp2p/pP2Pp1P/P4P1K/8/8 b - - 99 50");

    // pin should be able to capture
    var board = GameManager.from_fen("8/2rk4/8/2p5/b3q3/1NRP4/2K5/8 w - - 0 1");

    // var board = Board.from_fen(arena.allocator(), "8/8/8/8/4n3/8/8/8 b - - 99 50");

    var moving_piece: ?MovingPiece = null;

    // var attacked_sqaures = board.get_all_attacked_sqaures(board.active_color.get_enemy());

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
                        const moves = try board.get_valid_moves(allocator, pos);
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

            for (mp.valid_moves.items) |move| {
                if (move.end.eql(pos)) {
                    board.make_move(move);
                }
            }

            // if (mp.valid_moves.isSet(pos.toIndex())) {
            //     board.make_move(Move{ .start = mp.start, .end = pos, .kind = mp.piece.kind });
            //     // attacked_sqaures = board.get_all_attacked_sqaures(board.active_color.get_enemy());
            // }

            // const move_idx = indexOf(Position, mp.valid_moves.items, pos);

            // if (move_idx != null) {
            //     board.make_move(Move{ .start = mp.start, .end = pos });
            // }

            moving_piece = null;
            // only reset once we are done using the possible moves
            defer _ = arena.reset(.retain_capacity);
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
