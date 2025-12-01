const std = @import("std");
const terminal = @import("platform/terminal.zig");
const windows_io = @import("platform/windows_io.zig");
const screen_manager = @import("screens/screen_manager.zig");
const login_screen = @import("screens/login_screen.zig");
const register_screen = @import("screens/register_screen.zig");
const chat_screen = @import("screens/chat_screen.zig");
const result_screen = @import("screens/result_screen.zig");
const center = @import("ui/center.zig");
const draw = @import("ui/draw.zig");
const network = @import("network/client.zig");

const SERVER_PORT: u16 = 8080;

/// Background thread that receives messages from the server
fn receiveThread(manager: *screen_manager.ScreenManager, client: *network.ChatClient) void {
    var buf: [512]u8 = undefined;

    while (!manager.done) {
        // This blocks until data arrives (efficient - no CPU usage while waiting)
        const bytes_read = client.receive(&buf) catch |err| {
            if (err == error.EndOfStream) {
                manager.addChatMessage("System", "Disconnected from server", true);
            }
            break;
        };

        if (bytes_read == 0) {
            manager.addChatMessage("System", "Server closed connection", true);
            break;
        }

        const response = buf[0..bytes_read];
        const parsed = network.parseMessage(response);

        switch (parsed.msg_type) {
            .chat_message => {
                manager.addChatMessage(parsed.sender orelse "???", parsed.content, false);
            },
            .system_message => {
                manager.addChatMessage("System", parsed.content, true);
            },
            .user_list => {
                // Could display user list
            },
            .error_msg => {
                manager.addChatMessage("Error", parsed.content, true);
            },
            .ok => {
                // Ignore OK responses in chat mode
            },
            .unknown => {
                // Ignore unknown messages
            },
        }
    }
}

