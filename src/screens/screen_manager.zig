const std = @import("std");
const types = @import("types.zig");
const TextFieldEditor = @import("../ui/text_field_editor.zig").TextFieldEditor;
const chat_screen = @import("chat_screen.zig");

// Storage for a single chat message with its own buffers
pub const StoredMessage = struct {
    sender_buf: [32]u8 = undefined,
    sender_len: usize = 0,
    content_buf: [256]u8 = undefined,
    content_len: usize = 0,
    is_system: bool = false,

    pub fn toDisplayMessage(self: *const StoredMessage) chat_screen.ChatMessage {
        return chat_screen.ChatMessage{
            .sender = self.sender_buf[0..self.sender_len],
            .content = self.content_buf[0..self.content_len],
            .is_system = self.is_system,
        };
    }
};

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

    // Chat state with thread-safe message storage
    chat_input_buffer: [256]u8,
    chat_input_len: usize,
    chat_input_cursor: usize,
    stored_messages: [100]StoredMessage,
    chat_message_count: usize,
    mutex: std.Thread.Mutex,
    has_new_messages: bool,

    // Status/error message
    status_message: [128]u8,
    status_len: usize,
    status_is_error: bool,

    // Action flags for application layer
    should_login: bool,
    should_register: bool,
    should_send_message: bool,

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
            .chat_input_buffer = undefined,
            .chat_input_len = 0,
            .chat_input_cursor = 0,
            .stored_messages = [_]StoredMessage{.{}} ** 100,
            .chat_message_count = 0,
            .mutex = .{},
            .has_new_messages = false,
            .status_message = undefined,
            .status_len = 0,
            .status_is_error = false,
            .should_login = false,
            .should_register = false,
            .should_send_message = false,
        };
    }

    pub fn setStatus(self: *ScreenManager, message: []const u8, is_error: bool) void {
        const len = @min(message.len, self.status_message.len);
        @memcpy(self.status_message[0..len], message[0..len]);
        self.status_len = len;
        self.status_is_error = is_error;
    }

    pub fn clearStatus(self: *ScreenManager) void {
        self.status_len = 0;
    }

    /// Thread-safe method to add a chat message (copies the data into internal buffers)
    pub fn addChatMessage(self: *ScreenManager, sender: []const u8, content: []const u8, is_system: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.chat_message_count >= self.stored_messages.len) {
            // Shift messages up (remove oldest)
            for (0..self.stored_messages.len - 1) |i| {
                self.stored_messages[i] = self.stored_messages[i + 1];
            }
            self.chat_message_count = self.stored_messages.len - 1;
        }

        // Copy sender into buffer
        var msg = &self.stored_messages[self.chat_message_count];
        const sender_len = @min(sender.len, msg.sender_buf.len);
        @memcpy(msg.sender_buf[0..sender_len], sender[0..sender_len]);
        msg.sender_len = sender_len;

        // Copy content into buffer
        const content_len = @min(content.len, msg.content_buf.len);
        @memcpy(msg.content_buf[0..content_len], content[0..content_len]);
        msg.content_len = content_len;

        msg.is_system = is_system;
        self.chat_message_count += 1;
        self.has_new_messages = true;
    }

    /// Get messages for display (builds array of ChatMessage from stored data)
    pub fn getDisplayMessages(self: *ScreenManager, out: []chat_screen.ChatMessage) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const count = @min(self.chat_message_count, out.len);
        for (0..count) |i| {
            out[i] = self.stored_messages[i].toDisplayMessage();
        }
        return count;
    }

    pub fn switchToChat(self: *ScreenManager) void {
        self.current_screen = .chat;
        self.clearStatus();
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
        switch (self.current_screen) {
            .login => {
                self.login_field = switch (self.login_field) {
                    .username => .username,
                    .password => .username,
                    .forgot_password => .password,
                    .register => .forgot_password,
                };
            },
            .register => {
                self.register_field = switch (self.register_field) {
                    .username => .username,
                    .password => .username,
                    .confirm_password => .password,
                    .create_account => .confirm_password,
                    .back_to_login => .create_account,
                };
            },
            .chat => {
                // Could scroll messages up in the future
            },
        }
    }

    fn handleDownArrow(self: *ScreenManager) void {
        switch (self.current_screen) {
            .login => {
                self.login_field = switch (self.login_field) {
                    .username => .password,
                    .password => .forgot_password,
                    .forgot_password => .register,
                    .register => .register,
                };
            },
            .register => {
                self.register_field = switch (self.register_field) {
                    .username => .password,
                    .password => .confirm_password,
                    .confirm_password => .create_account,
                    .create_account => .back_to_login,
                    .back_to_login => .back_to_login,
                };
            },
            .chat => {
                // Could scroll messages down in the future
            },
        }
    }

    const max_input_len = 25;
    const max_chat_input_len = 200;

    /// Returns a TextFieldEditor for the currently active text field, or null if
    /// the current field is not editable (e.g., buttons like forgot_password, register).
    fn getActiveFieldEditor(self: *ScreenManager) ?TextFieldEditor {
        switch (self.current_screen) {
            .login => {
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
            },
            .register => {
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
            },
            .chat => {
                return TextFieldEditor{
                    .buffer = &self.chat_input_buffer,
                    .len = &self.chat_input_len,
                    .cursor = &self.chat_input_cursor,
                    .max_len = max_chat_input_len,
                };
            },
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
        switch (self.current_screen) {
            .login => {
                if (self.login_field == .username) {
                    self.login_field = .password;
                } else if (self.login_field == .password) {
                    // Submit login - set flag for application to handle
                    self.should_login = true;
                } else if (self.login_field == .forgot_password) {
                    // TODO: Handle forgot password
                    self.setStatus("Forgot password not implemented yet", true);
                } else if (self.login_field == .register) {
                    // Switch to register screen
                    self.current_screen = .register;
                    self.register_field = .username;
                    self.clearStatus();
                }
            },
            .register => {
                if (self.register_field == .username) {
                    self.register_field = .password;
                } else if (self.register_field == .password) {
                    self.register_field = .confirm_password;
                } else if (self.register_field == .confirm_password) {
                    self.register_field = .create_account;
                } else if (self.register_field == .create_account) {
                    // Validate passwords match
                    const pwd = self.password_buffer[0..self.password_len];
                    const confirm = self.confirm_password_buffer[0..self.confirm_password_len];
                    if (!std.mem.eql(u8, pwd, confirm)) {
                        self.setStatus("Passwords do not match!", true);
                        return;
                    }
                    // Submit registration - set flag for application to handle
                    self.should_register = true;
                } else if (self.register_field == .back_to_login) {
                    // Switch back to login screen
                    self.current_screen = .login;
                    self.login_field = .username;
                    self.clearStatus();
                    // Reset register fields
                    self.confirm_password_len = 0;
                    self.confirm_password_cursor = 0;
                }
            },
            .chat => {
                // Send message if input is not empty
                if (self.chat_input_len > 0) {
                    self.should_send_message = true;
                }
            },
        }
    }

    pub fn clearChatInput(self: *ScreenManager) void {
        self.chat_input_len = 0;
        self.chat_input_cursor = 0;
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
