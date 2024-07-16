const std = @import("std");
const utils = @import("utils.zig");

const board_types = @import("board.zig");
const Position = board_types.Position;

const piece = @import("piece.zig");
const Color = piece.Color;
const Kind = piece.Kind;
const NUM_KINDS = utils.enum_len(piece.Kind);
const NUM_COLOR = utils.enum_len(piece.Color);

// var prng = std.rand.DefaultPrng.init(blk: {
//     var seed: u64 = undefined;
//     std.posix.getrandom(std.mem.asBytes(&seed)) catch 1000;
//     break :blk seed;
// });

fn randomU64(rand: std.Random) u64 {
    return rand.int(u64);
}

fn randomSlice(comptime len: usize, rand: std.Random) [len]u64 {
    var res: [len]u64 = undefined;
    for (0..len) |i| {
        res[i] = randomU64(rand);
    }

    return res;
}

// const PieceNums = [NUM_COLOR][NUM_KINDS][64]u64;

// fn genPieceNum(rand: std.Random) PieceNums {
//     var res: PieceNums = undefined;
//     inline for (utils.enum_fields(Color)) |f_c| {
//         const color_idx = f_c.value;
//         inline for (utils.enum_fields(Kind)) |f_k| {
//             const kind_idx = f_k.value;
//             res[color_idx][kind_idx] = randomSlice(64, rand);
//         }
//     }

//     return res;
// }

const NUM_PIECE_SQAURES = 64 * NUM_KINDS * NUM_COLOR;
const PieceNums = [NUM_PIECE_SQAURES]u64;

// https://www.chessprogramming.org/Zobrist_Hashing
pub const ZHashing = struct {
    const Self = @This();

    // rand: std.Random,
    piece_nums: [NUM_PIECE_SQAURES]u64,
    black_to_move: u64,
    castle_rights: [4]u64,
    enpassant_files: [8]u64,

    pub fn init() ZHashing {
        @setEvalBranchQuota((NUM_PIECE_SQAURES + 4 + 8 + 1) * 100);
        // seed picked from no where...
        var prng = std.rand.DefaultPrng.init(3_475_632);
        const rand = prng.random();

        return ZHashing{
            .black_to_move = randomU64(rand),
            .piece_nums = randomSlice(NUM_PIECE_SQAURES, rand),
            .castle_rights = randomSlice(4, rand),
            .enpassant_files = randomSlice(8, rand),
        };
    }

    pub fn getPieceNum(self: Self, p: piece.Piece, pos: Position) u64 {
        const color_idx: usize = @intFromEnum(p.color);
        const kind_idx: usize = @intFromEnum(p.kind);
        const pos_idx = pos.toIndex();

        const idx = (pos_idx) + (color_idx * 64) + (kind_idx * 64 * NUM_COLOR);

        return self.piece_nums[idx];
    }

    pub fn getCastleRights(self: Self, color: Color, is_king_side: bool) u64 {
        const color_idx: usize = @intFromEnum(color);
        const side_idx: usize = @intFromBool(is_king_side);

        const idx = color_idx + (side_idx * NUM_COLOR);

        return self.castle_rights[idx];
    }

    pub fn getEnPassant(self: Self, pos: Position) u64 {
        const file: usize = pos.toRankFile().file;

        return self.enpassant_files[file];
    }
};

pub const ZHASHER = ZHashing.init();
