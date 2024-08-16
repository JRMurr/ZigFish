const std = @import("std");
const builtin = @import("builtin");

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
    rlg.guiLoadStyle("resources/style_dark.rgs");
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
    // skip the first move since its the dummy
    const move_hist = state.move_history.items[1..];

    // start at 1 to skip the dummy move
    var move_num: usize = 1;

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
    var move_iter = std.mem.window(UiState.MoveHist, move_hist, 2, 2);
    // idx of the move currently shown on the board
    const shown_move = if (state.hist_index) |idx| idx else move_hist.len;
    while (move_iter.next()) |window| {
        var x_offset: f32 = 0;
        const box_width = 120;
        const box_height = 40;
        for (window) |mh| {
            const rect = self.getOffsetRect(20 + x_offset, self.getScrollBarY(), box_width, box_height);
            var move_buf = [_]u8{' '} ** 8;

            const move_str = try toCStr(allocator, mh.move.toSanBuf(&move_buf));

            if (shown_move == move_num) {
                _ = rlg.guiDummyRec(rect, "");
            }

            if (rlg.guiLabelButton(rect, move_str) > 0) {
                state.selectHist(move_num);
            }
            x_offset += box_width;
            move_num += 1;
        }

        self.content.height += box_height;
    }
}

pub fn draw(self: *Self, state: *UiState) !void {
    // const font_size = GuiGetStyle(.default, @intFromEnum(rlg.GuiDefaultProperty.text_size));
    // std.debug.print("font_size: {}\n", .{font_size});

    // rl.beginScissorMode(@intFromFloat(self.x_offset), 0, 150 * 3, 150 * 8);
    // defer rl.endScissorMode();

    if (state.game_status != .InProgress) {
        const cell_size = 150; // TODO:
        const rect = rl.Rectangle{ .x = cell_size * 3, .y = cell_size * 3, .width = cell_size * 2, .height = cell_size * 2 };
        const msg = switch (state.game_status) {
            .BlackWin => "Black Win",
            .WhiteWin => "White Win",
            .Draw => "Draw",
            .InProgress => unreachable,
        };
        rlg.guiSetAlpha(0.85);
        defer rlg.guiSetAlpha(1);
        _ = rlg.guiDummyRec(rect, msg);
    }

    GuiSetStyle(.default, @intFromEnum(rlg.GuiDefaultProperty.text_size), @as(c_int, 16));

    var height: f32 = 0;

    _ = rlg.guiLabel(self.getOffsetRect(MARGIN, height, 200, 20), "Engine search time (sec)");
    height += 20;
    height += MARGIN / 2;

    _ = rlg.guiSliderBar(
        self.getOffsetRect(MARGIN, height, 150, 20),
        "",
        rl.textFormat("%.2f", .{state.options.search_time}),

        &state.options.search_time,
        0.0,
        10,
    );

    height += 20;
    height += MARGIN / 2;

    _ = rlg.guiCheckBox(self.getOffsetRect(MARGIN, height, 20, 20), "Ai on", &state.options.ai_on);
    height += 20;
    height += MARGIN / 2;

    if (!builtin.target.isWasm()) {
        _ = rlg.guiCheckBox(self.getOffsetRect(MARGIN, height, 20, 20), "Use opening book", &state.options.use_opening_book);
        height += 20;
        height += MARGIN / 2;
    }

    const bounds = self.getOffsetRect(0, height, 150 * 3, MOVE_HIST_HEIGHT - 40);
    try self.drawMoveHist(state, bounds);

    var iconRect = self.getOffsetRect(MARGIN, bounds.y + bounds.height, 80, 40);

    // go to first move
    if (rlg.guiButton(iconRect, rlg.guiIconText(@intFromEnum(rlg.GuiIconName.icon_player_previous), "")) > 0) {
        state.firstMove();
    }

    iconRect.x += iconRect.width + (MARGIN / 2);

    // go back one move
    if (rlg.guiButton(iconRect, rlg.guiIconText(@intFromEnum(rlg.GuiIconName.icon_arrow_left_fill), "")) > 0) {
        state.prevMove();
    }

    iconRect.x += iconRect.width + (MARGIN / 2);

    // forward one move
    if (rlg.guiButton(iconRect, rlg.guiIconText(@intFromEnum(rlg.GuiIconName.icon_arrow_right_fill), "")) > 0) {
        state.nextMove();
    }

    iconRect.x += iconRect.width + (MARGIN / 2);

    // go to most recent move
    if (rlg.guiButton(iconRect, rlg.guiIconText(@intFromEnum(rlg.GuiIconName.icon_player_next), "")) > 0) {
        state.lastMove();
    }
}
