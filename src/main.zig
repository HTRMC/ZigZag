const std = @import("std");
const windows_io = @import("platform/windows_io.zig");
const application = @import("application.zig");
const draw = @import("ui/draw.zig");

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    // Create I/O system
    var io_threaded = std.Io.Threaded.init(gpa);
    defer io_threaded.deinit();
    const io = io_threaded.io();

    // Create I/O buffers
    var stdout_buffer: [4096]u8 = undefined;
    var stdin_buffer: [4096]u8 = undefined;

    // Get reader and writer
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stdin_reader = std.fs.File.stdin().reader(io, &stdin_buffer);

    const stdout = &stdout_writer.interface;
    const stdin = &stdin_reader.interface;

    // Platform-specific setup
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

    defer {
        // Cleanup
        if (is_windows) {
            windows_io.restoreWindowsConsole(original_input_mode, original_output_cp, raw_mode_enabled);
        }
        draw.showCursor(stdout) catch {};
        stdout.flush() catch {};
    }

    // Run the application
    try application.run(stdout, stdin);
}