const std = @import("std");

const Screen = enum {
    login,
    register,
};

const LoginField = enum {
    username,
    password,
    forgot_password,
    register,
};

const RegisterField = enum {
    username,
    password,
    confirm_password,
    create_account,
    back_to_login,
};

// Windows Ctrl+C handler setup
const BOOL = i32;
const WINAPI = std.builtin.CallingConvention.winapi;
const PHANDLER_ROUTINE = ?*const fn (u32) callconv(WINAPI) BOOL;

extern "kernel32" fn SetConsoleCtrlHandler(
    HandlerRoutine: PHANDLER_ROUTINE,
    Add: BOOL,
) callconv(WINAPI) BOOL;

extern "kernel32" fn WriteConsoleA(
    hConsoleOutput: std.os.windows.HANDLE,
    lpBuffer: [*]const u8,
    nNumberOfCharsToWrite: u32,
    lpNumberOfCharsWritten: *u32,
    lpReserved: ?*anyopaque,
) callconv(WINAPI) BOOL;

// Windows console input event structures
const KEY_EVENT: u16 = 0x0001;
const WINDOW_BUFFER_SIZE_EVENT: u16 = 0x0004;

const COORD = extern struct {
    X: i16,
    Y: i16,
};

const KEY_EVENT_RECORD = extern struct {
    bKeyDown: BOOL,
    wRepeatCount: u16,
    wVirtualKeyCode: u16,
    wVirtualScanCode: u16,
    uChar: extern union {
        UnicodeChar: u16,
        AsciiChar: u8,
    },
    dwControlKeyState: u32,
};

const INPUT_RECORD = extern struct {
    EventType: u16,
    Event: extern union {
        KeyEvent: KEY_EVENT_RECORD,
        WindowBufferSizeEvent: extern struct {
            dwSize: COORD,
        },
        padding: [16]u8,
    },
};

extern "kernel32" fn PeekConsoleInputA(
    hConsoleInput: std.os.windows.HANDLE,
    lpBuffer: [*]INPUT_RECORD,
    nLength: u32,
    lpNumberOfEventsRead: *u32,
) callconv(WINAPI) BOOL;

extern "kernel32" fn ReadConsoleInputA(
    hConsoleInput: std.os.windows.HANDLE,
    lpBuffer: [*]INPUT_RECORD,
    nLength: u32,
    lpNumberOfEventsRead: *u32,
) callconv(WINAPI) BOOL;

// Global state for cleanup in signal handler
var g_original_input_mode: u32 = undefined;
var g_original_output_cp: u32 = undefined;
var g_raw_mode_enabled: bool = false;
var g_cleanup_needed: bool = false;

fn ctrlHandler(dwCtrlType: u32) callconv(WINAPI) BOOL {
    _ = dwCtrlType;

    if (g_cleanup_needed) {
        const win = std.os.windows;
        const stdin_handle = std.fs.File.stdin().handle;
        const stdout_handle = std.fs.File.stdout().handle;

        // Restore code page
        _ = win.kernel32.SetConsoleOutputCP(g_original_output_cp);

        // Restore input mode
        if (g_raw_mode_enabled) {
            _ = win.kernel32.SetConsoleMode(stdin_handle, g_original_input_mode);
        }

        // Show cursor and clear screen
        const cleanup_seq = "\x1b[?25h\x1b[2J\x1b[H";
        var written: u32 = undefined;
        _ = WriteConsoleA(stdout_handle, cleanup_seq.ptr, cleanup_seq.len, &written, null);
    }

    return 0; // Let default handler terminate the process
}

const TerminalSize = struct {
    width: u16,
    height: u16,
};

fn getTerminalSize() TerminalSize {
    if (@import("builtin").os.tag == .windows) {
        const win = std.os.windows;
        const stdout_handle = std.fs.File.stdout().handle;

        var csbi: win.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (win.kernel32.GetConsoleScreenBufferInfo(stdout_handle, &csbi) != 0) {
            // Use window size, not buffer size
            const width: u16 = @intCast(csbi.srWindow.Right - csbi.srWindow.Left + 1);
            const height: u16 = @intCast(csbi.srWindow.Bottom - csbi.srWindow.Top + 1);
            return TerminalSize{ .width = width, .height = height };
        }
    }
    // Default fallback
    return TerminalSize{ .width = 80, .height = 24 };
}

