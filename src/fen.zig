const std = @import("std");
const testing = std.testing;

const piece_types = @import("piece.zig");
const Piece = piece_types.Piece;
const Color = piece_types.Color;
const Kind = piece_types.Kind;

const board_types = @import("board.zig");
const Board = board_types.Board;
const Cell = board_types.Cell;
const Position = board_types.Position;

const piece_lookup = std.StaticStringMap(Piece).initComptime(.{
    .{ "k", Piece{ .kind = Kind.King, .color = Color.White } },
    .{ "K", Piece{ .kind = Kind.King, .color = Color.Black } },
    .{ "q", Piece{ .kind = Kind.Queen, .color = Color.White } },
    .{ "Q", Piece{ .kind = Kind.Queen, .color = Color.Black } },
    .{ "b", Piece{ .kind = Kind.Bishop, .color = Color.White } },
    .{ "B", Piece{ .kind = Kind.Bishop, .color = Color.Black } },
    .{ "n", Piece{ .kind = Kind.Knight, .color = Color.White } },
    .{ "N", Piece{ .kind = Kind.Knight, .color = Color.Black } },
    .{ "r", Piece{ .kind = Kind.Rook, .color = Color.White } },
    .{ "R", Piece{ .kind = Kind.Rook, .color = Color.Black } },
    .{ "p", Piece{ .kind = Kind.Pawn, .color = Color.White } },
    .{ "P", Piece{ .kind = Kind.Pawn, .color = Color.Black } },
});

pub fn parse(str: []const u8) Board {
    var splits = std.mem.tokenizeScalar(u8, str, ' ');

    const pieces_str = splits.next().?;
    const active_color = splits.next() orelse "w";
    const castling_str = splits.next() orelse "-";
    const en_passant_str = splits.next() orelse "-";
    const half_move_str = splits.next() orelse "0";
    const full_move_str = splits.next() orelse "0";

    var rank_strs = std.mem.tokenizeScalar(u8, pieces_str, '/');

    var cells: [64]Cell = undefined;

    // fen starts from the top, board arr has bottom as 0
    var curr_pos = Position{ .file = 0, .rank = 7 };

    while (rank_strs.next()) |rank_str| {
        curr_pos.file = 0;
        for (rank_str) |char| {
            const key = [_]u8{char};
            if (piece_lookup.has(&key)) {
                const piece = piece_lookup.get(&key).?;
                cells[curr_pos.to_index()] = Cell{ .piece = piece };
                curr_pos.file += 1;
            } else {
                const num_empty = std.fmt.parseInt(usize, &key, 10) catch |err| {
                    std.debug.panic("erroring parsing {s} as usize {}", .{ key, err });
                };
                for (0..(num_empty)) |_| {
                    cells[curr_pos.to_index()] = Cell.empty;
                    curr_pos.file += 1;
                }
            }
        }

        if (curr_pos.rank > 0) curr_pos.rank -= 1;
    }

    // TODO: use these....
    _ = active_color;
    _ = castling_str;
    _ = en_passant_str;
    _ = half_move_str;
    _ = full_move_str;

    return Board{ .cells = cells };
}
