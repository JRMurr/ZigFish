const std = @import("std");
const Allocator = std.mem.Allocator;

const ZigFish = @import("root.zig");
const Board = ZigFish.Board;
const Move = ZigFish.Move;
const Pgn = ZigFish.Pgn;
const PgnParser = Pgn.PgnParser;

pub const MoveEntry = struct { move: Move, times_played: usize };
const PlayedMoves = std.ArrayList(MoveEntry);

/// Map of zhash => moves to play in the position
const MoveMap = std.AutoHashMap(u64, PlayedMoves);

const Self = @This();

allocator: Allocator,
move_map: MoveMap,

pub fn init(allocator: Allocator) Self {
    return Self{
        .allocator = allocator,
        .move_map = MoveMap.init(allocator),
    };
}

pub fn readPgn(self: *Self, pgn_str: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    const arena_alloc = arena.allocator();

    const parsed = try PgnParser.many_pgn.parse(arena_alloc, pgn_str);

    const pgns: []Pgn = parsed.value;

    std.debug.print("PGNS: {}\n", .{pgns.len});

    // std.debug.print("rest: {s}\n", .{parsed.rest[0..300]});

    for (pgns) |pgn| {
        var board = Board.initStart();
        for (pgn.moves) |full_move| {
            const moves = full_move.moves().constSlice();
            for (moves) |move_str| {
                // std.debug.print("checking: {s}\n", .{move_str});
                const allowed_moves = board.getAllValidMoves();

                const move = Move.fromSan(move_str, allowed_moves.items());

                var get_res = try self.move_map.getOrPut(board.zhash);
                if (!get_res.found_existing) {
                    get_res.value_ptr.* = PlayedMoves.init(self.allocator);
                }
                const moves_in_position = get_res.value_ptr;
                for (moves_in_position.items) |*move_entry| {
                    if (move_entry.move.eql(move)) {
                        move_entry.times_played += 1;
                        break;
                    }
                } else {
                    // if we didnt see this move storted already we need to add it
                    try get_res.value_ptr.append(MoveEntry{ .move = move, .times_played = 1 });
                }

                board.makeMove(&move);
            }
        }
    }
}

pub fn getPossibleMoves(self: *const Self, zhash: u64) []MoveEntry {
    const maybe_move_entries = self.move_map.get(zhash);

    if (maybe_move_entries == null) {
        var slice: []MoveEntry = undefined;
        slice.len = 0;
        return slice;
    }

    const move_entries = maybe_move_entries.?;

    return move_entries.items;
}
