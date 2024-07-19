const std = @import("std");
const testing = std.testing;
const ZigFish = @import("root.zig");

const utils = ZigFish.Utils;

const Piece = @import("piece.zig");
const Color = Piece.Color;
const Kind = Piece.Kind;

const Board = ZigFish.Board;
const Position = ZigFish.Position;
const PositionRankFile = ZigFish.PositionRankFile;

fn parseInt(comptime T: type, buf: []const u8) T {
    return std.fmt.parseInt(T, buf, 10) catch |err| {
        std.debug.panic("erroring parsing {s} as {s}. Err: {}", .{ buf, @typeName(T), err });
    };
}

pub fn parse(str: []const u8) Board {
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
            if (std.ascii.isAlphabetic(char)) {
                const piece = Piece.fromChar(char);
                board.setPos(curr_pos.toPosition(), piece);
                curr_pos.file += 1;
            } else {
                const num_empty = char - '0';
                curr_pos.file +%= num_empty;
            }
        }

        if (curr_pos.rank > 0) curr_pos.rank -= 1;
    }

    board.active_color = if (std.mem.eql(u8, active_color_str, "w")) Color.White else Color.Black;

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

    board.full_moves = parseInt(usize, full_move_str);

    board.initHash();

    return board;
}

const MAX_FEN_LEN = 90; // probably could reduce this but who cares

const digitToChar = std.fmt.digitToChar;

pub fn toFen(board: Board) [MAX_FEN_LEN]u8 {
    // TOOD: see if i can do a sentil terminated slice
    var str = comptime utils.initStr(' ', MAX_FEN_LEN);
    var idx: usize = 0;

    for (0..8) |r| {
        var num_empty: u8 = 0;
        const rank = 7 - r;
        for (0..8) |file| {
            const pos = Position.fromRankFile(.{ .rank = @intCast(rank), .file = @intCast(file) });
            if (board.getPos(pos)) |p| {
                if (num_empty > 0) {
                    str[idx] = digitToChar(num_empty, .lower);
                    idx += 1;
                }
                str[idx] = p.toChar();
                idx += 1;
                num_empty = 0;
            } else {
                num_empty += 1;
            }
        }
        if (num_empty != 0) {
            str[idx] = digitToChar(num_empty, .lower);
            idx += 1;
        }
        if (rank != 0) {
            str[idx] = '/';
            idx += 1;
        }
    }

    str[idx] = ' ';
    idx += 1;

    const active_char: u8 = if (board.active_color == Color.White) 'w' else 'b';
    str[idx] = active_char;
    idx += 1;

    str[idx] = ' ';
    idx += 1;

    var can_castle = false;
    for (0..Piece.NUM_COLOR) |color_idx| {
        const color: Color = @enumFromInt(color_idx);
        const castling_rights = board.meta.castling_rights[color_idx];
        if (!castling_rights.canCastle()) {
            continue;
        }
        for (castling_rights.toStr()) |c| {
            const char = if (color == Color.Black)
                c + 32
            else
                c;
            str[idx] = char;
            idx += 1;
        }
        can_castle = true;
    }

    if (!can_castle) {
        str[idx] = '-';
        idx += 1;
    }

    str[idx] = ' ';
    idx += 1;

    if (board.meta.en_passant_pos) |p| {
        const pos_str = p.toStr();
        str[idx] = pos_str[0];
        idx += 1;
        str[idx] = pos_str[1];
        idx += 1;
    } else {
        str[idx] = '-';
        idx += 1;
    }

    str[idx] = ' ';
    idx += 1;

    const num_idx = std.fmt.formatIntBuf(str[idx .. idx + 2], board.meta.half_moves, 10, .lower, .{});
    idx += num_idx;

    str[idx] = ' ';
    idx += 1;

    _ = std.fmt.formatIntBuf(str[idx .. idx + 2], board.full_moves, 10, .lower, .{});

    return str;
}

test "no static erros" {
    std.testing.refAllDeclsRecursive(@This());
}

fn toAndFromFen(str: []const u8) anyerror!void {
    const board = parse(str);

    const fen = toFen(board);

    try std.testing.expectStringStartsWith(&fen, str);
}

test "start pos to from" {
    try toAndFromFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
}

test "bigger half moves to from" {
    try toAndFromFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 10 20");
}

test "non start to from" {
    try toAndFromFen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R b KQ - 1 8");
}
