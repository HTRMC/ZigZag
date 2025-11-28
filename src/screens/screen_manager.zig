const std = @import("std");
const types = @import("types.zig");

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

    fn handleLeftArrow(self: *ScreenManager) void {
        if (self.current_screen == .login) {
            if (self.login_field == .username and self.username_cursor > 0) {
                self.username_cursor -= 1;
            } else if (self.login_field == .password and self.password_cursor > 0) {
                self.password_cursor -= 1;
            }
        } else {
            if (self.register_field == .username and self.username_cursor > 0) {
                self.username_cursor -= 1;
            } else if (self.register_field == .password and self.password_cursor > 0) {
                self.password_cursor -= 1;
            } else if (self.register_field == .confirm_password and self.confirm_password_cursor > 0) {
                self.confirm_password_cursor -= 1;
            }
        }
    }

    fn handleRightArrow(self: *ScreenManager) void {
        if (self.current_screen == .login) {
            if (self.login_field == .username and self.username_cursor < self.username_len) {
                self.username_cursor += 1;
            } else if (self.login_field == .password and self.password_cursor < self.password_len) {
                self.password_cursor += 1;
            }
        } else {
            if (self.register_field == .username and self.username_cursor < self.username_len) {
                self.username_cursor += 1;
            } else if (self.register_field == .password and self.password_cursor < self.password_len) {
                self.password_cursor += 1;
            } else if (self.register_field == .confirm_password and self.confirm_password_cursor < self.confirm_password_len) {
                self.confirm_password_cursor += 1;
            }
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
        if (self.current_screen == .login) {
            if (self.login_field == .username and self.username_cursor > 0) {
                var j: usize = self.username_cursor;
                while (j < self.username_len) : (j += 1) {
                    self.username_buffer[j - 1] = self.username_buffer[j];
                }
                self.username_len -= 1;
                self.username_cursor -= 1;
            } else if (self.login_field == .password and self.password_cursor > 0) {
                var j: usize = self.password_cursor;
                while (j < self.password_len) : (j += 1) {
                    self.password_buffer[j - 1] = self.password_buffer[j];
                }
                self.password_len -= 1;
                self.password_cursor -= 1;
            }
        } else {
            if (self.register_field == .username and self.username_cursor > 0) {
                var j: usize = self.username_cursor;
                while (j < self.username_len) : (j += 1) {
                    self.username_buffer[j - 1] = self.username_buffer[j];
                }
                self.username_len -= 1;
                self.username_cursor -= 1;
            } else if (self.register_field == .password and self.password_cursor > 0) {
                var j: usize = self.password_cursor;
                while (j < self.password_len) : (j += 1) {
                    self.password_buffer[j - 1] = self.password_buffer[j];
                }
                self.password_len -= 1;
                self.password_cursor -= 1;
            } else if (self.register_field == .confirm_password and self.confirm_password_cursor > 0) {
                var j: usize = self.confirm_password_cursor;
                while (j < self.confirm_password_len) : (j += 1) {
                    self.confirm_password_buffer[j - 1] = self.confirm_password_buffer[j];
                }
                self.confirm_password_len -= 1;
                self.confirm_password_cursor -= 1;
            }
        }
    }

    fn handlePrintableChar(self: *ScreenManager, byte: u8) void {
        const max_input_len = 25;
        if (self.current_screen == .login) {
            if (self.login_field == .username and self.username_len < max_input_len) {
                var j: usize = self.username_len;
                while (j > self.username_cursor) : (j -= 1) {
                    self.username_buffer[j] = self.username_buffer[j - 1];
                }
                self.username_buffer[self.username_cursor] = byte;
                self.username_len += 1;
                self.username_cursor += 1;
            } else if (self.login_field == .password and self.password_len < max_input_len) {
                var j: usize = self.password_len;
                while (j > self.password_cursor) : (j -= 1) {
                    self.password_buffer[j] = self.password_buffer[j - 1];
                }
                self.password_buffer[self.password_cursor] = byte;
                self.password_len += 1;
                self.password_cursor += 1;
            }
        } else {
            if (self.register_field == .username and self.username_len < max_input_len) {
                var j: usize = self.username_len;
                while (j > self.username_cursor) : (j -= 1) {
                    self.username_buffer[j] = self.username_buffer[j - 1];
                }
                self.username_buffer[self.username_cursor] = byte;
                self.username_len += 1;
                self.username_cursor += 1;
            } else if (self.register_field == .password and self.password_len < max_input_len) {
                var j: usize = self.password_len;
                while (j > self.password_cursor) : (j -= 1) {
                    self.password_buffer[j] = self.password_buffer[j - 1];
                }
                self.password_buffer[self.password_cursor] = byte;
                self.password_len += 1;
                self.password_cursor += 1;
            } else if (self.register_field == .confirm_password and self.confirm_password_len < max_input_len) {
                var j: usize = self.confirm_password_len;
                while (j > self.confirm_password_cursor) : (j -= 1) {
                    self.confirm_password_buffer[j] = self.confirm_password_buffer[j - 1];
                }
                self.confirm_password_buffer[self.confirm_password_cursor] = byte;
                self.confirm_password_len += 1;
                self.confirm_password_cursor += 1;
            }
        }
    }
};
