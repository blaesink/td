const std = @import("std");
const t = std.testing;
const expect = std.testing.expect;

const Errors = error{
    EmptyLineError,
};

pub const Todo = struct {
    const Self = @This();

    description: []const u8,
    tags: [][]const u8,
    group: u8,

    pub fn fromLine(line: []const u8, allocator: std.mem.Allocator) !Self {
        if (line.len == 0) {
            return Errors.EmptyLineError;
        }

        var group: u8 = '-'; // Start with empty group.

        var description_words = std.ArrayList(u8).init(allocator);
        defer description_words.deinit();

        var tags = std.ArrayList([]const u8).init(allocator);
        defer tags.deinit();

        var tokens = std.mem.splitScalar(u8, line, ' ');

        return .{
            .description = description,
            .group = group,
            .tags = try tags.toOwnedSlice(),
        };
    }
};

test "Make a Todo" {
    const td = try Todo.fromLine("Make Bread", t.allocator);
    try expect(std.mem.eql(u8, td.description, "Make Bread"));

    // Default group.
    try expect(td.group == '-');

    // Should have no tags.
    try t.expectEqualSlices([]const u8, &[_][]const u8{}, td.tags);
}

test "Can't init empty line" {
    try std.testing.expectError(Errors.EmptyLineError, Todo.fromLine("", t.allocator));
}

test "Make a todo with a tag" {
    const td = try Todo.fromLine("Make Bread +Party", t.allocator);

    try t.expectEqualSlices([]const u8, &[_][]const u8{"Party"}, td.tags);
}

test "Make a todo with a group" {
    const td = try Todo.fromLine("Make Bread &P", t.allocator);

    try expect(td.group == 'P');
}
