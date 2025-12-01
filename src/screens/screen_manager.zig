const std = @import("std");
const types = @import("types.zig");
const TextFieldEditor = @import("../ui/text_field_editor.zig").TextFieldEditor;

pub const ScreenManager = struct {
    current_screen: types.Screen,
    login_field: types.LoginField,
    register_field: types.RegisterField,
    username_buffer: [256]u8,
    password_buffer: [256]u8,
    confirm_password_buffer: [256]u8,
    username_len: usize,
    password_len: usize,
    confirm_password_len: usize,
    username_cursor: usize,
    password_cursor: usize,
    confirm_password_cursor: usize,
    done: bool,

    pub fn init() ScreenManager {
        return ScreenManager{
            .current_screen = .login,
            .login_field = .username,
            .register_field = .username,
            .username_buffer = undefined,
            .password_buffer = undefined,
            .confirm_password_buffer = undefined,
            .username_len = 0,
            .password_len = 0,
            .confirm_password_len = 0,
            .username_cursor = 0,
            .password_cursor = 0,
            .confirm_password_cursor = 0,
            .done = false,
        };
    }

    pub fn handleInput(self: *ScreenManager, byte: u8, stdin: anytype) !void {
        // Handle escape sequences (arrow keys) and Windows scan codes
        if (byte == 0x1B) { // ESC - ANSI escape sequence
            const next = stdin.takeByte() catch {
                // Just ESC pressed - exit
                self.done = true;
                return;
            };
            if (next == '[') {
                const arrow = try stdin.takeByte();
                if (arrow == 'A') { // Up arrow
                    self.handleUpArrow();
                } else if (arrow == 'B') { // Down arrow
                    self.handleDownArrow();
                } else if (arrow == 'D') { // Left arrow
                    self.handleLeftArrow();
                } else if (arrow == 'C') { // Right arrow
                    self.handleRightArrow();
                }
            }
        } else if (byte == 0xE0 or byte == 0x00) { // Windows extended key scan code
            const scan = try stdin.takeByte();
            if (scan == 0x48) { // Up arrow
                self.handleUpArrow();
            } else if (scan == 0x50) { // Down arrow
                self.handleDownArrow();
            } else if (scan == 0x4B) { // Left arrow
                self.handleLeftArrow();
            } else if (scan == 0x4D) { // Right arrow
                self.handleRightArrow();
            }
        } else if (byte == '\r' or byte == '\n') {
            self.handleEnter();
        } else if (byte == 127 or byte == 8) { // Backspace
            self.handleBackspace();
        } else if (byte >= 32 and byte <= 126) { // Printable characters
            self.handlePrintableChar(byte);
        }
    }

    fn handleUpArrow(self: *ScreenManager) void {
        if (self.current_screen == .login) {
            self.login_field = switch (self.login_field) {
                .username => .username,
                .password => .username,
                .forgot_password => .password,
                .register => .forgot_password,
            };
        } else {
            self.register_field = switch (self.register_field) {
                .username => .username,
                .password => .username,
                .confirm_password => .password,
                .create_account => .confirm_password,
                .back_to_login => .create_account,
            };
        }
    }

    fn handleDownArrow(self: *ScreenManager) void {
        if (self.current_screen == .login) {
            self.login_field = switch (self.login_field) {
                .username => .password,
                .password => .forgot_password,
                .forgot_password => .register,
                .register => .register,
            };
        } else {
            self.register_field = switch (self.register_field) {
                .username => .password,
                .password => .confirm_password,
                .confirm_password => .create_account,
                .create_account => .back_to_login,
                .back_to_login => .back_to_login,
            };
        }
    }

    const max_input_len = 25;

    /// Returns a TextFieldEditor for the currently active text field, or null if
    /// the current field is not editable (e.g., buttons like forgot_password, register).
    fn getActiveFieldEditor(self: *ScreenManager) ?TextFieldEditor {
        if (self.current_screen == .login) {
            return switch (self.login_field) {
                .username => TextFieldEditor{
                    .buffer = &self.username_buffer,
                    .len = &self.username_len,
                    .cursor = &self.username_cursor,
                    .max_len = max_input_len,
                },
                .password => TextFieldEditor{
                    .buffer = &self.password_buffer,
                    .len = &self.password_len,
                    .cursor = &self.password_cursor,
                    .max_len = max_input_len,
                },
                .forgot_password, .register => null,
            };
        } else {
            return switch (self.register_field) {
                .username => TextFieldEditor{
                    .buffer = &self.username_buffer,
                    .len = &self.username_len,
                    .cursor = &self.username_cursor,
                    .max_len = max_input_len,
                },
                .password => TextFieldEditor{
                    .buffer = &self.password_buffer,
                    .len = &self.password_len,
                    .cursor = &self.password_cursor,
                    .max_len = max_input_len,
                },
                .confirm_password => TextFieldEditor{
                    .buffer = &self.confirm_password_buffer,
                    .len = &self.confirm_password_len,
                    .cursor = &self.confirm_password_cursor,
                    .max_len = max_input_len,
                },
                .create_account, .back_to_login => null,
            };
        }
    }

    fn handleLeftArrow(self: *ScreenManager) void {
        if (self.getActiveFieldEditor()) |*editor| {
            editor.moveCursorLeft();
        }
    }

    fn handleRightArrow(self: *ScreenManager) void {
        if (self.getActiveFieldEditor()) |*editor| {
            editor.moveCursorRight();
        }
    }

    fn handleEnter(self: *ScreenManager) void {
        if (self.current_screen == .login) {
            if (self.login_field == .username) {
                self.login_field = .password;
            } else if (self.login_field == .password) {
                // Submit login
                self.done = true;
            } else if (self.login_field == .forgot_password) {
                // TODO: Handle forgot password
                self.done = true;
            } else if (self.login_field == .register) {
                // Switch to register screen
                self.current_screen = .register;
                self.register_field = .username;
            }
        } else {
            if (self.register_field == .username) {
                self.register_field = .password;
            } else if (self.register_field == .password) {
                self.register_field = .confirm_password;
            } else if (self.register_field == .confirm_password) {
                self.register_field = .create_account;
            } else if (self.register_field == .create_account) {
                // Submit registration
                self.done = true;
            } else if (self.register_field == .back_to_login) {
                // Switch back to login screen
                self.current_screen = .login;
                self.login_field = .username;
                // Reset register fields
                self.confirm_password_len = 0;
                self.confirm_password_cursor = 0;
            }
        }
    }

    fn handleBackspace(self: *ScreenManager) void {
        if (self.getActiveFieldEditor()) |*editor| {
            editor.delete();
        }
    }

    fn handlePrintableChar(self: *ScreenManager, byte: u8) void {
        if (self.getActiveFieldEditor()) |*editor| {
            editor.insert(byte);
        }
    }
};
