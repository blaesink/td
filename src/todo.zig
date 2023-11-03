const std = @import("std");
const t = std.testing;
const expect = std.testing.expect;
const ArrayList = std.ArrayList;

pub const Errors = error{
    EmptyLineError,
    FoundMultipleGroups,
};

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

    pub fn fromLine(line: []const u8, allocator: std.mem.Allocator) !Self {
        if (line.len == 0) {
            return Errors.EmptyLineError;
        }

        var description = ArrayList(u8).init(allocator);
        var group: u8 = '-';
        var tags = ArrayList([]const u8).init(allocator);

        const first_tag_index = std.mem.indexOfScalar(u8, line, '+') orelse line.len;
        const group_index = std.mem.indexOfScalar(u8, line, '&') orelse line.len;

        if (group_index != line.len) {
            const maybe_second_group = std.mem.lastIndexOfScalar(u8, line[group_index + 1 ..], '&');

            if (maybe_second_group != null) {
                return Errors.FoundMultipleGroups;
            }
            group = line[group_index + 1];
        }

        if (first_tag_index != line.len) {
            var tag_tokens = std.mem.tokenizeScalar(u8, line[first_tag_index..group_index], ' ');

            while (tag_tokens.next()) |tag| {
                try tags.append(tag[1..]);
            }
        }

        var words = std.mem.tokenizeScalar(u8, line[0..first_tag_index], ' ');

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
