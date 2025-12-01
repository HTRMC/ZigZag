const std = @import("std");

// Windows Ctrl+C handler setup
const BOOL = i32;
const WINAPI = std.builtin.CallingConvention.winapi;
const PHANDLER_ROUTINE = ?*const fn (u32) callconv(WINAPI) BOOL;

extern "kernel32" fn SetConsoleCtrlHandler(
    HandlerRoutine: PHANDLER_ROUTINE,
    Add: BOOL,
) callconv(WINAPI) BOOL;

pub extern "kernel32" fn WriteConsoleA(
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

extern "kernel32" fn WaitForSingleObject(
    hHandle: std.os.windows.HANDLE,
    dwMilliseconds: u32,
) callconv(WINAPI) u32;

const WAIT_OBJECT_0: u32 = 0;
const WAIT_TIMEOUT: u32 = 258;

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

/// Result of readInputWithTimeout
pub const InputResult = enum {
    timeout, // No input within timeout period
    resize, // Window was resized
    input, // Got input byte
};

/// Read input with a timeout (Windows only feature, others block)
/// Returns timeout if no input within timeout_ms milliseconds
pub fn readInputWithTimeout(timeout_ms: u32) struct { result: InputResult, byte: u8 } {
    const is_windows = @import("builtin").os.tag == .windows;

    if (is_windows) {
        const stdin_handle = std.fs.File.stdin().handle;

        // Wait for input with timeout
        const wait_result = WaitForSingleObject(stdin_handle, timeout_ms);

        if (wait_result == WAIT_TIMEOUT) {
            return .{ .result = .timeout, .byte = 0 };
        }

        if (wait_result != WAIT_OBJECT_0) {
            return .{ .result = .timeout, .byte = 0 };
        }

        // Input is available, read it
        var input_rec: INPUT_RECORD = undefined;
        var events_read: u32 = 0;

        while (true) {
            if (ReadConsoleInputA(stdin_handle, @ptrCast(&input_rec), 1, &events_read) == 0) {
                return .{ .result = .timeout, .byte = 0 };
            }

            if (events_read == 0) continue;

            if (input_rec.EventType == WINDOW_BUFFER_SIZE_EVENT) {
                return .{ .result = .resize, .byte = 0 };
            } else if (input_rec.EventType == KEY_EVENT) {
                const key_event = input_rec.Event.KeyEvent;
                if (key_event.bKeyDown != 0) {
                    return .{ .result = .input, .byte = key_event.uChar.AsciiChar };
                }
            }
            // For other events, check if more input is available
            var peek_rec: INPUT_RECORD = undefined;
            var peek_count: u32 = 0;
            if (PeekConsoleInputA(stdin_handle, @ptrCast(&peek_rec), 1, &peek_count) == 0 or peek_count == 0) {
                return .{ .result = .timeout, .byte = 0 };
            }
        }
    } else {
        // Non-Windows: no timeout support, just return timeout
        return .{ .result = .timeout, .byte = 0 };
    }
}

// Read input and handle window resize events
// Returns: null if window was resized (need to redraw), otherwise the input byte
pub fn readInputOrResize(stdin: anytype) !?u8 {
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

pub fn setupWindowsConsole() !struct {
    original_input_mode: u32,
    original_output_cp: u32,
    raw_mode_enabled: bool,
} {
    const win = std.os.windows;
    const stdin_handle = std.fs.File.stdin().handle;
    const stdout_handle = std.fs.File.stdout().handle;

    var original_input_mode: u32 = undefined;
    const original_output_cp = win.kernel32.GetConsoleOutputCP();

    // Set console output code page to UTF-8
    _ = win.kernel32.SetConsoleOutputCP(65001); // UTF-8

    // Enable virtual terminal processing for ANSI escape codes
    var out_mode: u32 = undefined;
    if (win.kernel32.GetConsoleMode(stdout_handle, &out_mode) != 0) {
        const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;
        _ = win.kernel32.SetConsoleMode(stdout_handle, out_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    }

    // Get current console mode for stdin
    var raw_mode_enabled = false;
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

    return .{
        .original_input_mode = original_input_mode,
        .original_output_cp = original_output_cp,
        .raw_mode_enabled = raw_mode_enabled,
    };
}

pub fn restoreWindowsConsole(original_input_mode: u32, original_output_cp: u32, raw_mode_enabled: bool) void {
    const win = std.os.windows;
    // Restore code page
    _ = win.kernel32.SetConsoleOutputCP(original_output_cp);
    // Restore input mode
    if (raw_mode_enabled) {
        const stdin_handle = std.fs.File.stdin().handle;
        _ = win.kernel32.SetConsoleMode(stdin_handle, original_input_mode);
    }
}