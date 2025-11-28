const std = @import("std");
const terminal = @import("platform/terminal.zig");
const windows_io = @import("platform/windows_io.zig");
const types = @import("screens/types.zig");
const screen_manager = @import("screens/screen_manager.zig");
const login_screen = @import("screens/login_screen.zig");
const register_screen = @import("screens/register_screen.zig");
const center = @import("ui/center.zig");
const draw = @import("ui/draw.zig");

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    // Create Io instance for the new I/O system
    var io_threaded = std.Io.Threaded.init(gpa);
    defer io_threaded.deinit();
    const io = io_threaded.io();

    // Create I/O buffers for the new buffered I/O system
    var stdout_buffer: [4096]u8 = undefined;
    var stdin_buffer: [4096]u8 = undefined;

    // Get reader and writer with io and buffers
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stdin_reader = std.fs.File.stdin().reader(io, &stdin_buffer);

    // Access the interfaces
    const stdout = &stdout_writer.interface;
    const stdin = &stdin_reader.interface;

    // Initialize screen manager
    var manager = screen_manager.ScreenManager.init();

    // Track whether we've already asked the terminal to show the cursor.
    // This prevents redundant show/hide sequences each redraw (reduces flicker).
    var cursor_visible: bool = false;

    // Enable UTF-8 output on Windows
    const is_windows = @import("builtin").os.tag == .windows;
    var original_input_mode: u32 = undefined;
    var original_output_cp: u32 = undefined;
    var raw_mode_enabled = false;

    if (is_windows) {
        const setup_result = try windows_io.setupWindowsConsole();
        original_input_mode = setup_result.original_input_mode;
        original_output_cp = setup_result.original_output_cp;
        raw_mode_enabled = setup_result.raw_mode_enabled;
    }

    // Clear screen and hide cursor
    terminal.clearScreen();
    try draw.hideCursor(stdout);
    cursor_visible = false;
    try stdout.flush();

    defer {
        // Restore console settings on Windows
        if (is_windows) {
            windows_io.restoreWindowsConsole(original_input_mode, original_output_cp, raw_mode_enabled);
        }
        // Show cursor
        // Always try to show the cursor on exit (regardless of cursor_visible).
        draw.showCursor(stdout) catch {};
        stdout.flush() catch {};
    }

    while (!manager.done) {
        // Clear and redraw UI
        terminal.clearScreen();

        // Get terminal size and calculate center offset
        const term_size = terminal.getTerminalSize();
        const ui_width: u16 = 42; // Box is 42 characters wide
        const ui_height: u16 = if (manager.current_screen == .login) 16 else 18; // Login: 14 lines + 1 blank + 1 help, Register: 16 + 1 + 1
        const offset = center.calculateCenterOffset(term_size, ui_width, ui_height);

        // Move cursor to starting position
        try draw.moveCursor(stdout, offset.row + 1, 1);

        if (manager.current_screen == .login) {
            const login_state = login_screen.LoginScreenState{
                .username_buffer = manager.username_buffer[0..manager.username_len],
                .password_buffer = manager.password_buffer[0..manager.password_len],
                .field = manager.login_field,
                .username_cursor = manager.username_cursor,
                .password_cursor = manager.password_cursor,
            };
            try login_screen.render(stdout, offset, login_state, &cursor_visible);
        } else {
            const register_state = register_screen.RegisterScreenState{
                .username_buffer = manager.username_buffer[0..manager.username_len],
                .password_buffer = manager.password_buffer[0..manager.password_len],
                .confirm_password_buffer = manager.confirm_password_buffer[0..manager.confirm_password_len],
                .field = manager.register_field,
                .username_cursor = manager.username_cursor,
                .password_cursor = manager.password_cursor,
                .confirm_password_cursor = manager.confirm_password_cursor,
            };
            try register_screen.render(stdout, offset, register_state, &cursor_visible);
        }

        try stdout.flush();

        // Read input or handle resize
        const maybe_byte = try windows_io.readInputOrResize(stdin);
        if (maybe_byte == null) {
            // Window was resized - redraw UI by continuing the loop
            continue;
        }
        const byte = maybe_byte.?;

        // Handle input through screen manager
        try manager.handleInput(byte, stdin);
    }

    // Clear screen and show results
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
        @memcpy(user_result_buf[user_result_idx..][0..3], "║");
        user_result_idx += 3;
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
        @memcpy(pwd_result_buf[pwd_result_idx..][0..3], "║");
        pwd_result_idx += 3;
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
            @memcpy(conf_result_buf[conf_result_idx..][0..3], "║");
            conf_result_idx += 3;
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