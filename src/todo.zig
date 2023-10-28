const std = @import("std");
const t = std.testing;
const expect = std.testing.expect;

const Errors = error{
    EmptyLineError,
};

const Todo = struct {
    const Self = @This();

    description: []const u8,
    tags: [][]const u8,
    group: u8,

    pub fn from_line(line: []const u8, allocator: std.mem.Allocator) !Self {
        if (line.len == 0) {
            return Errors.EmptyLineError;
        }
        var items = std.mem.splitAny(u8, line, "+&");

        var description: []const u8 = undefined;

        if (items.next()) |item| {
            description = item;
        }

        var group: u8 = '-'; // Start with empty group.
        var tags = std.ArrayList([]const u8).init(allocator);
        defer tags.deinit();

        while (items.next()) |item| {
            switch (item[0]) {
                '&' => {
                    group = item[0];
                },
                '+' => {
                    try tags.append(item[1..]);
                },
                else => {
                    continue;
                },
            }
        }

        return .{
            .description = description,
            .group = group,
            .tags = try tags.toOwnedSlice(),
        };
    }
};

test "Make a Todo" {
    const td = try Todo.from_line("Make Bread", t.allocator);
    try expect(std.mem.eql(u8, td.description, "Make Bread"));

    // Default group.
    try expect(td.group == '-');

    // Should have no tags.
    try t.expectEqualSlices([]const u8, &[_][]const u8{}, td.tags);
}

test "Can't init empty line" {
    try std.testing.expectError(Errors.EmptyLineError, Todo.from_line("", t.allocator));
}
