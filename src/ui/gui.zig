const std = @import("std");
const rl = @import("raylib");
const rlg = @import("raygui");

const ZigFish = @import("zigfish");

const UiState = @import("state.zig");

const Self = @This();

// https://github.com/Not-Nik/raylib-zig/issues/131
pub extern "c" fn GuiSetStyle(control: rlg.GuiControl, property: c_int, value: c_int) void;
pub extern "c" fn GuiGetStyle(control: rlg.GuiControl, property: c_int) c_int;

x_offset: f32,
// font: rl.Font,

fn getOffsetRect(self: *const Self, x: f32, y: f32, width: f32, height: f32) rl.Rectangle {
    return rl.Rectangle.init(x + self.x_offset, y, width, height);
}

fn toCStr(allocator: std.mem.Allocator, str: []u8) ![*:0]u8 {
    const slice = try std.mem.Allocator.dupeZ(allocator, u8, str);
    return slice.ptr;
}

pub fn init(
    x_offset: f32,
    // font: rl.Font,
) Self {
    // rlg.guiSetFont(font);
    return Self{
        .x_offset = x_offset,
        // .font = font,
    };
}

pub fn deint(self: *Self) void {
    _ = self;
    // self.font.unload();
}

pub fn draw(self: *const Self, state: *UiState) !void {
    // const font_size = GuiGetStyle(.default, @intFromEnum(rlg.GuiDefaultProperty.text_size));
    // std.debug.print("font_size: {}\n", .{font_size});

    GuiSetStyle(.default, @intFromEnum(rlg.GuiDefaultProperty.text_size), @as(c_int, 16));

    _ = rlg.guiSliderBar(
        self.getOffsetRect(200, 10, 100, 40),
        "Engine search time (sec)",
        rl.textFormat("%.2f", .{state.options.search_time}),
        &state.options.search_time,
        0.0,
        10,
    );

    var move_num: usize = 0;

    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    GuiSetStyle(.default, @intFromEnum(rlg.GuiDefaultProperty.text_size), @as(c_int, 32));

    // Iter over 2 move pairs (ie white and black)
    var move_iter = std.mem.window(ZigFish.Move, state.move_history.items, 2, 2);
    while (move_iter.next()) |window| {
        move_num += 1;
        var x_offset: f32 = 0;
        const box_width = 100;
        const box_height = 40;
        for (window) |move| {
            const y_offset: f32 = (@as(f32, @floatFromInt(move_num)) * box_height);
            const rect = self.getOffsetRect(20 + x_offset, 50 + y_offset, box_width, box_height);
            var move_buf = [_]u8{' '} ** 8;

            const move_str = try toCStr(allocator, move.toSanBuf(&move_buf));

            if (rlg.guiLabelButton(rect, move_str) > 0) {
                // TOOD: if this a std.log.debug print if i click during search it crashes??
                std.debug.print("pressed move: {s}\n", .{move_str});
            }
            x_offset += box_width;
        }
    }
}
