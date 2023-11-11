const std = @import("std");
const t = std.testing;
const expect = std.testing.expect;
const ArrayList = std.ArrayList;

pub const Errors = error{
    EmptyLineError,
    FoundMultipleGroups,
};

/// Split a string between `start_index` and `end_index` and add its contents to `tags`.
fn generateTags(
    line: []const u8,
    start_index: usize,
    stop_index: usize,
    tags: *ArrayList([]const u8),
) !usize {
    var tag_tokens = std.mem.tokenizeScalar(u8, line[start_index..stop_index], ' ');

    var written_tags: usize = 0;

    while (tag_tokens.next()) |tag| {
        try tags.append(tag[1..]);
        written_tags += 1;
    }

    return written_tags;
}

/// A `Todo` holds its `description`, `tags` and `group`.
/// A `Todo` is written like so:
///
/// Make bread +Party
/// OR
/// Write that whitepaper +Work &A
/// Write that whitepaper &A +Work
///
/// Its format is `description <tags> <group>`.
pub const Todo = struct {
    const Self = @This();

    description: []const u8,
    tags: ArrayList([]const u8),
    group: u8, // Single character
    allocator: std.mem.Allocator,
    hash: ?[]const u8 = null,

    /// For use in creating a todo when it's already written into a todo file.
    pub fn fromFormattedLine(line: []const u8, allocator: std.mem.Allocator) !Self {
        if (line.len == 0) {
            return Errors.EmptyLineError;
        }

        const group: u8 = line[0];

        var description = ArrayList(u8).init(allocator);

        var tags = ArrayList([]const u8).init(allocator);

        const first_tag_index = std.mem.indexOfScalar(u8, line, '+') orelse line.len;
        const description_start_index = 2; // 0 is group char, 1 is a space.
        const hash_start_index = std.mem.lastIndexOfScalar(u8, line, '(');
        const hash_end_index = std.mem.lastIndexOfScalar(u8, line, ')');

        if (hash_start_index == null or hash_end_index == null) {
            return error.InvalidFormat;
        }

        const hash = line[hash_start_index.? + 1 .. hash_end_index.?];

        if (first_tag_index < line.len) {
            // - 1 because we need to ignore previous whitespace.
            try description.appendSlice(line[description_start_index .. first_tag_index - 1]);
            _ = try generateTags(line, first_tag_index, line.len, &tags);
        } else {
            try description.appendSlice(line[description_start_index .. hash_start_index.? - 1]);
        }

        return .{
            .description = try description.toOwnedSlice(),
            .group = group,
            .tags = tags,
            .allocator = allocator,
            .hash = hash,
        };
    }

    pub fn fromLine(line: []const u8, allocator: std.mem.Allocator) !Self {
        if (line.len == 0) {
            return Errors.EmptyLineError;
        }

        var description = ArrayList(u8).init(allocator);
        defer description.deinit();

        var group: u8 = '-';
        var tags = ArrayList([]const u8).init(allocator);

        const first_tag_index = std.mem.indexOfScalar(u8, line, '+') orelse line.len;
        const group_index = std.mem.indexOfScalar(u8, line, '&') orelse line.len;

        // Make sure that regardless of having a tag or not, a group or not, that the description
        // doesn't contain any of them.
        var end_of_description_index = @min(line.len, @min(first_tag_index, group_index));

        if (group_index != line.len) {
            const maybe_second_group = std.mem.lastIndexOfScalar(u8, line[group_index + 1 ..], '&');

            if (maybe_second_group != null) {
                return Errors.FoundMultipleGroups;
            }
            group = line[group_index + 1];
        }

        if (first_tag_index != line.len) {
            _ = try generateTags(line, first_tag_index, group_index, &tags);
        }

        var words = std.mem.tokenizeScalar(u8, line[0..end_of_description_index], ' ');

        while (words.next()) |word| {
            try description.appendSlice(word);

            // TODO: this probably isn't the best way to check this.
            if (words.peek() != null) {
                try description.append(' ');
            }
        }

        return .{
            .description = try description.toOwnedSlice(),
            .group = group,
            .tags = tags,
            .allocator = allocator,
        };
    }

    pub fn fromLineNoDescription(line: []const u8, allocator: std.mem.Allocator) !Self {
        const first_tag_index: ?usize = std.mem.indexOfScalar(u8, line, '+') orelse null;
        const group_index: ?usize = std.mem.indexOfScalar(u8, line, '&') orelse null;

        var tags = ArrayList([]const u8).init(allocator);

        var group: u8 = '-';

        if (group_index != null) {
            group = line[group_index.? + 1];
        }

        if (first_tag_index) |ti| {
            if (group_index) |gi| {
                _ = try generateTags(line, ti, gi, &tags);
            } else {
                _ = try generateTags(line, ti, line.len, &tags);
            }
        }

        return .{
            .description = "",
            .group = group,
            .tags = tags,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.description);
        self.tags.deinit();
    }

    /// Return a nicely formatted string of this object (how it was written).
    pub fn formatToStringAlloc(self: Self, hash: []const u8) ![]const u8 {
        var contents_to_write = ArrayList(u8).init(self.allocator);
        defer contents_to_write.deinit();

        if (self.tags.items.len > 0) {
            var tag_string = ArrayList(u8).init(self.allocator);
            defer tag_string.deinit();

            const tag_string_writer = tag_string.writer();

            // Format the tags.
            for (self.tags.items) |tag| {
                try std.fmt.format(tag_string_writer, "+{s} ", .{tag});
            }

            // Remove the last space from the string because I'm too lazy to do a conditional above.
            _ = tag_string.pop();

            try std.fmt.format(contents_to_write.writer(), "{c} {s} {s} ({s})\n", .{ self.group, self.description, tag_string.items, hash });
        } else {
            try std.fmt.format(contents_to_write.writer(), "{c} {s} ({s})\n", .{ self.group, self.description, hash });
        }

        return contents_to_write.toOwnedSlice();
    }
};

