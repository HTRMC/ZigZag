const std = @import("std");

pub const User = struct {
    username: []const u8,
    password_hash: [128]u8, // Argon2id encoded hash

    pub fn deinit(self: *User, allocator: std.mem.Allocator) void {
        allocator.free(self.username);
    }
};

pub const Database = struct {
    allocator: std.mem.Allocator,
    users: std.StringHashMap(User),
    file_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !Database {
        var db = Database{
            .allocator = allocator,
            .users = std.StringHashMap(User).init(allocator),
            .file_path = file_path,
        };

        // Try to load existing data
        db.load() catch |err| {
            if (err != error.FileNotFound) {
                return err;
            }
            // File doesn't exist yet, that's fine
        };

        return db;
    }

    pub fn deinit(self: *Database) void {
        var iter = self.users.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.users.deinit();
    }

    pub fn createUser(self: *Database, username: []const u8, password: []const u8) !void {
        // Check if user already exists
        if (self.users.contains(username)) {
            return error.UserAlreadyExists;
        }

        // Hash the password using Argon2id (resistant to rainbow table attacks)
        var hash_buf: [128]u8 = undefined;
        const hash_str = std.crypto.pwhash.argon2.strHash(password, .{
            .allocator = self.allocator,
            .params = .{ .t = 3, .m = 65536, .p = 4 }, // OWASP recommended minimum
        }, &hash_buf) catch return error.HashingFailed;
        // Null-terminate after the hash string
        @memset(hash_buf[hash_str.len..], 0);

        // Copy username for storage
        const username_copy = try self.allocator.dupe(u8, username);
        errdefer self.allocator.free(username_copy);

        const user = User{
            .username = username_copy,
            .password_hash = hash_buf,
        };

        try self.users.put(username_copy, user);
        try self.save();
    }

    pub fn verifyUser(self: *Database, username: []const u8, password: []const u8) bool {
        const user = self.users.get(username) orelse return false;

        // Find end of hash string (null terminated in buffer)
        var hash_len: usize = 0;
        for (user.password_hash) |c| {
            if (c == 0) break;
            hash_len += 1;
        }

        // Verify using Argon2id (constant-time comparison built-in)
        std.crypto.pwhash.argon2.strVerify(user.password_hash[0..hash_len], password, .{
            .allocator = self.allocator,
        }) catch return false;

        return true;
    }

    pub fn userExists(self: *Database, username: []const u8) bool {
        return self.users.contains(username);
    }

    fn save(self: *Database) !void {
        // Use std.fs for file operations (std.Io write is not implemented yet)
        const file = try std.fs.cwd().createFile(self.file_path, .{});
        defer file.close();

        // Build content in a buffer manually
        var content_buf: [8192]u8 = undefined;
        var pos: usize = 0;

        // Write number of users
        const count_str = std.fmt.bufPrint(content_buf[pos..], "{d}\n", .{self.users.count()}) catch return error.BufferTooSmall;
        pos += count_str.len;

        // Write each user
        var iter = self.users.iterator();
        while (iter.next()) |entry| {
            const user = entry.value_ptr.*;
            // Find actual hash length (null-terminated)
            var hash_len: usize = 0;
            for (user.password_hash) |c| {
                if (c == 0) break;
                hash_len += 1;
            }
            const user_str = std.fmt.bufPrint(content_buf[pos..], "{s}\n{s}\n", .{ user.username, user.password_hash[0..hash_len] }) catch return error.BufferTooSmall;
            pos += user_str.len;
        }

        // Write to file
        try file.writeAll(content_buf[0..pos]);
    }

    fn load(self: *Database) !void {
        // Use std.fs for file operations
        const file = std.fs.cwd().openFile(self.file_path, .{}) catch |err| {
            if (err == error.FileNotFound) return error.FileNotFound;
            return err;
        };
        defer file.close();

        // Read entire file
        var buf: [8192]u8 = undefined;
        var total_read: usize = 0;
        while (total_read < buf.len) {
            const bytes_read = try file.read(buf[total_read..]);
            if (bytes_read == 0) break;
            total_read += bytes_read;
        }
        const content = buf[0..total_read];

        // Parse line by line
        var lines = std.mem.splitScalar(u8, content, '\n');

        // Read number of users
        const count_line = lines.next() orelse return;
        const count = std.fmt.parseInt(usize, std.mem.trim(u8, count_line, "\r"), 10) catch return;

        // Read each user
        for (0..count) |_| {
            const username_line = lines.next() orelse return;
            const username = std.mem.trim(u8, username_line, "\r");

            const hash_line = lines.next() orelse return;
            const hash_str = std.mem.trim(u8, hash_line, "\r");

            if (hash_str.len == 0 or hash_str.len > 128) continue;

            const username_copy = try self.allocator.dupe(u8, username);
            errdefer self.allocator.free(username_copy);

            var hash_buf: [128]u8 = undefined;
            @memcpy(hash_buf[0..hash_str.len], hash_str);
            @memset(hash_buf[hash_str.len..], 0);

            const user = User{
                .username = username_copy,
                .password_hash = hash_buf,
            };

            try self.users.put(username_copy, user);
        }
    }
};