const std = @import("std");
const rl = @import("raylib");
const rlg = @import("raygui");

const ZigFish = @import("zigfish");

const UiState = @import("state.zig");

const Self = @This();

// https://github.com/Not-Nik/raylib-zig/issues/131
pub extern "c" fn GuiSetStyle(control: rlg.GuiControl, property: c_int, value: c_int) void;
pub extern "c" fn GuiGetStyle(control: rlg.GuiControl, property: c_int) c_int;

const RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT = 24;
const MARGIN = 8;
const MOVE_HIST_HEIGHT = 150 * 6;

x_offset: f32,
scrollOffset: rl.Vector2 = .{ .x = 0, .y = 0 },
content: rl.Rectangle = rl.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 },
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

fn getScrollBarY(self: *Self) f32 {
    return self.content.y + self.content.height + self.scrollOffset.y;
}

fn drawMoveHist(self: *Self, state: *UiState, bounds: rl.Rectangle) !void {
    var move_num: usize = 0;

    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    GuiSetStyle(.default, @intFromEnum(rlg.GuiDefaultProperty.text_size), @as(c_int, 32));

    // scroll example https://github.com/raysan5/raygui/blob/master/examples/animation_curve/animation_curve.c
    // https://www.reddit.com/r/raylib/comments/12ezor0/animation_curves_demo_in_c/

    var view = rl.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
    _ = rlg.guiScrollPanel(bounds, "moves", self.content, &self.scrollOffset, &view);

    rl.beginScissorMode(@intFromFloat(bounds.x), @intFromFloat(bounds.y + RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT), @intFromFloat(bounds.width), @intFromFloat(bounds.height));
    defer rl.endScissorMode();

    const scroll_bar_width = @as(f32, @floatFromInt(GuiGetStyle(.listview, @intFromEnum(rlg.GuiListViewProperty.scrollbar_width))));
    self.content = rl.Rectangle{
        .x = bounds.x + MARGIN,
        .y = bounds.y + RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT + MARGIN,
        .width = bounds.width - 2 * MARGIN - scroll_bar_width,
        .height = 0,
    };

    // Iter over 2 move pairs (ie white and black)
    var move_iter = std.mem.window(ZigFish.Move, state.move_history.items, 2, 2);
    while (move_iter.next()) |window| {
        var x_offset: f32 = 0;
        const box_width = 120;
        const box_height = 40;
        for (window) |move| {
            // const y_offset: f32 = (@as(f32, @floatFromInt(move_num)) * box_height);
            const rect = self.getOffsetRect(20 + x_offset, self.getScrollBarY(), box_width, box_height);
            var move_buf = [_]u8{' '} ** 8;

            const move_str = try toCStr(allocator, move.toSanBuf(&move_buf));

            if (rlg.guiLabelButton(rect, move_str) > 0) {
                // TOOD: if this a std.log.debug print if i click during search it crashes??
                std.debug.print("pressed move: {s}\n", .{move_str});
            }
            x_offset += box_width;
        }
        move_num += 1;

        self.content.height += box_height;
    }
}

pub fn draw(self: *Self, state: *UiState) !void {
    // const font_size = GuiGetStyle(.default, @intFromEnum(rlg.GuiDefaultProperty.text_size));
    // std.debug.print("font_size: {}\n", .{font_size});

    // rl.beginScissorMode(@intFromFloat(self.x_offset), 0, 150 * 3, 150 * 8);
    // defer rl.endScissorMode();

    GuiSetStyle(.default, @intFromEnum(rlg.GuiDefaultProperty.text_size), @as(c_int, 16));

    _ = rlg.guiSliderBar(
        self.getOffsetRect(200, 10, 100, 40),
        "Engine search time (sec)",
        rl.textFormat("%.2f", .{state.options.search_time}),
        &state.options.search_time,
        0.0,
        10,
    );

    const bounds = self.getOffsetRect(0, 40, 150 * 3, MOVE_HIST_HEIGHT - 40);
    try self.drawMoveHist(state, bounds);

    var iconRect = self.getOffsetRect(MARGIN, bounds.y + bounds.height, 80, 40);

    // go to first move
    if (rlg.guiButton(iconRect, rlg.guiIconText(@intFromEnum(rlg.GuiIconName.icon_player_previous), "")) > 0) {
        std.debug.print("pressed first move\n", .{});
    }

    iconRect.x += iconRect.width + (MARGIN / 2);

    // go back one move
    if (rlg.guiButton(iconRect, rlg.guiIconText(@intFromEnum(rlg.GuiIconName.icon_arrow_left_fill), "")) > 0) {
        std.debug.print("pressed left fill\n", .{});
    }

    iconRect.x += iconRect.width + (MARGIN / 2);

    // forward one move
    if (rlg.guiButton(iconRect, rlg.guiIconText(@intFromEnum(rlg.GuiIconName.icon_arrow_right_fill), "")) > 0) {
        std.debug.print("pressed rght fill\n", .{});
    }

    iconRect.x += iconRect.width + (MARGIN / 2);

    // go to most recent move
    if (rlg.guiButton(iconRect, rlg.guiIconText(@intFromEnum(rlg.GuiIconName.icon_player_next), "")) > 0) {
        std.debug.print("pressed last move\n", .{});
    }
}
