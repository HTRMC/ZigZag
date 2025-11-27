const std = @import("std");

const Field = enum {
    username,
    password,
};

fn clearScreen() void {
    if (@import("builtin").os.tag == .windows) {
        const win = std.os.windows;
        const stdout_handle = std.fs.File.stdout().handle;

        // Get console screen buffer info
        var csbi: win.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (win.kernel32.GetConsoleScreenBufferInfo(stdout_handle, &csbi) != 0) {
            const console_size: u32 = @intCast(csbi.dwSize.X * csbi.dwSize.Y);
            var written: u32 = undefined;
            const coord = win.COORD{ .X = 0, .Y = 0 };

            // Fill console with spaces (use W version for Unicode)
            _ = win.kernel32.FillConsoleOutputCharacterW(stdout_handle, ' ', console_size, coord, &written);
            // Reset attributes
            _ = win.kernel32.FillConsoleOutputAttribute(stdout_handle, csbi.wAttributes, console_size, coord, &written);
            // Move cursor to top-left
            _ = win.kernel32.SetConsoleCursorPosition(stdout_handle, coord);
        }
    }
}

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

    // Buffers to store username and password
    var username_buffer: [256]u8 = undefined;
    var password_buffer: [256]u8 = undefined;
    var username_len: usize = 0;
    var password_len: usize = 0;
    var username_cursor: usize = 0;
    var password_cursor: usize = 0;

    var current_field: Field = .username;
    var done = false;

    // Enable UTF-8 output on Windows
    const is_windows = @import("builtin").os.tag == .windows;
    var original_input_mode: u32 = undefined;
    var original_output_cp: u32 = undefined;
    var raw_mode_enabled = false;

    if (is_windows) {
        const win = std.os.windows;
        const stdin_handle = std.fs.File.stdin().handle;
        const stdout_handle = std.fs.File.stdout().handle;

        // Save and set console output code page to UTF-8
        original_output_cp = win.kernel32.GetConsoleOutputCP();
        _ = win.kernel32.SetConsoleOutputCP(65001); // UTF-8

        // Enable virtual terminal processing for ANSI escape codes
        var out_mode: u32 = undefined;
        if (win.kernel32.GetConsoleMode(stdout_handle, &out_mode) != 0) {
            const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;
            _ = win.kernel32.SetConsoleMode(stdout_handle, out_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        }

        // Get current console mode for stdin
        if (win.kernel32.GetConsoleMode(stdin_handle, &original_input_mode) != 0) {
            // Configure for raw mode with Virtual Terminal Input
            const ENABLE_LINE_INPUT: u32 = 0x0002;
            const ENABLE_ECHO_INPUT: u32 = 0x0004;
            const ENABLE_VIRTUAL_TERMINAL_INPUT: u32 = 0x0200;

            // Disable line and echo, but keep processed input and enable VT input
            const new_mode = (original_input_mode & ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT)) | ENABLE_VIRTUAL_TERMINAL_INPUT;

            if (win.kernel32.SetConsoleMode(stdin_handle, new_mode) != 0) {
                raw_mode_enabled = true;
            }
        }
    }

    // Clear screen and hide cursor
    clearScreen();
    try stdout.writeAll("\x1b[?25l");
    try stdout.flush();

    defer {
        // Restore console settings on Windows
        if (is_windows) {
            const win = std.os.windows;
            // Restore code page
            _ = win.kernel32.SetConsoleOutputCP(original_output_cp);
            // Restore input mode
            if (raw_mode_enabled) {
                const stdin_handle = std.fs.File.stdin().handle;
                _ = win.kernel32.SetConsoleMode(stdin_handle, original_input_mode);
            }
        }
        // Show cursor
        stdout.writeAll("\x1b[?25h") catch {};
        stdout.flush() catch {};
    }

    while (!done) {
        // Clear and redraw UI
        clearScreen();
        try stdout.writeAll("╔════════════════════════════════════════╗\n");
        try stdout.writeAll("║          Login Form (ZigZag)           ║\n");
        try stdout.writeAll("╠════════════════════════════════════════╣\n");
        try stdout.writeAll("║                                        ║\n");

        // Username field
        if (current_field == .username) {
            try stdout.writeAll("║ ► Username: ");
        } else {
            try stdout.writeAll("║   Username: ");
        }
        const display_username_len = @min(username_len, 25);
        try stdout.writeAll(username_buffer[0..display_username_len]);
        // Pad to align the box (27 = max_len + 2 for safety)
        const username_padding = if (username_len < 27) 27 - username_len else 0;
        var i: usize = 0;
        while (i < username_padding) : (i += 1) {
            try stdout.writeAll(" ");
        }
        try stdout.writeAll("║\n");

        try stdout.writeAll("║                                        ║\n");

        // Password field
        if (current_field == .password) {
            try stdout.writeAll("║ ► Password: ");
        } else {
            try stdout.writeAll("║   Password: ");
        }
        // Show password as asterisks
        const display_password_len = @min(password_len, 25);
        i = 0;
        while (i < display_password_len) : (i += 1) {
            try stdout.writeAll("*");
        }
        const password_padding = if (password_len < 27) 27 - password_len else 0;
        i = 0;
        while (i < password_padding) : (i += 1) {
            try stdout.writeAll(" ");
        }
        try stdout.writeAll("║\n");

        try stdout.writeAll("║                                        ║\n");
        try stdout.writeAll("╚════════════════════════════════════════╝\n");
        try stdout.writeAll("\n");
        try stdout.writeAll("↑/↓: Navigate  │  ←/→: Move cursor  │  Enter: Next/Submit  │  Esc: Exit\n");

        // Position cursor at the correct location
        if (current_field == .username) {
            const cursor_col = 14 + username_cursor; // "║ ► Username: " = 14 chars
            try stdout.print("\x1b[5;{d}H", .{cursor_col + 1}); // Row 5, column (1-indexed)
        } else {
            const cursor_col = 14 + password_cursor; // "║ ► Password: " = 14 chars
            try stdout.print("\x1b[7;{d}H", .{cursor_col + 1}); // Row 7, column (1-indexed)
        }
        // Show cursor
        try stdout.writeAll("\x1b[?25h");
        try stdout.flush();

        // Read input
        const byte = try stdin.takeByte();

        // Hide cursor while processing
        try stdout.writeAll("\x1b[?25l");
        try stdout.flush();

        // Handle escape sequences (arrow keys) and Windows scan codes
        if (byte == 0x1B) { // ESC - ANSI escape sequence
            const next = stdin.takeByte() catch {
                // Just ESC pressed - exit
                done = true;
                continue;
            };
            if (next == '[') {
                const arrow = try stdin.takeByte();
                if (arrow == 'A') { // Up arrow
                    current_field = .username;
                } else if (arrow == 'B') { // Down arrow
                    current_field = .password;
                } else if (arrow == 'D') { // Left arrow
                    if (current_field == .username and username_cursor > 0) {
                        username_cursor -= 1;
                    } else if (current_field == .password and password_cursor > 0) {
                        password_cursor -= 1;
                    }
                } else if (arrow == 'C') { // Right arrow
                    if (current_field == .username and username_cursor < username_len) {
                        username_cursor += 1;
                    } else if (current_field == .password and password_cursor < password_len) {
                        password_cursor += 1;
                    }
                }
            }
        } else if (byte == 0xE0 or byte == 0x00) { // Windows extended key scan code
            const scan = try stdin.takeByte();
            if (scan == 0x48) { // Up arrow
                current_field = .username;
            } else if (scan == 0x50) { // Down arrow
                current_field = .password;
            } else if (scan == 0x4B) { // Left arrow
                if (current_field == .username and username_cursor > 0) {
                    username_cursor -= 1;
                } else if (current_field == .password and password_cursor > 0) {
                    password_cursor -= 1;
                }
            } else if (scan == 0x4D) { // Right arrow
                if (current_field == .username and username_cursor < username_len) {
                    username_cursor += 1;
                } else if (current_field == .password and password_cursor < password_len) {
                    password_cursor += 1;
                }
            }
        } else if (byte == '\r' or byte == '\n') {
            // Enter key - move to next field or submit
            if (current_field == .username) {
                current_field = .password;
            } else {
                done = true; // Submit when on password field
            }
        } else if (byte == 127 or byte == 8) { // Backspace
            if (current_field == .username and username_cursor > 0) {
                // Shift characters left
                var j: usize = username_cursor;
                while (j < username_len) : (j += 1) {
                    username_buffer[j - 1] = username_buffer[j];
                }
                username_len -= 1;
                username_cursor -= 1;
            } else if (current_field == .password and password_cursor > 0) {
                var j: usize = password_cursor;
                while (j < password_len) : (j += 1) {
                    password_buffer[j - 1] = password_buffer[j];
                }
                password_len -= 1;
                password_cursor -= 1;
            }
        } else if (byte >= 32 and byte <= 126) { // Printable characters
            const max_input_len = 25;
            if (current_field == .username and username_len < max_input_len) {
                // Shift characters right to make room
                var j: usize = username_len;
                while (j > username_cursor) : (j -= 1) {
                    username_buffer[j] = username_buffer[j - 1];
                }
                username_buffer[username_cursor] = byte;
                username_len += 1;
                username_cursor += 1;
            } else if (current_field == .password and password_len < max_input_len) {
                var j: usize = password_len;
                while (j > password_cursor) : (j -= 1) {
                    password_buffer[j] = password_buffer[j - 1];
                }
                password_buffer[password_cursor] = byte;
                password_len += 1;
                password_cursor += 1;
            }
        }
    }

    // Clear screen and show results
    clearScreen();
    try stdout.writeAll("╔════════════════════════════════════════╗\n");
    try stdout.writeAll("║              Login Result              ║\n");
    try stdout.writeAll("╠════════════════════════════════════════╣\n");
    try stdout.writeAll("║                                        ║\n");

    // Username result
    try stdout.writeAll("║  Username: ");
    try stdout.writeAll(username_buffer[0..username_len]);
    const result_username_padding = if (username_len < 28) 28 - username_len else 0;
    var result_i: usize = 0;
    while (result_i < result_username_padding) : (result_i += 1) {
        try stdout.writeAll(" ");
    }
    try stdout.writeAll("║\n");

    // Password result
    try stdout.writeAll("║  Password: ");
    try stdout.writeAll(password_buffer[0..password_len]);
    const result_password_padding = if (password_len < 28) 28 - password_len else 0;
    result_i = 0;
    while (result_i < result_password_padding) : (result_i += 1) {
        try stdout.writeAll(" ");
    }
    try stdout.writeAll("║\n");

    try stdout.writeAll("║                                        ║\n");
    try stdout.writeAll("╚════════════════════════════════════════╝\n");
    try stdout.flush();
}