test "Can't make an empty Todo" {
    try t.expectError(Errors.EmptyLineError, Todo.fromLine("", t.allocator));
}

test "Can't have multiple groups in a Todo" {
    try t.expectError(Errors.FoundMultipleGroups, Todo.fromLine("&A &B", t.allocator));
}

test "Single Group Todo" {
    var td = try Todo.fromLine("Hello World! &A", t.allocator);
    defer td.deinit();

    try t.expectEqualSlices(u8, "Hello World!", td.description);
}

test "Make a Todo" {
    var td = try Todo.fromLine("Hello World! +Newbie &A", t.allocator);
    defer td.deinit();

    try t.expectEqualSlices(u8, "Hello World!", td.description);
    try t.expect(td.group == 'A');
    const expected_tags = &[_][]const u8{"Newbie"};

    for (expected_tags, td.tags.items) |expected, actual| {
        try t.expectEqualSlices(u8, expected, actual);
    }
}

test "Check formatting" {
    const line = "Hello World! +Newbie &A";

    var td = try Todo.fromLine(line, t.allocator);
    defer td.deinit();

    const expected_format = "A Hello World! +Newbie (abc123)\n";

    const actual_format = try td.formatToStringAlloc("abc123");
    defer t.allocator.free(actual_format);

    try t.expectEqualStrings(expected_format, actual_format);
}

test "Make a todo with No Description (for Querying)" {
    var td = try Todo.fromLineNoDescription("+A &B", t.allocator);
    defer td.deinit();

    t.expect(td.group == 'B') catch {
        std.log.err("Expected 'B', got {c}", .{td.group});
    };

    const expected_tags = &[_][]const u8{"A"};

    for (expected_tags, td.tags.items) |expected, actual| {
        try t.expectEqualStrings(expected, actual);
    }
}

test "Reconstruct from a formatted line" {
    const line = "B All your todo are belong to us. +1337 (abc123) ";

    const todo = try Todo.fromFormattedLine(line, t.allocator);
    defer todo.deinit();

    try t.expect(todo.group == 'B');
    try t.expectEqualStrings("All your todo are belong to us.", todo.description);
    try t.expectEqualStrings("abc123", todo.hash.?);
}

test "Make a simple query" {
    const todo = try Todo.fromLineNoDescription("&B", t.allocator);
    defer todo.deinit();

    try t.expect(todo.group == 'B');
}
