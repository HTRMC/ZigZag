const std = @import("std");
const types = @import("types.zig");
const center = @import("../ui/center.zig");
const draw = @import("../ui/draw.zig");

pub const LoginScreenState = struct {
    username_buffer: []const u8,
    password_buffer: []const u8,
    field: types.LoginField,
    username_cursor: usize,
    password_cursor: usize,
};

pub fn render(
    stdout: anytype,
    offset: center.CenterOffset,
    state: LoginScreenState,
    cursor_visible: *bool,
) !void {
    const username_len = state.username_buffer.len;
    const password_len = state.password_buffer.len;

    // LOGIN SCREEN
    try center.writeCenteredLine(stdout, offset, "╔════════════════════════════════════════╗");
    try center.writeCenteredLine(stdout, offset, "║          Login Form (ZigZag)           ║");
    try center.writeCenteredLine(stdout, offset, "╠════════════════════════════════════════╣");
    try center.writeCenteredLine(stdout, offset, "║                                        ║");

    // Username field
    const display_username_len = @min(username_len, 25);
    const username_padding = if (username_len < 27) 27 - username_len else 0;
    const username_line = blk: {
        const prefix = if (state.field == .username) "║ ► Username: " else "║   Username: ";
        var user_buf: [256]u8 = undefined;
        var user_idx: usize = 0;
        @memcpy(user_buf[user_idx..][0..prefix.len], prefix);
        user_idx += prefix.len;
        @memcpy(user_buf[user_idx..][0..display_username_len], state.username_buffer[0..display_username_len]);
        user_idx += display_username_len;
        var i: usize = 0;
        while (i < username_padding) : (i += 1) {
            user_buf[user_idx] = ' ';
            user_idx += 1;
        }
        const suffix = "║";
        @memcpy(user_buf[user_idx..][0..suffix.len], suffix);
        user_idx += suffix.len;
        break :blk user_buf[0..user_idx];
    };
    try center.writeCenteredLine(stdout, offset, username_line);

    try center.writeCenteredLine(stdout, offset, "║                                        ║");

    // Password field
    const display_password_len = @min(password_len, 25);
    const password_padding = if (password_len < 27) 27 - password_len else 0;
    const password_line = blk: {
        const prefix = if (state.field == .password) "║ ► Password: " else "║   Password: ";
        var pwd_buf: [256]u8 = undefined;
        var pwd_idx: usize = 0;
        @memcpy(pwd_buf[pwd_idx..][0..prefix.len], prefix);
        pwd_idx += prefix.len;
        var i: usize = 0;
        while (i < display_password_len) : (i += 1) {
            pwd_buf[pwd_idx] = '*';
            pwd_idx += 1;
        }
        i = 0;
        while (i < password_padding) : (i += 1) {
            pwd_buf[pwd_idx] = ' ';
            pwd_idx += 1;
        }
        const suffix = "║";
        @memcpy(pwd_buf[pwd_idx..][0..suffix.len], suffix);
        pwd_idx += suffix.len;
        break :blk pwd_buf[0..pwd_idx];
    };
    try center.writeCenteredLine(stdout, offset, password_line);

    try center.writeCenteredLine(stdout, offset, "║                                        ║");

    // Forgot password button
    if (state.field == .forgot_password) {
        try center.writeCenteredLine(stdout, offset, "║ ► Forgot your password?                ║");
    } else {
        try center.writeCenteredLine(stdout, offset, "║   Forgot your password?                ║");
    }

    try center.writeCenteredLine(stdout, offset, "║                                        ║");

    // Register button
    if (state.field == .register) {
        try center.writeCenteredLine(stdout, offset, "║ ► Need an account? Register            ║");
    } else {
        try center.writeCenteredLine(stdout, offset, "║   Need an account? Register            ║");
    }

    try center.writeCenteredLine(stdout, offset, "║                                        ║");
    try center.writeCenteredLine(stdout, offset, "╚════════════════════════════════════════╝");
    try center.writeCenteredLine(stdout, offset, "");
    try center.writeCenteredLine(stdout, offset, "↑/↓: Navigate  │  ←/→: Move cursor  │  Enter: Select  │  Esc: Exit");

    // Position cursor
    if (state.field == .username) {
        const cursor_col: u16 = @intCast(offset.col + 14 + state.username_cursor);
        try draw.moveCursor(stdout, offset.row + 5, cursor_col + 1);
        if (!cursor_visible.*) {
            try draw.showCursor(stdout);
            cursor_visible.* = true;
        }
    } else if (state.field == .password) {
        const cursor_col: u16 = @intCast(offset.col + 14 + state.password_cursor);
        try draw.moveCursor(stdout, offset.row + 7, cursor_col + 1);
        if (!cursor_visible.*) {
            try draw.showCursor(stdout);
            cursor_visible.* = true;
        }
    } else {
        // Hide cursor for buttons
        if (cursor_visible.*) {
            try draw.hideCursor(stdout);
            cursor_visible.* = false;
        }
    }
}