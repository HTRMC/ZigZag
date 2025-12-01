const std = @import("std");

pub const FieldType = enum {
    text,
    password,
};

// Field line constants
const field_prefix_selected = "║ ► ";
const field_prefix_unselected = "║   ";
const field_suffix = "║";
const field_content_width = 37; // 42-char box - prefix (4 visual) - suffix (1 visual) = 37

/// Renders a field line with proper formatting
pub fn renderFieldLine(
    label: []const u8,
    content: []const u8,
    field_type: FieldType,
    is_selected: bool,
) struct { buf: [256]u8, len: usize } {
    var buf: [256]u8 = undefined;
    var idx: usize = 0;

    // Add border and selection indicator
    const prefix = if (is_selected) field_prefix_selected else field_prefix_unselected;
    @memcpy(buf[idx..][0..prefix.len], prefix);
    idx += prefix.len;

    // Add label
    @memcpy(buf[idx..][0..label.len], label);
    idx += label.len;

    // Add content (masked if password)
    const max_display_len = 25;
    const display_len = @min(content.len, max_display_len);

    if (field_type == .password) {
        // Mask password with asterisks
        for (0..display_len) |_| {
            buf[idx] = '*';
            idx += 1;
        }
    } else {
        // Display text normally
        @memcpy(buf[idx..][0..display_len], content[0..display_len]);
        idx += display_len;
    }

    // Add padding to align the right border
    const current_content = label.len + display_len;
    const padding = if (current_content < field_content_width)
        field_content_width - current_content
    else
        0;

    for (0..padding) |_| {
        buf[idx] = ' ';
        idx += 1;
    }

    // Add closing border
    @memcpy(buf[idx..][0..field_suffix.len], field_suffix);
    idx += field_suffix.len;

    return .{ .buf = buf, .len = idx };
}

// Result field constants
const result_prefix = "║  ";
const result_suffix = "║";
const result_content_width = 38; // 42-char box - 1 (prefix ║) - 2 (spaces) - 1 (suffix ║) = 38

/// Renders a simple result field line (without selection indicator)
pub fn renderResultFieldLine(
    label: []const u8,
    content: []const u8,
) struct { buf: [256]u8, len: usize } {
    var buf: [256]u8 = undefined;
    var idx: usize = 0;

    // Add border
    @memcpy(buf[idx..][0..result_prefix.len], result_prefix);
    idx += result_prefix.len;

    // Add label
    @memcpy(buf[idx..][0..label.len], label);
    idx += label.len;

    // Add content
    @memcpy(buf[idx..][0..content.len], content);
    idx += content.len;

    // Add padding
    const current_content = label.len + content.len;
    const padding = if (current_content < result_content_width)
        result_content_width - current_content
    else
        0;

    for (0..padding) |_| {
        buf[idx] = ' ';
        idx += 1;
    }

    // Add closing border
    @memcpy(buf[idx..][0..result_suffix.len], result_suffix);
    idx += result_suffix.len;

    return .{ .buf = buf, .len = idx };
}