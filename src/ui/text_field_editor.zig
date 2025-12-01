const std = @import("std");

/// A reusable text field editor that handles cursor-based text editing.
pub const TextFieldEditor = struct {
    buffer: []u8,
    len: *usize,
    cursor: *usize,
    max_len: usize,

    /// Insert a character at the current cursor position.
    /// Shifts existing characters to the right to make room.
    pub fn insert(self: *const TextFieldEditor, byte: u8) void {
        if (self.len.* >= self.max_len) return;

        // Shift characters right to make room
        var j: usize = self.len.*;
        while (j > self.cursor.*) : (j -= 1) {
            self.buffer[j] = self.buffer[j - 1];
        }
        self.buffer[self.cursor.*] = byte;
        self.len.* += 1;
        self.cursor.* += 1;
    }

    /// Delete the character before the cursor (backspace).
    /// Shifts remaining characters left to fill the gap.
    pub fn delete(self: *const TextFieldEditor) void {
        if (self.cursor.* == 0) return;

        // Shift characters left to fill gap
        var j: usize = self.cursor.*;
        while (j < self.len.*) : (j += 1) {
            self.buffer[j - 1] = self.buffer[j];
        }
        self.len.* -= 1;
        self.cursor.* -= 1;
    }

    /// Move cursor one position to the left.
    pub fn moveCursorLeft(self: *const TextFieldEditor) void {
        if (self.cursor.* > 0) {
            self.cursor.* -= 1;
        }
    }

    /// Move cursor one position to the right.
    pub fn moveCursorRight(self: *const TextFieldEditor) void {
        if (self.cursor.* < self.len.*) {
            self.cursor.* += 1;
        }
    }
};