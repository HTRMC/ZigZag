const std = @import("std");
const types = @import("types.zig");
const center = @import("../ui/center.zig");
const terminal = @import("../platform/terminal.zig");
const draw = @import("../ui/draw.zig");
const screen_manager = @import("screen_manager.zig");
const field_renderer = @import("../ui/field_renderer.zig");

pub fn render(stdout: anytype, manager: *const screen_manager.ScreenManager) !void {
    // Clear screen
    terminal.clearScreen();

    // Calculate center offset for result screen
    const term_size = terminal.getTerminalSize();
    const result_ui_width: u16 = 42; // Box is 42 characters wide
    const result_ui_height: u16 = if (manager.current_screen == .login) 8 else 10; // Login: 8 lines, Register: 10 lines
    const result_offset = center.calculateCenterOffset(term_size, result_ui_width, result_ui_height);

    // Move cursor to starting position
    try draw.moveCursor(stdout, result_offset.row + 1, 1);

    try center.writeCenteredLine(stdout, result_offset, "╔════════════════════════════════════════╗");

    if (manager.current_screen == .login) {
        try center.writeCenteredLine(stdout, result_offset, "║              Login Result              ║");
    } else {
        try center.writeCenteredLine(stdout, result_offset, "║           Registration Result          ║");
    }

    try center.writeCenteredLine(stdout, result_offset, "╠════════════════════════════════════════╣");
    try center.writeCenteredLine(stdout, result_offset, "║                                        ║");

    // Username result
    const username_result = field_renderer.renderResultFieldLine(
        "Username: ",
        manager.username_buffer[0..manager.username_len],
    );
    try center.writeCenteredLine(stdout, result_offset, username_result.buf[0..username_result.len]);

    // Password result
    const password_result = field_renderer.renderResultFieldLine(
        "Password: ",
        manager.password_buffer[0..manager.password_len],
    );
    try center.writeCenteredLine(stdout, result_offset, password_result.buf[0..password_result.len]);

    // Confirm password result (only in register mode)
    if (manager.current_screen == .register) {
        const confirm_result = field_renderer.renderResultFieldLine(
            "Confirm:  ",
            manager.confirm_password_buffer[0..manager.confirm_password_len],
        );
        try center.writeCenteredLine(stdout, result_offset, confirm_result.buf[0..confirm_result.len]);

        // Check if passwords match
        try center.writeCenteredLine(stdout, result_offset, "║                                        ║");
        const passwords_match = std.mem.eql(
            u8,
            manager.password_buffer[0..manager.password_len],
            manager.confirm_password_buffer[0..manager.confirm_password_len],
        );
        if (passwords_match) {
            try center.writeCenteredLine(stdout, result_offset, "║  Status: ✓ Passwords match            ║");
        } else {
            try center.writeCenteredLine(stdout, result_offset, "║  Status: ✗ Passwords don't match      ║");
        }
    }

    try center.writeCenteredLine(stdout, result_offset, "║                                        ║");
    try center.writeCenteredLine(stdout, result_offset, "╚════════════════════════════════════════╝");
    try stdout.flush();
}