const CenterOffset = struct {
    row: u16,
    col: u16,
};

fn calculateCenterOffset(term_size: TerminalSize, ui_width: u16, ui_height: u16) CenterOffset {
    const row = if (term_size.height > ui_height) (term_size.height - ui_height) / 2 else 0;
    const col = if (term_size.width > ui_width) (term_size.width - ui_width) / 2 else 0;
    return CenterOffset{ .row = row, .col = col };
}

fn writeCenteredLine(writer: anytype, offset: CenterOffset, line: []const u8) !void {
    var i: u16 = 0;
    while (i < offset.col) : (i += 1) {
        try writer.writeAll(" ");
    }
    try writer.writeAll(line);
    try writer.writeAll("\n");
}

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

// Read input and handle window resize events
// Returns: null if window was resized (need to redraw), otherwise the input byte
fn readInputOrResize(stdin: anytype) !?u8 {
    const is_windows = @import("builtin").os.tag == .windows;

    if (is_windows) {
        const stdin_handle = std.fs.File.stdin().handle;
        var input_rec: INPUT_RECORD = undefined;
        var events_read: u32 = 0;

        while (true) {
            // Read console input event
            if (ReadConsoleInputA(stdin_handle, @ptrCast(&input_rec), 1, &events_read) == 0) {
                return error.ReadFailed;
            }

            if (events_read == 0) continue;

            // Check event type
            if (input_rec.EventType == WINDOW_BUFFER_SIZE_EVENT) {
                // Window was resized - return null to trigger redraw
                return null;
            } else if (input_rec.EventType == KEY_EVENT) {
                const key_event = input_rec.Event.KeyEvent;
                // Only process key down events
                if (key_event.bKeyDown != 0) {
                    return key_event.uChar.AsciiChar;
                }
            }
            // Ignore other event types and key-up events
        }
    } else {
        // Non-Windows: just read a byte normally
        return try stdin.takeByte();
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
    var confirm_password_buffer: [256]u8 = undefined;
    var username_len: usize = 0;
    var password_len: usize = 0;
    var confirm_password_len: usize = 0;
    var username_cursor: usize = 0;
    var password_cursor: usize = 0;
    var confirm_password_cursor: usize = 0;

    var current_screen: Screen = .login;
    var login_field: LoginField = .username;
    var register_field: RegisterField = .username;
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
            // Configure for raw mode with Virtual Terminal Input and Window Input
            const ENABLE_LINE_INPUT: u32 = 0x0002;
            const ENABLE_ECHO_INPUT: u32 = 0x0004;
            const ENABLE_VIRTUAL_TERMINAL_INPUT: u32 = 0x0200;
            const ENABLE_WINDOW_INPUT: u32 = 0x0008;

            // Disable line and echo, but keep processed input and enable VT input and window events
            const new_mode = (original_input_mode & ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT)) | ENABLE_VIRTUAL_TERMINAL_INPUT | ENABLE_WINDOW_INPUT;

            if (win.kernel32.SetConsoleMode(stdin_handle, new_mode) != 0) {
                raw_mode_enabled = true;
            }
        }

        // Register Ctrl+C handler
        g_original_input_mode = original_input_mode;
        g_original_output_cp = original_output_cp;
        g_raw_mode_enabled = raw_mode_enabled;
        _ = SetConsoleCtrlHandler(&ctrlHandler, 1);
        g_cleanup_needed = true;
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

        // Get terminal size and calculate center offset
        const term_size = getTerminalSize();
        const ui_width: u16 = 42; // Box is 42 characters wide
        const ui_height: u16 = if (current_screen == .login) 16 else 18; // Login: 14 lines + 1 blank + 1 help, Register: 16 + 1 + 1
        const offset = calculateCenterOffset(term_size, ui_width, ui_height);

        // Move cursor to starting position
        try stdout.print("\x1b[{d};1H", .{offset.row + 1});

        if (current_screen == .login) {
            // LOGIN SCREEN
            try writeCenteredLine(stdout, offset, "╔════════════════════════════════════════╗");
            try writeCenteredLine(stdout, offset, "║          Login Form (ZigZag)           ║");
            try writeCenteredLine(stdout, offset, "╠════════════════════════════════════════╣");
            try writeCenteredLine(stdout, offset, "║                                        ║");

            // Username field
            const display_username_len = @min(username_len, 25);
            const username_padding = if (username_len < 27) 27 - username_len else 0;
            const username_line = blk: {
                const prefix = if (login_field == .username) "║ ► Username: " else "║   Username: ";
                var user_buf: [256]u8 = undefined;
                var user_idx: usize = 0;
                @memcpy(user_buf[user_idx..][0..prefix.len], prefix);
                user_idx += prefix.len;
                @memcpy(user_buf[user_idx..][0..display_username_len], username_buffer[0..display_username_len]);
                user_idx += display_username_len;
                var i: usize = 0;
                while (i < username_padding) : (i += 1) {
                    user_buf[user_idx] = ' ';
                    user_idx += 1;
                }
                @memcpy(user_buf[user_idx..][0..3], "║");
                user_idx += 3;
                break :blk user_buf[0..user_idx];
            };
            try writeCenteredLine(stdout, offset, username_line);

            try writeCenteredLine(stdout, offset, "║                                        ║");

            // Password field
            const display_password_len = @min(password_len, 25);
            const password_padding = if (password_len < 27) 27 - password_len else 0;
            const password_line = blk: {
                const prefix = if (login_field == .password) "║ ► Password: " else "║   Password: ";
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
                @memcpy(pwd_buf[pwd_idx..][0..3], "║");
                pwd_idx += 3;
                break :blk pwd_buf[0..pwd_idx];
            };
            try writeCenteredLine(stdout, offset, password_line);

            try writeCenteredLine(stdout, offset, "║                                        ║");

            // Forgot password button
            if (login_field == .forgot_password) {
                try writeCenteredLine(stdout, offset, "║ ► Forgot your password?                ║");
            } else {
                try writeCenteredLine(stdout, offset, "║   Forgot your password?                ║");
            }

            try writeCenteredLine(stdout, offset, "║                                        ║");

            // Register button
            if (login_field == .register) {
                try writeCenteredLine(stdout, offset, "║ ► Need an account? Register            ║");
            } else {
                try writeCenteredLine(stdout, offset, "║   Need an account? Register            ║");
            }

            try writeCenteredLine(stdout, offset, "║                                        ║");
            try writeCenteredLine(stdout, offset, "╚════════════════════════════════════════╝");
            try writeCenteredLine(stdout, offset, "");
            try writeCenteredLine(stdout, offset, "↑/↓: Navigate  │  ←/→: Move cursor  │  Enter: Select  │  Esc: Exit");

            // Position cursor
            if (login_field == .username) {
                const cursor_col = offset.col + 14 + username_cursor;
                try stdout.print("\x1b[{d};{d}H", .{ offset.row + 5, cursor_col + 1 });
                try stdout.writeAll("\x1b[?25h");
            } else if (login_field == .password) {
                const cursor_col = offset.col + 14 + password_cursor;
                try stdout.print("\x1b[{d};{d}H", .{ offset.row + 7, cursor_col + 1 });
                try stdout.writeAll("\x1b[?25h");
            } else {
                // Hide cursor for buttons
                try stdout.writeAll("\x1b[?25l");
            }
        } else {
            // REGISTER SCREEN

            try writeCenteredLine(stdout, offset, "╔════════════════════════════════════════╗");
            try writeCenteredLine(stdout, offset, "║        Register Form (ZigZag)          ║");
            try writeCenteredLine(stdout, offset, "╠════════════════════════════════════════╣");
            try writeCenteredLine(stdout, offset, "║                                        ║");

            // Username field
            const display_username_len = @min(username_len, 25);
            const username_padding = if (username_len < 27) 27 - username_len else 0;
            const username_line = blk: {
                const prefix = if (register_field == .username) "║ ► Username: " else "║   Username: ";
                var user_buf: [256]u8 = undefined;
                var user_idx: usize = 0;
                @memcpy(user_buf[user_idx..][0..prefix.len], prefix);
                user_idx += prefix.len;
                @memcpy(user_buf[user_idx..][0..display_username_len], username_buffer[0..display_username_len]);
                user_idx += display_username_len;
                var i: usize = 0;
                while (i < username_padding) : (i += 1) {
                    user_buf[user_idx] = ' ';
                    user_idx += 1;
                }
                @memcpy(user_buf[user_idx..][0..3], "║");
                user_idx += 3;
                break :blk user_buf[0..user_idx];
            };
            try writeCenteredLine(stdout, offset, username_line);

            try writeCenteredLine(stdout, offset, "║                                        ║");

            // Password field
            const display_password_len = @min(password_len, 25);
            const password_padding = if (password_len < 27) 27 - password_len else 0;
            const password_line = blk: {
                const prefix = if (register_field == .password) "║ ► Password: " else "║   Password: ";
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
                @memcpy(pwd_buf[pwd_idx..][0..3], "║");
                pwd_idx += 3;
                break :blk pwd_buf[0..pwd_idx];
            };
            try writeCenteredLine(stdout, offset, password_line);

            try writeCenteredLine(stdout, offset, "║                                        ║");

            // Confirm Password field
            const display_confirm_len = @min(confirm_password_len, 25);
            const confirm_padding = if (confirm_password_len < 27) 27 - confirm_password_len else 0;
            const confirm_line = blk: {
                const prefix = if (register_field == .confirm_password) "║ ► Confirm:  " else "║   Confirm:  ";
                var conf_buf: [256]u8 = undefined;
                var conf_idx: usize = 0;
                @memcpy(conf_buf[conf_idx..][0..prefix.len], prefix);
                conf_idx += prefix.len;
                var i: usize = 0;
                while (i < display_confirm_len) : (i += 1) {
                    conf_buf[conf_idx] = '*';
                    conf_idx += 1;
                }
                i = 0;
                while (i < confirm_padding) : (i += 1) {
                    conf_buf[conf_idx] = ' ';
                    conf_idx += 1;
                }
                @memcpy(conf_buf[conf_idx..][0..3], "║");
                conf_idx += 3;
                break :blk conf_buf[0..conf_idx];
            };
            try writeCenteredLine(stdout, offset, confirm_line);

            try writeCenteredLine(stdout, offset, "║                                        ║");

            // Create Account button
            if (register_field == .create_account) {
                try writeCenteredLine(stdout, offset, "║ ► Create Account                       ║");
            } else {
                try writeCenteredLine(stdout, offset, "║   Create Account                       ║");
            }

            try writeCenteredLine(stdout, offset, "║                                        ║");

            // Back to Login button
            if (register_field == .back_to_login) {
                try writeCenteredLine(stdout, offset, "║ ► Already have an account? Login       ║");
            } else {
                try writeCenteredLine(stdout, offset, "║   Already have an account? Login       ║");
            }

            try writeCenteredLine(stdout, offset, "║                                        ║");
            try writeCenteredLine(stdout, offset, "╚════════════════════════════════════════╝");
            try writeCenteredLine(stdout, offset, "");
            try writeCenteredLine(stdout, offset, "↑/↓: Navigate  │  ←/→: Move cursor  │  Enter: Select  │  Esc: Exit");

            // Position cursor
            if (register_field == .username) {
                const cursor_col = offset.col + 14 + username_cursor;
                try stdout.print("\x1b[{d};{d}H", .{ offset.row + 5, cursor_col + 1 });
                try stdout.writeAll("\x1b[?25h");
            } else if (register_field == .password) {
                const cursor_col = offset.col + 14 + password_cursor;
                try stdout.print("\x1b[{d};{d}H", .{ offset.row + 7, cursor_col + 1 });
                try stdout.writeAll("\x1b[?25h");
            } else if (register_field == .confirm_password) {
                const cursor_col = offset.col + 14 + confirm_password_cursor;
                try stdout.print("\x1b[{d};{d}H", .{ offset.row + 9, cursor_col + 1 });
                try stdout.writeAll("\x1b[?25h");
            } else {
                // Hide cursor for buttons
                try stdout.writeAll("\x1b[?25l");
            }
        }

        try stdout.flush();

        // Read input or handle resize
        const maybe_byte = try readInputOrResize(stdin);
        if (maybe_byte == null) {
            // Window was resized - redraw UI by continuing the loop
            continue;
        }
        const byte = maybe_byte.?;

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
                    if (current_screen == .login) {
                        login_field = switch (login_field) {
                            .username => .username,
                            .password => .username,
                            .forgot_password => .password,
                            .register => .forgot_password,
                        };
                    } else {
                        register_field = switch (register_field) {
                            .username => .username,
                            .password => .username,
                            .confirm_password => .password,
                            .create_account => .confirm_password,
                            .back_to_login => .create_account,
                        };
                    }
                } else if (arrow == 'B') { // Down arrow
                    if (current_screen == .login) {
                        login_field = switch (login_field) {
                            .username => .password,
                            .password => .forgot_password,
                            .forgot_password => .register,
                            .register => .register,
                        };
                    } else {
                        register_field = switch (register_field) {
                            .username => .password,
                            .password => .confirm_password,
                            .confirm_password => .create_account,
                            .create_account => .back_to_login,
                            .back_to_login => .back_to_login,
                        };
                    }
                } else if (arrow == 'D') { // Left arrow
                    if (current_screen == .login) {
                        if (login_field == .username and username_cursor > 0) {
                            username_cursor -= 1;
                        } else if (login_field == .password and password_cursor > 0) {
                            password_cursor -= 1;
                        }
                    } else {
                        if (register_field == .username and username_cursor > 0) {
                            username_cursor -= 1;
                        } else if (register_field == .password and password_cursor > 0) {
                            password_cursor -= 1;
                        } else if (register_field == .confirm_password and confirm_password_cursor > 0) {
                            confirm_password_cursor -= 1;
                        }
                    }
                } else if (arrow == 'C') { // Right arrow
                    if (current_screen == .login) {
                        if (login_field == .username and username_cursor < username_len) {
                            username_cursor += 1;
                        } else if (login_field == .password and password_cursor < password_len) {
                            password_cursor += 1;
                        }
                    } else {
                        if (register_field == .username and username_cursor < username_len) {
                            username_cursor += 1;
                        } else if (register_field == .password and password_cursor < password_len) {
                            password_cursor += 1;
                        } else if (register_field == .confirm_password and confirm_password_cursor < confirm_password_len) {
                            confirm_password_cursor += 1;
                        }
                    }
                }
            }
        } else if (byte == 0xE0 or byte == 0x00) { // Windows extended key scan code
            const scan = try stdin.takeByte();
            if (scan == 0x48) { // Up arrow
                if (current_screen == .login) {
                    login_field = switch (login_field) {
                        .username => .username,
                        .password => .username,
                        .forgot_password => .password,
                        .register => .forgot_password,
                    };
                } else {
                    register_field = switch (register_field) {
                        .username => .username,
                        .password => .username,
                        .confirm_password => .password,
                        .create_account => .confirm_password,
                        .back_to_login => .create_account,
                    };
                }
            } else if (scan == 0x50) { // Down arrow
                if (current_screen == .login) {
                    login_field = switch (login_field) {
                        .username => .password,
                        .password => .forgot_password,
                        .forgot_password => .register,
                        .register => .register,
                    };
                } else {
                    register_field = switch (register_field) {
                        .username => .password,
                        .password => .confirm_password,
                        .confirm_password => .create_account,
                        .create_account => .back_to_login,
                        .back_to_login => .back_to_login,
                    };
                }
            } else if (scan == 0x4B) { // Left arrow
                if (current_screen == .login) {
                    if (login_field == .username and username_cursor > 0) {
                        username_cursor -= 1;
                    } else if (login_field == .password and password_cursor > 0) {
                        password_cursor -= 1;
                    }
                } else {
                    if (register_field == .username and username_cursor > 0) {
                        username_cursor -= 1;
                    } else if (register_field == .password and password_cursor > 0) {
                        password_cursor -= 1;
                    } else if (register_field == .confirm_password and confirm_password_cursor > 0) {
                        confirm_password_cursor -= 1;
                    }
                }
            } else if (scan == 0x4D) { // Right arrow
                if (current_screen == .login) {
                    if (login_field == .username and username_cursor < username_len) {
                        username_cursor += 1;
                    } else if (login_field == .password and password_cursor < password_len) {
                        password_cursor += 1;
                    }
                } else {
                    if (register_field == .username and username_cursor < username_len) {
                        username_cursor += 1;
                    } else if (register_field == .password and password_cursor < password_len) {
                        password_cursor += 1;
                    } else if (register_field == .confirm_password and confirm_password_cursor < confirm_password_len) {
                        confirm_password_cursor += 1;
                    }
                }
            }
        } else if (byte == '\r' or byte == '\n') {
            // Enter key - select button or submit
            if (current_screen == .login) {
                if (login_field == .username) {
                    login_field = .password;
                } else if (login_field == .password) {
                    // Submit login
                    done = true;
                } else if (login_field == .forgot_password) {
                    // TODO: Handle forgot password
                    done = true;
                } else if (login_field == .register) {
                    // Switch to register screen
                    current_screen = .register;
                    register_field = .username;
                }
            } else {
                if (register_field == .username) {
                    register_field = .password;
                } else if (register_field == .password) {
                    register_field = .confirm_password;
                } else if (register_field == .confirm_password) {
                    register_field = .create_account;
                } else if (register_field == .create_account) {
                    // Submit registration
                    done = true;
                } else if (register_field == .back_to_login) {
                    // Switch back to login screen
                    current_screen = .login;
                    login_field = .username;
                    // Reset register fields
                    confirm_password_len = 0;
                    confirm_password_cursor = 0;
                }
            }
        } else if (byte == 127 or byte == 8) { // Backspace
            if (current_screen == .login) {
                if (login_field == .username and username_cursor > 0) {
                    var j: usize = username_cursor;
                    while (j < username_len) : (j += 1) {
                        username_buffer[j - 1] = username_buffer[j];
                    }
                    username_len -= 1;
                    username_cursor -= 1;
                } else if (login_field == .password and password_cursor > 0) {
                    var j: usize = password_cursor;
                    while (j < password_len) : (j += 1) {
                        password_buffer[j - 1] = password_buffer[j];
                    }
                    password_len -= 1;
                    password_cursor -= 1;
                }
            } else {
                if (register_field == .username and username_cursor > 0) {
                    var j: usize = username_cursor;
                    while (j < username_len) : (j += 1) {
                        username_buffer[j - 1] = username_buffer[j];
                    }
                    username_len -= 1;
                    username_cursor -= 1;
                } else if (register_field == .password and password_cursor > 0) {
                    var j: usize = password_cursor;
                    while (j < password_len) : (j += 1) {
                        password_buffer[j - 1] = password_buffer[j];
                    }
                    password_len -= 1;
                    password_cursor -= 1;
                } else if (register_field == .confirm_password and confirm_password_cursor > 0) {
                    var j: usize = confirm_password_cursor;
                    while (j < confirm_password_len) : (j += 1) {
                        confirm_password_buffer[j - 1] = confirm_password_buffer[j];
                    }
                    confirm_password_len -= 1;
                    confirm_password_cursor -= 1;
                }
            }
        } else if (byte >= 32 and byte <= 126) { // Printable characters
            const max_input_len = 25;
            if (current_screen == .login) {
                if (login_field == .username and username_len < max_input_len) {
                    var j: usize = username_len;
                    while (j > username_cursor) : (j -= 1) {
                        username_buffer[j] = username_buffer[j - 1];
                    }
                    username_buffer[username_cursor] = byte;
                    username_len += 1;
                    username_cursor += 1;
                } else if (login_field == .password and password_len < max_input_len) {
                    var j: usize = password_len;
                    while (j > password_cursor) : (j -= 1) {
                        password_buffer[j] = password_buffer[j - 1];
                    }
                    password_buffer[password_cursor] = byte;
                    password_len += 1;
                    password_cursor += 1;
                }
            } else {
                if (register_field == .username and username_len < max_input_len) {
                    var j: usize = username_len;
                    while (j > username_cursor) : (j -= 1) {
                        username_buffer[j] = username_buffer[j - 1];
                    }
                    username_buffer[username_cursor] = byte;
                    username_len += 1;
                    username_cursor += 1;
                } else if (register_field == .password and password_len < max_input_len) {
                    var j: usize = password_len;
                    while (j > password_cursor) : (j -= 1) {
                        password_buffer[j] = password_buffer[j - 1];
                    }
                    password_buffer[password_cursor] = byte;
                    password_len += 1;
                    password_cursor += 1;
                } else if (register_field == .confirm_password and confirm_password_len < max_input_len) {
                    var j: usize = confirm_password_len;
                    while (j > confirm_password_cursor) : (j -= 1) {
                        confirm_password_buffer[j] = confirm_password_buffer[j - 1];
                    }
                    confirm_password_buffer[confirm_password_cursor] = byte;
                    confirm_password_len += 1;
                    confirm_password_cursor += 1;
                }
            }
        }
    }

    // Clear screen and show results
    clearScreen();

    // Calculate center offset for result screen
    const term_size = getTerminalSize();
    const result_ui_width: u16 = 42; // Box is 42 characters wide
    const result_ui_height: u16 = if (current_screen == .login) 8 else 10; // Login: 8 lines, Register: 10 lines
    const result_offset = calculateCenterOffset(term_size, result_ui_width, result_ui_height);

    // Move cursor to starting position
    try stdout.print("\x1b[{d};1H", .{result_offset.row + 1});

    try writeCenteredLine(stdout, result_offset, "╔════════════════════════════════════════╗");

    if (current_screen == .login) {
        try writeCenteredLine(stdout, result_offset, "║              Login Result              ║");
    } else {
        try writeCenteredLine(stdout, result_offset, "║           Registration Result          ║");
    }

    try writeCenteredLine(stdout, result_offset, "╠════════════════════════════════════════╣");
    try writeCenteredLine(stdout, result_offset, "║                                        ║");

    // Username result
    const result_username_padding = if (username_len < 28) 28 - username_len else 0;
    const username_result_line = blk: {
        var user_result_buf: [256]u8 = undefined;
        var user_result_idx: usize = 0;
        const prefix = "║  Username: ";
        @memcpy(user_result_buf[user_result_idx..][0..prefix.len], prefix);
        user_result_idx += prefix.len;
        @memcpy(user_result_buf[user_result_idx..][0..username_len], username_buffer[0..username_len]);
        user_result_idx += username_len;
        var i: usize = 0;
        while (i < result_username_padding) : (i += 1) {
            user_result_buf[user_result_idx] = ' ';
            user_result_idx += 1;
        }
        @memcpy(user_result_buf[user_result_idx..][0..3], "║");
        user_result_idx += 3;
        break :blk user_result_buf[0..user_result_idx];
    };
    try writeCenteredLine(stdout, result_offset, username_result_line);

    // Password result
    const result_password_padding = if (password_len < 28) 28 - password_len else 0;
    const password_result_line = blk: {
        var pwd_result_buf: [256]u8 = undefined;
        var pwd_result_idx: usize = 0;
        const prefix = "║  Password: ";
        @memcpy(pwd_result_buf[pwd_result_idx..][0..prefix.len], prefix);
        pwd_result_idx += prefix.len;
        @memcpy(pwd_result_buf[pwd_result_idx..][0..password_len], password_buffer[0..password_len]);
        pwd_result_idx += password_len;
        var i: usize = 0;
        while (i < result_password_padding) : (i += 1) {
            pwd_result_buf[pwd_result_idx] = ' ';
            pwd_result_idx += 1;
        }
        @memcpy(pwd_result_buf[pwd_result_idx..][0..3], "║");
        pwd_result_idx += 3;
        break :blk pwd_result_buf[0..pwd_result_idx];
    };
    try writeCenteredLine(stdout, result_offset, password_result_line);

    // Confirm password result (only in register mode)
    if (current_screen == .register) {
        const result_confirm_padding = if (confirm_password_len < 28) 28 - confirm_password_len else 0;
        const confirm_result_line = blk: {
            var conf_result_buf: [256]u8 = undefined;
            var conf_result_idx: usize = 0;
            const prefix = "║  Confirm:  ";
            @memcpy(conf_result_buf[conf_result_idx..][0..prefix.len], prefix);
            conf_result_idx += prefix.len;
            @memcpy(conf_result_buf[conf_result_idx..][0..confirm_password_len], confirm_password_buffer[0..confirm_password_len]);
            conf_result_idx += confirm_password_len;
            var i: usize = 0;
            while (i < result_confirm_padding) : (i += 1) {
                conf_result_buf[conf_result_idx] = ' ';
                conf_result_idx += 1;
            }
            @memcpy(conf_result_buf[conf_result_idx..][0..3], "║");
            conf_result_idx += 3;
            break :blk conf_result_buf[0..conf_result_idx];
        };
        try writeCenteredLine(stdout, result_offset, confirm_result_line);

        // Check if passwords match
        try writeCenteredLine(stdout, result_offset, "║                                        ║");
        const passwords_match = std.mem.eql(u8, password_buffer[0..password_len], confirm_password_buffer[0..confirm_password_len]);
        if (passwords_match) {
            try writeCenteredLine(stdout, result_offset, "║  Status: ✓ Passwords match            ║");
        } else {
            try writeCenteredLine(stdout, result_offset, "║  Status: ✗ Passwords don't match      ║");
        }
    }

    try writeCenteredLine(stdout, result_offset, "║                                        ║");
    try writeCenteredLine(stdout, result_offset, "╚════════════════════════════════════════╝");
    try stdout.flush();
}