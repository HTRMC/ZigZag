const std = @import("std");
const center = @import("../ui/center.zig");
const draw = @import("../ui/draw.zig");

pub const ChatMessage = struct {
    sender: []const u8,
    content: []const u8,
    is_system: bool = false,
};

pub const ChatScreenState = struct {
    username: []const u8,
    messages: []const ChatMessage,
    input_buffer: []const u8,
    input_cursor: usize,
};

pub fn render(
    stdout: anytype,
    offset: center.CenterOffset,
    state: ChatScreenState,
    cursor_visible: *bool,
) !void {
    const messages_height: usize = 12;

    // Header
    try center.writeCenteredLine(stdout, offset, "+----------------------------------------------------------+");

    // Title line with username
    var title_buf: [60]u8 = undefined;
    @memset(&title_buf, ' ');
    const title_text = "ZigZag Chat";
    @memcpy(title_buf[2 .. 2 + title_text.len], title_text);

    // Add username if it fits
    if (state.username.len > 0 and state.username.len < 20) {
        const user_prefix = " - ";
        const user_start = 2 + title_text.len;
        @memcpy(title_buf[user_start .. user_start + user_prefix.len], user_prefix);
        @memcpy(title_buf[user_start + user_prefix.len .. user_start + user_prefix.len + state.username.len], state.username);
    }

    var title_line: [62]u8 = undefined;
    title_line[0] = '|';
    @memcpy(title_line[1..61], &title_buf);
    title_line[61] = '|';
    try center.writeCenteredLine(stdout, offset, &title_line);

    try center.writeCenteredLine(stdout, offset, "+----------------------------------------------------------+");

    // Messages area
    const visible_messages = @min(state.messages.len, messages_height);
    const start_idx = if (state.messages.len > messages_height)
        state.messages.len - messages_height
    else
        0;

    for (0..messages_height) |i| {
        var line_buf: [62]u8 = undefined;
        @memset(&line_buf, ' ');
        line_buf[0] = '|';
        line_buf[61] = '|';

        if (i < visible_messages) {
            const msg = state.messages[start_idx + i];

            // Format: "* system msg" or "<user> message"
            var msg_buf: [58]u8 = undefined;
            @memset(&msg_buf, ' ');

            if (msg.is_system) {
                // System message: "* content"
                msg_buf[0] = '*';
                msg_buf[1] = ' ';
                const copy_len = @min(msg.content.len, 56);
                @memcpy(msg_buf[2 .. 2 + copy_len], msg.content[0..copy_len]);
            } else {
                // User message: "<user> content"
                msg_buf[0] = '<';
                const name_len: usize = @min(msg.sender.len, 12);
                @memcpy(msg_buf[1 .. 1 + name_len], msg.sender[0..name_len]);
                msg_buf[1 + name_len] = '>';
                msg_buf[2 + name_len] = ' ';
                const content_start: usize = 3 + name_len;
                const content_max: usize = if (58 > content_start) 58 - content_start else 0;
                const content_len: usize = @min(msg.content.len, content_max);
                if (content_len > 0) {
                    @memcpy(msg_buf[content_start .. content_start + content_len], msg.content[0..content_len]);
                }
            }

            @memcpy(line_buf[2..60], msg_buf[0..58]);
        }

        try center.writeCenteredLine(stdout, offset, &line_buf);
    }

    // Input separator
    try center.writeCenteredLine(stdout, offset, "+----------------------------------------------------------+");

    // Input line
    var input_line: [62]u8 = undefined;
    @memset(&input_line, ' ');
    input_line[0] = '|';
    input_line[1] = '>';
    input_line[2] = ' ';

    const input_len = @min(state.input_buffer.len, 55);
    @memcpy(input_line[3 .. 3 + input_len], state.input_buffer[0..input_len]);

    input_line[61] = '|';
    try center.writeCenteredLine(stdout, offset, &input_line);

    // Footer
    try center.writeCenteredLine(stdout, offset, "+----------------------------------------------------------+");
    try center.writeCenteredLine(stdout, offset, "");
    try center.writeCenteredLine(stdout, offset, "Enter: Send  |  Esc: Quit");

    // Position cursor in input field
    const cursor_col: u16 = @intCast(offset.col + 3 + state.input_cursor);
    const cursor_row: u16 = @intCast(offset.row + 4 + messages_height + 1);
    try draw.moveCursor(stdout, cursor_row, cursor_col + 1);

    if (!cursor_visible.*) {
        try draw.showCursor(stdout);
        cursor_visible.* = true;
    }
}