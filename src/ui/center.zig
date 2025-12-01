const terminal = @import("../platform/terminal.zig");

pub const CenterOffset = struct {
    row: u16,
    col: u16,
};

pub fn calculateCenterOffset(term_size: terminal.TerminalSize, ui_width: u16, ui_height: u16) CenterOffset {
    const row = if (term_size.height > ui_height) (term_size.height - ui_height) / 2 else 0;
    const col = if (term_size.width > ui_width) (term_size.width - ui_width) / 2 else 0;
    return CenterOffset{ .row = row, .col = col };
}

pub fn writeCenteredLine(writer: anytype, offset: CenterOffset, line: []const u8) !void {
    var i: u16 = 0;
    while (i < offset.col) : (i += 1) {
        try writer.writeAll(" ");
    }
    try writer.writeAll(line);
    try writer.writeAll("\n");
}

pub fn writeCenteredLineWidth(writer: anytype, offset: CenterOffset, line: []const u8, width: u16) !void {
    _ = width; // Width is informational for now
    try writeCenteredLine(writer, offset, line);
}
