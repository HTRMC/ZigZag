const std = @import("std");
const types = @import("types.zig");
const center = @import("../ui/center.zig");
const terminal = @import("../platform/terminal.zig");
const draw = @import("../ui/draw.zig");
const screen_manager = @import("screen_manager.zig");

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
    const result_username_padding = if (manager.username_len < 28) 28 - manager.username_len else 0;
    const username_result_line = blk: {
        var user_result_buf: [256]u8 = undefined;
        var user_result_idx: usize = 0;
        const prefix = "║  Username: ";
        @memcpy(user_result_buf[user_result_idx..][0..prefix.len], prefix);
        user_result_idx += prefix.len;
        @memcpy(user_result_buf[user_result_idx..][0..manager.username_len], manager.username_buffer[0..manager.username_len]);
        user_result_idx += manager.username_len;
        var i: usize = 0;
        while (i < result_username_padding) : (i += 1) {
            user_result_buf[user_result_idx] = ' ';
            user_result_idx += 1;
        }
        const suffix = "║";
        @memcpy(user_result_buf[user_result_idx..][0..suffix.len], suffix);
        user_result_idx += suffix.len;
        break :blk user_result_buf[0..user_result_idx];
    };
    try center.writeCenteredLine(stdout, result_offset, username_result_line);

    // Password result
    const result_password_padding = if (manager.password_len < 28) 28 - manager.password_len else 0;
    const password_result_line = blk: {
        var pwd_result_buf: [256]u8 = undefined;
        var pwd_result_idx: usize = 0;
        const prefix = "║  Password: ";
        @memcpy(pwd_result_buf[pwd_result_idx..][0..prefix.len], prefix);
        pwd_result_idx += prefix.len;
        @memcpy(pwd_result_buf[pwd_result_idx..][0..manager.password_len], manager.password_buffer[0..manager.password_len]);
        pwd_result_idx += manager.password_len;
        var i: usize = 0;
        while (i < result_password_padding) : (i += 1) {
            pwd_result_buf[pwd_result_idx] = ' ';
            pwd_result_idx += 1;
        }
        const suffix = "║";
        @memcpy(pwd_result_buf[pwd_result_idx..][0..suffix.len], suffix);
        pwd_result_idx += suffix.len;
        break :blk pwd_result_buf[0..pwd_result_idx];
    };
    try center.writeCenteredLine(stdout, result_offset, password_result_line);

    // Confirm password result (only in register mode)
    if (manager.current_screen == .register) {
        const result_confirm_padding = if (manager.confirm_password_len < 28) 28 - manager.confirm_password_len else 0;
        const confirm_result_line = blk: {
            var conf_result_buf: [256]u8 = undefined;
            var conf_result_idx: usize = 0;
            const prefix = "║  Confirm:  ";
            @memcpy(conf_result_buf[conf_result_idx..][0..prefix.len], prefix);
            conf_result_idx += prefix.len;
            @memcpy(conf_result_buf[conf_result_idx..][0..manager.confirm_password_len], manager.confirm_password_buffer[0..manager.confirm_password_len]);
            conf_result_idx += manager.confirm_password_len;
            var i: usize = 0;
            while (i < result_confirm_padding) : (i += 1) {
                conf_result_buf[conf_result_idx] = ' ';
                conf_result_idx += 1;
            }
            const suffix = "║";
            @memcpy(conf_result_buf[conf_result_idx..][0..suffix.len], suffix);
            conf_result_idx += suffix.len;
            break :blk conf_result_buf[0..conf_result_idx];
        };
        try center.writeCenteredLine(stdout, result_offset, confirm_result_line);

        // Check if passwords match
        try center.writeCenteredLine(stdout, result_offset, "║                                        ║");
        const passwords_match = std.mem.eql(u8, manager.password_buffer[0..manager.password_len], manager.confirm_password_buffer[0..manager.confirm_password_len]);
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