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

    description: ArrayList(u8),
    tags: ArrayList([]const u8),
    group: u8, // Single character
    raw_length: usize,

    /// For use in creating a todo when it's already written into a todo file.
    pub fn fromFormattedLine(line: []const u8, allocator: std.mem.Allocator) !Self {
        if (line.len == 0) {
            return Errors.EmptyLineError;
        }

        const group: u8 = line[0];
        var description = ArrayList(u8).init(allocator);
        var tags = ArrayList([]const u8).init(allocator);
        var hash: [32]u8 = undefined;

        const first_tag_index = std.mem.indexOfScalar(u8, line, '+') orelse line.len;
        const description_start_index = 2; // 0 is group char, 1 is a space.
        const hash_start_index = std.mem.indexOfScalar(u8, line, '(').?;
        const hash_end_index = std.mem.indexOfScalar(u8, line[hash_start_index..], ')').? + hash_start_index;

        // FIXME: there has to be a more idiomatic way to do this.. not the "C" way lol.
        for (line[hash_start_index + 1 .. hash_end_index], 0..) |chr, i| {
            hash[i] = chr;
        }

        if (first_tag_index < line.len) {
            // - 1 because we need to ignore previous whitespace.
            try description.appendSlice(line[description_start_index .. first_tag_index - 1]);
            _ = try generateTags(line, first_tag_index, line.len, &tags);
        } else {
            try description.appendSlice(line[description_start_index .. hash_start_index - 1]);
        }

        return .{
            .description = description,
            .group = group,
            .tags = tags,
            .raw_length = description.items.len,
        };
    }

    pub fn fromLine(line: []const u8, allocator: std.mem.Allocator) !Self {
        if (line.len == 0) {
            return Errors.EmptyLineError;
        }

        var description = ArrayList(u8).init(allocator);
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
            .description = description,
            .group = group,
            .tags = tags,
            .raw_length = line.len,
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
            .description = ArrayList(u8).init(allocator),
            .group = group,
            .tags = tags,
            .raw_length = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.description.deinit();
        self.tags.deinit();
    }

    /// Return a nicely formatted string of this object (how it was written).
    pub fn format_self(self: Self) []const u8 {
        _ = self;
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

    try t.expectEqualSlices(u8, "Hello World!", td.description.items);
}

test "Make a Todo" {
    var td = try Todo.fromLine("Hello World! +Newbie &A", t.allocator);
    defer td.deinit();

    try t.expectEqualSlices(u8, "Hello World!", td.description.items);
    try t.expect(td.group == 'A');
    const expected_tags = &[_][]const u8{"Newbie"};

    for (expected_tags, td.tags.items) |expected, actual| {
        try t.expectEqualSlices(u8, expected, actual);
    }
}

test "Check formatting" {
    return error.SkipZigTest;
    // const line = "Hello World! +Newbie &A";
    // var td = try Todo.fromLine(line, t.allocator);
    // defer td.deinit();

    // try t.expectEqualSlices(u8, line, td.format_self());
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

    var todo = try Todo.fromFormattedLine(line, t.allocator);
    defer todo.deinit();

    try t.expect(todo.group == 'B');
    try t.expectEqualSlices(u8, "All your todo are belong to us.", todo.description.items);
}

test "Make a simple query" {
    var todo = try Todo.fromLineNoDescription("&B", t.allocator);
    defer todo.deinit();

    try t.expect(todo.group == 'B');
}
