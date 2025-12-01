const std = @import("std");
const Io = std.Io;
const database = @import("database.zig");

const Database = database.Database;

pub const Client = struct {
    stream: Io.net.Stream,
    username: ?[]const u8 = null,
    authenticated: bool = false,
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    db: Database,
    listener: Io.net.Server,
    clients: std.ArrayList(*Client),
    running: bool = true,
    threaded: Io.Threaded,

    pub fn init(allocator: std.mem.Allocator, port: u16) !Server {
        // Get threaded I/O interface
        var threaded = Io.Threaded.init(allocator);
        const io = threaded.io();

        // Create server address (listen on all interfaces)
        const address = Io.net.IpAddress{ .ip4 = Io.net.Ip4Address.unspecified(port) };

        // Start listening
        const listener = try address.listen(io, .{
            .reuse_address = true,
        });

        const db = try Database.init(allocator, "zigzag_users.db");

        return Server{
            .allocator = allocator,
            .db = db,
            .listener = listener,
            .clients = .empty,
            .threaded = threaded,
        };
    }

    pub fn deinit(self: *Server) void {
        const io = self.threaded.io();
        for (self.clients.items) |client| {
            client.stream.close(io);
            if (client.username) |name| {
                self.allocator.free(name);
            }
            self.allocator.destroy(client);
        }
        self.clients.deinit(self.allocator);
        self.listener.deinit(io);
        self.db.deinit();
    }

    pub fn run(self: *Server) !void {
        std.debug.print("Server listening on port 8080...\n", .{});

        while (self.running) {
            const io = self.threaded.io();
            // Accept new connection
            const stream = self.listener.accept(io) catch |err| {
                std.debug.print("Accept error: {}\n", .{err});
                continue;
            };

            std.debug.print("New connection accepted\n", .{});

            const client = try self.allocator.create(Client);
            client.* = Client{
                .stream = stream,
            };

            try self.clients.append(self.allocator, client);

            // Handle client in a separate thread
            const thread = try std.Thread.spawn(.{}, handleClient, .{ self, client });
            thread.detach();
        }
    }

    fn handleClient(self: *Server, client: *Client) void {
        defer self.removeClient(client);

        const io = self.threaded.io();
        var recv_buffer: [4096]u8 = undefined;
        var reader = client.stream.reader(io, &recv_buffer);

        while (true) {
            const line = reader.interface.takeDelimiterExclusive('\n') catch |err| {
                if (err == error.EndOfStream) {
                    std.debug.print("Client disconnected\n", .{});
                } else {
                    std.debug.print("Read error: {}\n", .{err});
                }
                break;
            };
            reader.interface.toss(1);

            const message = std.mem.trim(u8, line, "\r");
            self.handleMessage(client, message) catch |err| {
                std.debug.print("Message handling error: {}\n", .{err});
            };
        }
    }

    fn handleMessage(self: *Server, client: *Client, message: []const u8) !void {
        var iter = std.mem.splitScalar(u8, message, ' ');
        const command = iter.next() orelse return;

        if (std.mem.eql(u8, command, "REGISTER")) {
            const username = iter.next() orelse {
                try self.sendToClient(client, "ERROR Missing username\n");
                return;
            };
            const password = iter.next() orelse {
                try self.sendToClient(client, "ERROR Missing password\n");
                return;
            };

            self.db.createUser(username, password) catch |err| {
                if (err == error.UserAlreadyExists) {
                    try self.sendToClient(client, "ERROR Username already exists\n");
                } else {
                    try self.sendToClient(client, "ERROR Registration failed\n");
                }
                return;
            };

            try self.sendToClient(client, "OK Registered successfully\n");
            std.debug.print("User registered: {s}\n", .{username});
        } else if (std.mem.eql(u8, command, "LOGIN")) {
            const username = iter.next() orelse {
                try self.sendToClient(client, "ERROR Missing username\n");
                return;
            };
            const password = iter.next() orelse {
                try self.sendToClient(client, "ERROR Missing password\n");
                return;
            };

            if (self.db.verifyUser(username, password)) {
                client.authenticated = true;
                client.username = try self.allocator.dupe(u8, username);
                try self.sendToClient(client, "OK Login successful\n");
                std.debug.print("User logged in: {s}\n", .{username});

                // Notify others
                var notify_buf: [256]u8 = undefined;
                const notify_msg = try std.fmt.bufPrint(&notify_buf, "SYSTEM {s} joined the chat\n", .{username});
                try self.broadcast(notify_msg, client);
            } else {
                try self.sendToClient(client, "ERROR Invalid username or password\n");
            }
        } else if (std.mem.eql(u8, command, "MSG")) {
            if (!client.authenticated) {
                try self.sendToClient(client, "ERROR Not logged in\n");
                return;
            }

            const rest = iter.rest();
            if (rest.len == 0) {
                try self.sendToClient(client, "ERROR Empty message\n");
                return;
            }

            var msg_buf: [1024]u8 = undefined;
            const broadcast_msg = try std.fmt.bufPrint(&msg_buf, "MSG {s} {s}\n", .{ client.username.?, rest });
            try self.broadcast(broadcast_msg, client); // Exclude sender (they already see their own message)
        } else if (std.mem.eql(u8, command, "QUIT")) {
            if (client.authenticated and client.username != null) {
                var notify_buf: [256]u8 = undefined;
                const notify_msg = try std.fmt.bufPrint(&notify_buf, "SYSTEM {s} left the chat\n", .{client.username.?});
                try self.broadcast(notify_msg, client);
            }
        } else if (std.mem.eql(u8, command, "USERS")) {
            if (!client.authenticated) {
                try self.sendToClient(client, "ERROR Not logged in\n");
                return;
            }

            var users_buf: [2048]u8 = undefined;
            var pos: usize = 0;

            // Write "USERS " prefix
            const prefix = "USERS ";
            @memcpy(users_buf[pos .. pos + prefix.len], prefix);
            pos += prefix.len;

            var first = true;
            for (self.clients.items) |c| {
                if (c.authenticated and c.username != null) {
                    if (!first) {
                        users_buf[pos] = ',';
                        pos += 1;
                    }
                    const name = c.username.?;
                    @memcpy(users_buf[pos .. pos + name.len], name);
                    pos += name.len;
                    first = false;
                }
            }
            users_buf[pos] = '\n';
            pos += 1;

            try self.sendToClient(client, users_buf[0..pos]);
        } else {
            try self.sendToClient(client, "ERROR Unknown command\n");
        }
    }

    fn sendToClient(self: *Server, client: *Client, message: []const u8) !void {
        const io = self.threaded.io();
        var send_buffer: [4096]u8 = undefined;
        var writer = client.stream.writer(io, &send_buffer);
        try writer.interface.writeAll(message);
        try writer.interface.flush();
    }

    fn broadcast(self: *Server, message: []const u8, exclude: ?*Client) !void {
        for (self.clients.items) |client| {
            if (exclude != null and client == exclude) continue;
            if (!client.authenticated) continue;
            self.sendToClient(client, message) catch {};
        }
    }

    fn removeClient(self: *Server, client: *Client) void {
        const io = self.threaded.io();
        for (self.clients.items, 0..) |c, i| {
            if (c == client) {
                _ = self.clients.swapRemove(i);
                break;
            }
        }

        client.stream.close(io);
        if (client.username) |name| {
            self.allocator.free(name);
        }
        self.allocator.destroy(client);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const port: u16 = 8080;

    var server = try Server.init(allocator, port);
    defer server.deinit();

    try server.run();
}