pub fn run(stdout: anytype, stdin: anytype) !void {
    // Initialize screen manager
    var manager = screen_manager.ScreenManager.init();

    // Initialize network client
    var client = network.ChatClient.init();
    var connected = false;
    var receive_thread: ?std.Thread = null;

    // Buffer for display messages
    var display_messages: [100]chat_screen.ChatMessage = undefined;

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
        const ui_width: u16 = if (manager.current_screen == .chat) 62 else 42;
        const ui_height: u16 = switch (manager.current_screen) {
            .login => 16,
            .register => 18,
            .chat => 20,
        };
        const offset = center.calculateCenterOffset(term_size, ui_width, ui_height);

        // Move cursor to starting position
        try draw.moveCursor(stdout, offset.row + 1, 1);

        // Render current screen
        switch (manager.current_screen) {
            .login => {
                const login_state = login_screen.LoginScreenState{
                    .username_buffer = manager.username_buffer[0..manager.username_len],
                    .password_buffer = manager.password_buffer[0..manager.password_len],
                    .field = manager.login_field,
                    .username_cursor = manager.username_cursor,
                    .password_cursor = manager.password_cursor,
                };
                try login_screen.render(stdout, offset, login_state, &cursor_visible);

                // Show status message if any
                if (manager.status_len > 0) {
                    try center.writeCenteredLine(stdout, offset, "");
                    if (manager.status_is_error) {
                        try stdout.writeAll("\x1b[31m"); // Red
                    } else {
                        try stdout.writeAll("\x1b[32m"); // Green
                    }
                    try center.writeCenteredLine(stdout, offset, manager.status_message[0..manager.status_len]);
                    try stdout.writeAll("\x1b[0m"); // Reset
                }
            },
            .register => {
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

                // Show status message if any
                if (manager.status_len > 0) {
                    try center.writeCenteredLine(stdout, offset, "");
                    if (manager.status_is_error) {
                        try stdout.writeAll("\x1b[31m"); // Red
                    } else {
                        try stdout.writeAll("\x1b[32m"); // Green
                    }
                    try center.writeCenteredLine(stdout, offset, manager.status_message[0..manager.status_len]);
                    try stdout.writeAll("\x1b[0m"); // Reset
                }
            },
            .chat => {
                // Get messages from thread-safe storage
                const msg_count = manager.getDisplayMessages(&display_messages);
                const chat_state = chat_screen.ChatScreenState{
                    .username = manager.username_buffer[0..manager.username_len],
                    .messages = display_messages[0..msg_count],
                    .input_buffer = manager.chat_input_buffer[0..manager.chat_input_len],
                    .input_cursor = manager.chat_input_cursor,
                };
                try chat_screen.render(stdout, offset, chat_state, &cursor_visible);
            },
        }

        try stdout.flush();

        // Handle action flags before reading new input
        if (manager.should_login) {
            manager.should_login = false;
            const started = try handleLogin(&manager, &client, &connected);
            if (started and receive_thread == null) {
                // Start receive thread after successful login
                receive_thread = try std.Thread.spawn(.{}, receiveThread, .{ &manager, &client });
            }
            continue;
        }

        if (manager.should_register) {
            manager.should_register = false;
            const started = try handleRegister(&manager, &client, &connected);
            if (started and receive_thread == null) {
                // Start receive thread after successful registration+login
                receive_thread = try std.Thread.spawn(.{}, receiveThread, .{ &manager, &client });
            }
            continue;
        }

        if (manager.should_send_message) {
            manager.should_send_message = false;
            try handleSendMessage(&manager, &client);
            continue;
        }

        // In chat mode, use timeout-based input to allow receiving messages
        if (manager.current_screen == .chat) {
            // Use 100ms timeout so we can check for new messages
            const input = windows_io.readInputWithTimeout(100);
            switch (input.result) {
                .timeout => {
                    // Only redraw if there are new messages
                    if (manager.has_new_messages) {
                        manager.has_new_messages = false;
                        continue; // Redraw
                    }
                    // No new messages, no input - don't redraw, just wait again
                    // Jump back to input check without redrawing
                    while (true) {
                        const next_input = windows_io.readInputWithTimeout(100);
                        switch (next_input.result) {
                            .timeout => {
                                if (manager.has_new_messages) {
                                    manager.has_new_messages = false;
                                    break; // Exit inner loop to redraw
                                }
                                // Keep waiting
                            },
                            .resize => break, // Exit to redraw
                            .input => {
                                try manager.handleInput(next_input.byte, stdin);
                                break; // Exit to redraw after input
                            },
                        }
                    }
                },
                .resize => continue, // Redraw on resize
                .input => {
                    try manager.handleInput(input.byte, stdin);
                },
            }
        } else {
            // Not in chat - use blocking input
            const maybe_byte = try windows_io.readInputOrResize(stdin);
            if (maybe_byte == null) {
                continue; // Window resized
            }
            try manager.handleInput(maybe_byte.?, stdin);
        }
    }

    // Clean up network connection
    if (connected) {
        client.quit();
    }

    // Show result screen if we exited from login/register
    if (manager.current_screen != .chat) {
        try result_screen.render(stdout, &manager);
    }
}

fn handleLogin(manager: *screen_manager.ScreenManager, client: *network.ChatClient, connected: *bool) !bool {
    const username = manager.username_buffer[0..manager.username_len];
    const password = manager.password_buffer[0..manager.password_len];

    if (username.len == 0) {
        manager.setStatus("Username cannot be empty", true);
        return false;
    }
    if (password.len == 0) {
        manager.setStatus("Password cannot be empty", true);
        return false;
    }

    // Try to connect if not connected
    if (!connected.*) {
        manager.setStatus("Connecting to server...", false);
        client.connect("127.0.0.1", SERVER_PORT) catch {
            manager.setStatus("Cannot connect to server", true);
            return false;
        };
        connected.* = true;
    }

    // Send login request
    manager.setStatus("Logging in...", false);

    var cmd_buf: [512]u8 = undefined;
    const cmd = std.fmt.bufPrint(&cmd_buf, "LOGIN {s} {s}\n", .{ username, password }) catch {
        manager.setStatus("Error formatting request", true);
        return false;
    };

    client.send(cmd) catch {
        manager.setStatus("Error sending login request", true);
        connected.* = false;
        return false;
    };

    // Read response
    var response_buf: [256]u8 = undefined;
    const bytes_read = client.receive(&response_buf) catch {
        manager.setStatus("Error reading server response", true);
        connected.* = false;
        return false;
    };

    if (bytes_read == 0) {
        manager.setStatus("Server closed connection", true);
        connected.* = false;
        return false;
    }

    const response = response_buf[0..bytes_read];

    if (network.isSuccess(response)) {
        // Login successful - switch to chat screen
        manager.setStatus("Login successful!", false);
        manager.switchToChat();
        manager.addChatMessage("System", "Welcome to ZigZag Chat!", true);
        return true;
    } else {
        // Login failed
        const err_msg = network.getErrorMessage(response);
        manager.setStatus(err_msg, true);
        return false;
    }
}

