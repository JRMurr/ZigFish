const std = @import("std");
const testing = std.testing;

const piece_types = @import("piece.zig");
const Piece = piece_types.Piece;
const Color = piece_types.Color;
const Kind = piece_types.Kind;

const board_types = @import("board.zig");
const Board = board_types.Board;
const Position = board_types.Position;
const PositionRankFile = board_types.PositionRankFile;

const piece_lookup = std.StaticStringMap(Piece).initComptime(.{
    .{ "K", Piece{ .kind = Kind.King, .color = Color.White } },
    .{ "k", Piece{ .kind = Kind.King, .color = Color.Black } },
    .{ "Q", Piece{ .kind = Kind.Queen, .color = Color.White } },
    .{ "q", Piece{ .kind = Kind.Queen, .color = Color.Black } },
    .{ "B", Piece{ .kind = Kind.Bishop, .color = Color.White } },
    .{ "b", Piece{ .kind = Kind.Bishop, .color = Color.Black } },
    .{ "N", Piece{ .kind = Kind.Knight, .color = Color.White } },
    .{ "n", Piece{ .kind = Kind.Knight, .color = Color.Black } },
    .{ "R", Piece{ .kind = Kind.Rook, .color = Color.White } },
    .{ "r", Piece{ .kind = Kind.Rook, .color = Color.Black } },
    .{ "P", Piece{ .kind = Kind.Pawn, .color = Color.White } },
    .{ "p", Piece{ .kind = Kind.Pawn, .color = Color.Black } },
});

pub const BoardState = struct {
    board: board_types.Board,
    active_color: Color,
};

fn parseInt(comptime T: type, buf: []const u8) T {
    return std.fmt.parseInt(T, buf, 10) catch |err| {
        std.debug.panic("erroring parsing {s} as {s}. Err: {}", .{ buf, @typeName(T), err });
    };
}

pub fn parse(str: []const u8) BoardState {
    var splits = std.mem.tokenizeScalar(u8, str, ' ');

    const pieces_str = splits.next().?;
    const active_color_str = splits.next() orelse "w";
    const castling_str = splits.next() orelse "KQkq";
    const en_passant_str = splits.next() orelse "-";
    const half_move_str = splits.next() orelse "0";
    const full_move_str = splits.next() orelse "0";

    var rank_strs = std.mem.tokenizeScalar(u8, pieces_str, '/');

    var board = Board.init();

    // fen starts from the top, board arr has bottom as 0
    var curr_pos = PositionRankFile{ .file = 0, .rank = 7 };

    while (rank_strs.next()) |rank_str| {
        curr_pos.file = 0;
        for (rank_str) |char| {
            const key = [_]u8{char};
            if (piece_lookup.has(&key)) {
                const piece = piece_lookup.get(&key).?;
                board.set_pos(curr_pos.toPosition(), piece);
                curr_pos.file += 1;
            } else {
                const num_empty = parseInt(u8, &key);
                curr_pos.file +%= num_empty;
            }
        }

        if (curr_pos.rank > 0) curr_pos.rank -= 1;
    }

    const active_color = if (std.mem.eql(u8, active_color_str, "w")) Color.White else Color.Black;

    if (!std.mem.eql(u8, en_passant_str, "-")) {
        board.meta.en_passant_pos = Position.fromStr(en_passant_str);
    }

    for (castling_str) |c| {
        if (c == '-') {
            break;
        }

        const color = if (std.ascii.isUpper(c)) Color.White else Color.Black;
        const color_idx = @intFromEnum(color);

        switch (std.ascii.toLower(c)) {
            'k' => {
                board.meta.castling_rights[color_idx].king_side = true;
            },
            'q' => {
                board.meta.castling_rights[color_idx].queen_side = true;
            },
            else => {},
        }
    }

    board.meta.half_moves = parseInt(usize, half_move_str);

    _ = full_move_str;

    return BoardState{ .board = board, .active_color = active_color };
}
