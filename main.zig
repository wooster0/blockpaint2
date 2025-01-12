const std = @import("std");

const format = @import("format.zig");
const terminal = @import("terminal.zig");
const Blocks = @import("Blocks.zig");

pub const std_options: std.Options = .{ .keep_sigpipe = true };

var pixels: Blocks = undefined;

pub fn main() void {
    terminal.initialize();

    defer terminal.flush();
    terminal.enable_secondary_screen();
    defer terminal.disable_secondary_screen();
    terminal.enable_mouse_tracking();
    defer terminal.disable_mouse_tracking();
    terminal.make_raw();
    defer terminal.make_cooked();
    terminal.hide_cursor();
    defer terminal.show_cursor();

    pixels.clear(.white);

    while (true) {
        terminal.clear();
        terminal.reset_cursor();
        draw();
        terminal.flush();
        update();
    }
}

fn draw() void {
    pixels.draw();
}

var last_point: ?terminal.Point = null;

fn update() void {
    const color: terminal.Color = .black;
    if (terminal.read_mouse()) |mouse| {
        if (mouse.button.state == .left) {
            pixels.set(mouse.point.x, mouse.point.y * 2, color);
            if (last_point) |point| {
                if (point.y < mouse.point.y) {
                    pixels.set(mouse.point.x, mouse.point.y * 2 - 1, color);
                } else if (point.y > mouse.point.y) {
                    pixels.set(mouse.point.x, mouse.point.y * 2 + 1, color);
                }
            }
            last_point = mouse.point;
        } else if (mouse.button.state == .release) {
            last_point = null;
        }
    }
}

fn abort() noreturn {
    std.process.exit(1);
}

test {
    _ = format;
}