fn handleRegister(manager: *screen_manager.ScreenManager, client: *network.ChatClient, connected: *bool) !bool {
    const username = manager.username_buffer[0..manager.username_len];
    const password = manager.password_buffer[0..manager.password_len];

    if (username.len == 0) {
        manager.setStatus("Username cannot be empty", true);
        return false;
    }
    if (password.len == 0) {
        manager.setStatus("Password cannot be empty", true);
        return false;
    }

    // Try to connect if not connected
    if (!connected.*) {
        manager.setStatus("Connecting to server...", false);
        client.connect("127.0.0.1", SERVER_PORT) catch {
            manager.setStatus("Cannot connect to server", true);
            return false;
        };
        connected.* = true;
    }

    // Send register request
    manager.setStatus("Registering...", false);

    var cmd_buf: [512]u8 = undefined;
    const cmd = std.fmt.bufPrint(&cmd_buf, "REGISTER {s} {s}\n", .{ username, password }) catch {
        manager.setStatus("Error formatting request", true);
        return false;
    };

    client.send(cmd) catch {
        manager.setStatus("Error sending register request", true);
        connected.* = false;
        return false;
    };

    // Read response
    var response_buf: [256]u8 = undefined;
    const bytes_read = client.receive(&response_buf) catch {
        manager.setStatus("Error reading server response", true);
        connected.* = false;
        return false;
    };

    if (bytes_read == 0) {
        manager.setStatus("Server closed connection", true);
        connected.* = false;
        return false;
    }

    const response = response_buf[0..bytes_read];

    if (network.isSuccess(response)) {
        // Registration successful - now login
        manager.setStatus("Registered! Logging in...", false);

        // Send login request
        const login_cmd = std.fmt.bufPrint(&cmd_buf, "LOGIN {s} {s}\n", .{ username, password }) catch {
            manager.setStatus("Error formatting login request", true);
            return false;
        };

        client.send(login_cmd) catch {
            manager.setStatus("Error sending login request", true);
            connected.* = false;
            return false;
        };

        const login_bytes = client.receive(&response_buf) catch {
            manager.setStatus("Error reading login response", true);
            connected.* = false;
            return false;
        };

        if (login_bytes == 0) {
            manager.setStatus("Server closed connection", true);
            connected.* = false;
            return false;
        }

        const login_response = response_buf[0..login_bytes];

        if (network.isSuccess(login_response)) {
            manager.switchToChat();
            manager.addChatMessage("System", "Welcome to ZigZag Chat!", true);
            return true;
        } else {
            manager.setStatus("Login failed after registration", true);
            return false;
        }
    } else {
        // Registration failed
        const err_msg = network.getErrorMessage(response);
        manager.setStatus(err_msg, true);
        return false;
    }
}

fn handleSendMessage(manager: *screen_manager.ScreenManager, client: *network.ChatClient) !void {
    const message = manager.chat_input_buffer[0..manager.chat_input_len];

    if (message.len == 0) {
        return;
    }

    var cmd_buf: [1024]u8 = undefined;
    const cmd = std.fmt.bufPrint(&cmd_buf, "MSG {s}\n", .{message}) catch {
        return;
    };

    client.send(cmd) catch {
        manager.addChatMessage("System", "Failed to send message", true);
        return;
    };

    // Clear input after sending
    manager.clearChatInput();

    // Add our own message to the display (server will also broadcast it back)
    const username = manager.username_buffer[0..manager.username_len];
    manager.addChatMessage(username, message, false);
}