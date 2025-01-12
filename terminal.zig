const std = @import("std");

const format = @import("format.zig");

const Terminal = @This();

const standard_input = std.io.getStdIn();
const standard_output = std.io.getStdOut();

pub const Color = enum(u4) {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,

    fn foreground(color: Color) u8 {
        return switch (@intFromEnum(color)) {
            @intFromEnum(Color.black)...@intFromEnum(Color.white) => @as(u8, @intFromEnum(color)) + 30,
            @intFromEnum(Color.bright_black)...@intFromEnum(Color.bright_white) => @as(u8, @intFromEnum(color) - 8) + 90,
        };
    }

    fn background(color: Color) u8 {
        return switch (@intFromEnum(color)) {
            @intFromEnum(Color.black)...@intFromEnum(Color.white) => @as(u8, @intFromEnum(color)) + 40,
            @intFromEnum(Color.bright_black)...@intFromEnum(Color.bright_white) => @as(u8, @intFromEnum(color) - 8) + 100,
        };
    }
};

pub const Point = struct { x: u16, y: u16 };
pub const Position = struct { x: i16, y: i16 };
pub const Size = struct { width: u16, height: u16 };

var original_termios: std.posix.termios = undefined;
pub var size: Size = undefined;

pub fn initialize() void {
    set_size();
    register_resize_handler(set_size);
}

fn set_size() void {
    size = get_size();
}

fn apply_termios(termios: std.posix.termios) void {
    std.posix.tcsetattr(standard_input.handle, .NOW, termios) catch abort();
}

/// Makes the terminal non-canonical so that keypresses are received immediately and disables echoing of input.
/// Assumes the terminal is cooked before this is called.
pub fn make_raw() void {
    original_termios = std.posix.tcgetattr(standard_input.handle) catch abort();
    var new_termios = original_termios;

    // Make the terminal non-canonical so that keypresses are received immediately.
    new_termios.lflag.ICANON = false;
    // Disable echoing so that keystrokes are not printed to the terminal.
    new_termios.lflag.ECHO = false;

    apply_termios(new_termios);
}

/// Makes the terminal canonical to enable line editing and disables echoing of input.
/// Assumes make_raw was called previously.
pub fn make_cooked() void {
    apply_termios(original_termios);
}

fn get_size() Size {
    var winsize: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    const @"error" = std.posix.system.ioctl(standard_output.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize));
    if (std.posix.errno(@"error") == .SUCCESS) {
        return .{ .width = winsize.col, .height = winsize.row };
    } else abort();
}

