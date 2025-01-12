const format = @import("format.zig");
const terminal = @import("terminal.zig");

const Blocks = @This();

blocks: [0xff * 0xff]Block = undefined,

const Block = struct {
    upper_half: terminal.Color,
    lower_half: terminal.Color,
};

fn get_block(blocks: *Blocks, x: u16, y: u16) *Block {
    return &blocks.blocks[x + ((y / 2) * terminal.size.width)];
}

pub fn set(blocks: *Blocks, x: u16, y: u16, color: terminal.Color) void {
    const block = blocks.get_block(x, y);
    if (y % 2 == 0) {
        block.upper_half = color;
    } else {
        block.lower_half = color;
    }
}

pub fn get(blocks: Blocks, x: u16, y: u16) terminal.Color {
    const block = blocks.get_block(x, y).*;
    return if (y % 2 == 0) block.upper_half else block.lower_half;
}

pub fn clear(blocks: *Blocks, color: terminal.Color) void {
    @memset(&blocks.blocks, .{ .upper_half = color, .lower_half = color });
}

pub fn draw(blocks: Blocks) void {
    var y: u16 = 0;
    while (y < terminal.size.height * 2) {
        var x: u16 = 0;
        while (x < terminal.size.width) {
            const block = @as(*Blocks, @constCast(&blocks)).get_block(x, y).*;
            if (block.upper_half == block.lower_half) {
                terminal.set_background_color(block.upper_half);
                terminal.write(" ");
            } else {
                terminal.set_color(block.upper_half, block.lower_half);
                terminal.write("▀");
            }
            x += 1;
        }
        y += 2;
    }
}
