const std = @import("std");
const terminal = @import("platform/terminal.zig");
const windows_io = @import("platform/windows_io.zig");
const screen_manager = @import("screens/screen_manager.zig");
const login_screen = @import("screens/login_screen.zig");
const register_screen = @import("screens/register_screen.zig");
const result_screen = @import("screens/result_screen.zig");
const center = @import("ui/center.zig");
const draw = @import("ui/draw.zig");

pub fn run(stdout: anytype, stdin: anytype) !void {
    // Initialize screen manager
    var manager = screen_manager.ScreenManager.init();

    // Track cursor visibility to reduce flicker
    var cursor_visible: bool = false;

    // Clear screen and hide cursor
    terminal.clearScreen();
    try draw.hideCursor(stdout);
    cursor_visible = false;
    try stdout.flush();

    // Main render loop
    while (!manager.done) {
        // Clear and redraw UI
        terminal.clearScreen();

        // Get terminal size and calculate center offset
        const term_size = terminal.getTerminalSize();
        const ui_width: u16 = 42; // Box is 42 characters wide
        const ui_height: u16 = if (manager.current_screen == .login) 16 else 18;
        const offset = center.calculateCenterOffset(term_size, ui_width, ui_height);

        // Move cursor to starting position
        try draw.moveCursor(stdout, offset.row + 1, 1);

        // Render current screen
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

    // Show result screen
    try result_screen.render(stdout, &manager);
}