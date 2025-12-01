const std = @import("std");
const types = @import("types.zig");
const center = @import("../ui/center.zig");
const draw = @import("../ui/draw.zig");
const field_renderer = @import("../ui/field_renderer.zig");

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
    // LOGIN SCREEN
    try center.writeCenteredLine(stdout, offset, "╔════════════════════════════════════════╗");
    try center.writeCenteredLine(stdout, offset, "║          Login Form (ZigZag)           ║");
    try center.writeCenteredLine(stdout, offset, "╠════════════════════════════════════════╣");
    try center.writeCenteredLine(stdout, offset, "║                                        ║");

    // Username field
    const username_result = field_renderer.renderFieldLine(
        "Username: ",
        state.username_buffer,
        .text,
        state.field == .username,
    );
    try center.writeCenteredLine(stdout, offset, username_result.buf[0..username_result.len]);

    try center.writeCenteredLine(stdout, offset, "║                                        ║");

    // Password field
    const password_result = field_renderer.renderFieldLine(
        "Password: ",
        state.password_buffer,
        .password,
        state.field == .password,
    );
    try center.writeCenteredLine(stdout, offset, password_result.buf[0..password_result.len]);

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