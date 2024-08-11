const std = @import("std");
const rl = @import("raylib");
const rlg = @import("raygui");

const UiState = @import("state.zig");

const Self = @This();

x_offset: f32,

fn getOffsetRect(self: *const Self, x: f32, y: f32, width: f32, height: f32) rl.Rectangle {
    return rl.Rectangle.init(x + self.x_offset, y, width, height);
}

pub fn draw(self: *const Self, state: *UiState) !void {
    var slider_buf: [5:0]u8 = .{' '} ** 5;
    _ = try std.fmt.bufPrint(&slider_buf, "{d:.2}", .{state.options.search_time});

    _ = rlg.guiSliderBar(
        self.getOffsetRect(130, 10, 100, 40),
        "Think time (sec)",
        &slider_buf, // this looks weird?
        &state.options.search_time,
        0.0,
        10,
    );
}
