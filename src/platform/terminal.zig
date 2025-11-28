const std = @import("std");

pub const TerminalSize = struct {
    width: u16,
    height: u16,
};

pub fn getTerminalSize() TerminalSize {
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

pub fn clearScreen() void {
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