fn register_resize_handler(handler: fn () void) void {
    const internal_handler = struct {
        fn internal_handler(signal: c_int) callconv(.C) void {
            std.debug.assert(signal == std.posix.SIG.WINCH);
            handler();
        }
    }.internal_handler;
    const act = std.posix.Sigaction{
        .handler = .{ .handler = internal_handler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    // WINCH stands for WINdow CHange.
    std.posix.sigaction(std.posix.SIG.WINCH, &act, null);
}

var buffer: [8192]u8 = undefined;
var buffer_offset: u16 = 0;

pub fn write(bytes: []const u8) void {
    std.debug.assert(bytes.len <= buffer.len);
    if (buffer_offset + bytes.len >= buffer.len) {
        flush();
    }
    @memcpy(buffer[buffer_offset..][0..bytes.len], bytes);
    buffer_offset += @intCast(bytes.len);
}

pub fn print(slices: []const []const u8) void {
    for (slices) |slice| write(slice);
}

pub fn read_byte() error{signal}!u8 {
    var pollfds = [_]std.posix.pollfd{
        .{ .fd = standard_input.handle, .events = std.os.linux.POLL.IN, .revents = undefined },
    };
    const non_zero_revents_pollfd_count = std.posix.ppoll(&pollfds, null, null) catch |err| {
        switch (err) {
            error.SignalInterrupt => return error.signal,
            else => abort(),
        }
    };
    std.debug.assert(non_zero_revents_pollfd_count == 1);
    return read_byte_ignore_signal();
}

pub fn read_byte_ignore_signal() u8 {
    var byte_buffer: [1]u8 = undefined;
    const amount = standard_input.read(&byte_buffer) catch abort();
    if (amount != 1) abort();
    return byte_buffer[0];
}

pub const MouseButton = packed struct(u8) {
    state: enum(u2) {
        left,
        middle,
        right,
        release,
    },
    modifier: packed struct(u3) {
        shift: bool,
        meta: bool,
        control: bool,
    },
    _: u3,
};

pub fn read_mouse() ?struct { point: Point, button: MouseButton } {
    const escape = read_byte() catch return null;
    if (escape == std.ascii.control_code.esc) {
        const left_square_bracket = read_byte() catch return null;
        if (left_square_bracket == '[') {
            const m = read_byte() catch return null;
            if (m == 'M') {
                const button: MouseButton = @bitCast(read_byte() catch return null);
                const x = (read_byte() catch return null) - ' ' - 1;
                const y = (read_byte() catch return null) - ' ' - 1;
                return .{
                    .point = .{ .x = x, .y = y },
                    .button = button,
                };
            }
        }
    }
    return null;
}

pub fn flush() void {
    standard_output.writeAll(buffer[0..buffer_offset]) catch abort();
    buffer_offset = 0;
}

pub fn reset() void {
    write(csi ++ "0m");
}

pub fn set_color(foreground: Color, background: Color) void {
    var foreground_buffer: [format.maximum_length(@TypeOf(foreground.foreground()))]u8 = undefined;
    const foreground_formatted = format.decimal(foreground.foreground(), &foreground_buffer);
    var background_buffer: [format.maximum_length(@TypeOf(background.background()))]u8 = undefined;
    const background_formatted = format.decimal(background.background(), &background_buffer);
    print(&.{ csi, foreground_formatted, ";", background_formatted, "m" });
}

pub fn set_foreground_color(foreground: Color) void {
    var foreground_buffer: [format.maximum_length(@TypeOf(foreground.foreground()))]u8 = undefined;
    const foreground_formatted = format.decimal(foreground.foreground(), &foreground_buffer);
    print(&.{ csi, foreground_formatted, "m" });
}

pub fn set_background_color(background: Color) void {
    var background_buffer: [format.maximum_length(@TypeOf(background.background()))]u8 = undefined;
    const background_formatted = format.decimal(background.background(), &background_buffer);
    print(&.{ csi, background_formatted, "m" });
}

/// Control Sequence Indicator.
const csi = "\x1b[";

/// Operating System Command.
const osc = "\x1b]";

const alert = [_]u8{std.ascii.control_code.bel};

//pub fn dim_foreground_color() void {
//    stdout.writeAll(csi ++ "2m") catch abort();
//}
//pub fn undim_foreground_color() void {
//    stdout.writeAll(csi ++ "22m") catch abort();
//}

pub fn enable_secondary_screen() void {
    write("\x1b[?1049h");
}

pub fn disable_secondary_screen() void {
    write(csi ++ "?1049l");
}

pub fn clear() void {
    write(csi ++ "2J");
}

pub fn reset_cursor() void {
    write(csi ++ ";H");
}

pub fn enable_mouse_tracking() void {
    write(csi ++ "?1003h");
}

pub fn disable_mouse_tracking() void {
    write(csi ++ "?1003l");
}

pub fn hide_cursor() void {
    write(csi ++ "?25l");
}

pub fn show_cursor() void {
    write(csi ++ "?25h");
}

//pub fn set_background_color(color: u24) void {
//    print(osc ++ "11;#{X:0<8}" ++ alert, .{color});
//}
//pub fn reset_background_color() void {
//    stdout.writeAll(osc ++ "111" ++ alert) catch abort();
//}

//pub fn set_foreground_color(color: u24) void {
//    print(osc ++ "10;#{X:0<8}" ++ alert, .{color});
//}
//pub fn reset_foreground_color() void {
//    stdout.writeAll(osc ++ "110" ++ alert) catch abort();
//}

//pub fn set_abort_signal_handler(comptime handler: *const fn () void) void {
//    const internal_handler = struct {
//        fn internal_handler(sig: c_int) callconv(.C) void {
//            std.debug.assert(sig == std.posix.SIG.INT);
//            handler();
//        }
//    }.internal_handler;
//    const act = std.posix.Sigaction{
//        .handler = .{ .handler = internal_handler },
//        .mask = std.posix.empty_sigset,
//        .flags = 0,
//    };
//    std.posix.sigaction(std.posix.SIG.INT, &act, null) catch abort();
//}

fn abort() noreturn {
    std.process.exit(1);
}
