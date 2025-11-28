const std = @import("std");

pub fn hideCursor(writer: anytype) !void {
    try writer.writeAll("\x1b[?25l");
}

pub fn showCursor(writer: anytype) !void {
    try writer.writeAll("\x1b[?25h");
}

pub fn moveCursor(writer: anytype, row: u16, col: u16) !void {
    try writer.print("\x1b[{d};{d}H", .{ row, col });
}
