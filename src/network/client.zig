const std = @import("std");
const Io = std.Io;

pub const ChatClient = struct {
    stream: ?Io.net.Stream = null,
    threaded: Io.Threaded = Io.Threaded.init_single_threaded,
    connected: bool = false,
    recv_buffer: [4096]u8 = undefined,
    send_buffer: [4096]u8 = undefined,

    pub fn init() ChatClient {
        return ChatClient{};
    }

    pub fn connect(self: *ChatClient, host: []const u8, port: u16) !void {
        _ = host; // For now, localhost only
        const io = self.threaded.io();
        const address = Io.net.IpAddress{ .ip4 = Io.net.Ip4Address.loopback(port) };
        self.stream = try address.connect(io, .{ .mode = .stream });
        self.connected = true;
    }

    pub fn disconnect(self: *ChatClient) void {
        const io = self.threaded.io();
        if (self.stream) |*stream| {
            stream.close(io);
        }
        self.stream = null;
        self.connected = false;
    }

    pub fn send(self: *ChatClient, message: []const u8) !void {
        if (self.stream) |stream| {
            const io = self.threaded.io();
            var writer = stream.writer(io, &self.send_buffer);
            try writer.interface.writeAll(message);
            try writer.interface.flush();
        } else {
            return error.NotConnected;
        }
    }

    pub fn receive(self: *ChatClient, buf: []u8) !usize {
        if (self.stream) |stream| {
            const io = self.threaded.io();
            var reader = stream.reader(io, &self.recv_buffer);
            const line = reader.interface.takeDelimiterExclusive('\n') catch |err| {
                if (err == error.EndOfStream) return 0;
                return err;
            };
            reader.interface.toss(1);
            const trimmed = std.mem.trim(u8, line, "\r");
            const copy_len = @min(trimmed.len, buf.len);
            @memcpy(buf[0..copy_len], trimmed[0..copy_len]);
            return copy_len;
        } else {
            return error.NotConnected;
        }
    }

    /// Send quit command
    pub fn quit(self: *ChatClient) void {
        self.send("QUIT\n") catch {};
        self.disconnect();
    }
};

/// Parse a server response to check if it's successful
pub fn isSuccess(response: []const u8) bool {
    return std.mem.startsWith(u8, response, "OK");
}

/// Extract error message from server response
pub fn getErrorMessage(response: []const u8) []const u8 {
    if (std.mem.startsWith(u8, response, "ERROR ")) {
        const msg = std.mem.trim(u8, response[6..], "\r\n");
        return msg;
    }
    return "Unknown error";
}

/// Parse incoming message type
pub const MessageType = enum {
    chat_message,
    system_message,
    user_list,
    error_msg,
    ok,
    unknown,
};

pub const ParsedMessage = struct {
    msg_type: MessageType,
    sender: ?[]const u8 = null,
    content: []const u8,
};

pub fn parseMessage(message: []const u8) ParsedMessage {
    const trimmed = std.mem.trim(u8, message, "\r\n");

    if (std.mem.startsWith(u8, trimmed, "MSG ")) {
        // Format: MSG username message_content
        const rest = trimmed[4..];
        if (std.mem.indexOfScalar(u8, rest, ' ')) |space_idx| {
            return ParsedMessage{
                .msg_type = .chat_message,
                .sender = rest[0..space_idx],
                .content = rest[space_idx + 1 ..],
            };
        }
        return ParsedMessage{ .msg_type = .chat_message, .content = rest };
    } else if (std.mem.startsWith(u8, trimmed, "SYSTEM ")) {
        return ParsedMessage{
            .msg_type = .system_message,
            .content = trimmed[7..],
        };
    } else if (std.mem.startsWith(u8, trimmed, "USERS ")) {
        return ParsedMessage{
            .msg_type = .user_list,
            .content = trimmed[6..],
        };
    } else if (std.mem.startsWith(u8, trimmed, "ERROR ")) {
        return ParsedMessage{
            .msg_type = .error_msg,
            .content = trimmed[6..],
        };
    } else if (std.mem.startsWith(u8, trimmed, "OK")) {
        return ParsedMessage{
            .msg_type = .ok,
            .content = if (trimmed.len > 3) trimmed[3..] else "",
        };
    }

    return ParsedMessage{ .msg_type = .unknown, .content = trimmed };
}