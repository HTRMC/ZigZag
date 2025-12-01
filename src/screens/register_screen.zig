const std = @import("std");
const types = @import("types.zig");
const center = @import("../ui/center.zig");
const draw = @import("../ui/draw.zig");
const field_renderer = @import("../ui/field_renderer.zig");

pub const RegisterScreenState = struct {
    username_buffer: []const u8,
    password_buffer: []const u8,
    confirm_password_buffer: []const u8,
    field: types.RegisterField,
    username_cursor: usize,
    password_cursor: usize,
    confirm_password_cursor: usize,
};

pub fn render(
    stdout: anytype,
    offset: center.CenterOffset,
    state: RegisterScreenState,
    cursor_visible: *bool,
) !void {
    // REGISTER SCREEN
    try center.writeCenteredLine(stdout, offset, "╔════════════════════════════════════════╗");
    try center.writeCenteredLine(stdout, offset, "║        Register Form (ZigZag)          ║");
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

    // Confirm Password field
    const confirm_result = field_renderer.renderFieldLine(
        "Confirm:  ",
        state.confirm_password_buffer,
        .password,
        state.field == .confirm_password,
    );
    try center.writeCenteredLine(stdout, offset, confirm_result.buf[0..confirm_result.len]);

    try center.writeCenteredLine(stdout, offset, "║                                        ║");

    // Create Account button
    if (state.field == .create_account) {
        try center.writeCenteredLine(stdout, offset, "║ ► Create Account                       ║");
    } else {
        try center.writeCenteredLine(stdout, offset, "║   Create Account                       ║");
    }

    try center.writeCenteredLine(stdout, offset, "║                                        ║");

    // Back to Login button
    if (state.field == .back_to_login) {
        try center.writeCenteredLine(stdout, offset, "║ ► Already have an account? Login       ║");
    } else {
        try center.writeCenteredLine(stdout, offset, "║   Already have an account? Login       ║");
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
    } else if (state.field == .confirm_password) {
        const cursor_col: u16 = @intCast(offset.col + 14 + state.confirm_password_cursor);
        try draw.moveCursor(stdout, offset.row + 9, cursor_col + 1);
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