const std = @import("std");
const t = std.testing;
const expect = std.testing.expect;
const ArrayList = std.ArrayList;
const md5 = std.crypto.hash.Md5;

pub const Errors = error{
    EmptyLineError,
    FoundMultipleGroups,
};

/// Generates a string hash from the `Todo`'s description.
/// Returns the generated hash.
fn generateTodoHashAlloc(todo_description: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var hash_buf: [md5.digest_length]u8 = undefined;
    var output: [32]u8 = undefined;
    var result = ArrayList(u8).init(allocator);

    md5.hash(todo_description, &hash_buf, .{});

    _ = try std.fmt.bufPrint(&output, "{x}", .{std.fmt.fmtSliceHexLower(&hash_buf)});
    try result.appendSlice(&output);

    return result.toOwnedSlice();
}

/// Split a string between `start_index` and `end_index` and add its contents to `tags`.
/// # Returns:
/// The number of generated tags.
fn generateTags(
    line: []const u8,
    start_index: usize,
    stop_index: usize,
    tags: *ArrayList([]const u8),
) !usize {
    var tag_tokens = std.mem.tokenizeScalar(u8, line[start_index..stop_index], ' ');

    var num_written_tags: usize = 0;

    while (tag_tokens.next()) |tag| {
        // Skip the + or #.
        try tags.append(tag[1..]);
        num_written_tags += 1;
    }

    return num_written_tags;
}

/// Just holds the core parts of the todo.
/// General Todos have more allocated parts than others, such as those that
/// are from user input and need to have the hash allocated in order to outlive
/// the construction of the todo until it is written to file.
/// # Allocated attributes:
/// - `tags`
const TodoInner = struct {
    description: []const u8,
    group: u8,
    tags: [][]const u8, // Allocated
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

    allocator: std.mem.Allocator,
    hash: []const u8, // Allocated
    inner: TodoInner,

    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) std.os.WriteError!void {
        return writer.print("<Todo: &{c} {s}>", .{ self.inner.group, self.inner.description });
    }

    pub fn init(line: []const u8, allocator: std.mem.Allocator) !Self {
        if (line.len == 0)
            return Errors.EmptyLineError;

        var group: u8 = '-';
        var tags = ArrayList([]const u8).init(allocator);

        const first_tag_index = blk: {
            const maybe_pound_index = std.mem.indexOfScalar(u8, line, '#') orelse line.len;
            const maybe_plus_index = std.mem.indexOfScalar(u8, line, '+') orelse line.len;

            break :blk @min(maybe_pound_index, maybe_plus_index);
        };
        const group_index = std.mem.indexOfScalar(u8, line, '&') orelse line.len;

        const end_of_description_index = @min(line.len, @min(first_tag_index - 1, group_index - 1));

        // TODO: this could be handled more elegantly..
        if (first_tag_index != line.len and group_index != line.len and first_tag_index > group_index)
            return error.IncorrectFormat;

        if (group_index < line.len) {
            const maybe_second_group = std.mem.lastIndexOfScalar(u8, line[group_index + 1 ..], '&');

            if (maybe_second_group != null)
                return Errors.FoundMultipleGroups;

            group = line[group_index + 1];
        }

        if (first_tag_index != line.len)
            _ = try generateTags(line, first_tag_index, group_index, &tags);

        const description = line[0..end_of_description_index];
        const hash = try generateTodoHashAlloc(description, allocator);

        return .{
            .inner = TodoInner{
                .description = description,
                .group = group,
                .tags = try tags.toOwnedSlice(),
            },
            .allocator = allocator,
            .hash = hash,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.inner.tags);
        self.allocator.free(self.hash);
    }

    /// Return a nicely formatted string of this object (how it is represented).
    pub fn formatToStringAlloc(self: Self) ![]const u8 {
        var contents_to_write = ArrayList(u8).init(self.allocator);

        const writer = contents_to_write.writer();

        if (self.inner.tags.len > 0) {
            var tag_string = ArrayList(u8).init(self.allocator);
            defer tag_string.deinit();

            // Format the tags.
            for (self.inner.tags) |tag| {
                try std.fmt.format(tag_string.writer(), "+{s} ", .{tag});
            }

            // Remove the last space from the string because I'm too lazy to do a conditional above.
            _ = tag_string.pop();

            try std.fmt.format(writer, "{c} {s} {s} ({s})\n", .{
                self.inner.group,
                self.inner.description,
                tag_string.items,
                self.hash,
            });
        } else {
            try std.fmt.format(writer, "{c} {s} ({s})\n", .{
                self.inner.group,
                self.inner.description,
                self.hash,
            });
        }
        return contents_to_write.toOwnedSlice();
    }
};

/// Get the tags out of a Todo.
/// # Notes
/// - *NOT* for `TodoInner`.
pub fn containsTag(td: anytype, tag: []const u8) bool {
    const result = blk: {
        for (td.inner.tags) |todo_tag| {
            if (std.mem.eql(u8, todo_tag, tag))
                break :blk true;
        }
        break :blk false;
    };

    return result;
}

/// For use in creating a todo when it's already written into a todo file.
/// This is because we don't need to do allocations for the hash etc.
pub const StaticTodo = struct {
    inner: TodoInner,
    hash: []const u8,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(line: []const u8, allocator: std.mem.Allocator) !Self {
        if (line.len == 0)
            return Errors.EmptyLineError;

        const group: u8 = line[0];
        var description: []const u8 = undefined;
        var tags = ArrayList([]const u8).init(allocator);

        const first_tag_index = std.mem.indexOfScalar(u8, line, '+') orelse line.len;
        const description_start_index = 2; // 0 is group char, 1 is a space.
        const hash_start_index = std.mem.lastIndexOfScalar(u8, line, '(');
        const hash_end_index = std.mem.lastIndexOfScalar(u8, line, ')');

        if (hash_start_index == null or hash_end_index == null)
            return error.InvalidFormat;

        const hash = line[hash_start_index.? + 1 .. hash_end_index.?];

        if (first_tag_index < line.len) {
            description = line[description_start_index .. first_tag_index - 1];
            _ = try generateTags(line, first_tag_index, line.len, &tags);
        } else {
            description = line[description_start_index .. hash_start_index.? - 1];
        }

        return .{
            .inner = TodoInner{
                .description = description,
                .group = group,
                .tags = try tags.toOwnedSlice(),
            },
            .allocator = allocator,
            .hash = hash,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.inner.tags);
    }
};

test "Can't make an empty Todo" {
    try t.expectError(Errors.EmptyLineError, Todo.init("", t.allocator));
}

test "Can't have multiple groups in a Todo" {
    try t.expectError(Errors.FoundMultipleGroups, Todo.init("Hi mom! &A &B", t.allocator));
}

test "Single Group Todo" {
    const td = try Todo.init("Hello World! &A", t.allocator);
    defer td.deinit();

    try t.expectEqualStrings("Hello World!", td.inner.description);
    try t.expectEqual(td.inner.group, 'A');
}

test "Make a Todo" {
    var td = try Todo.init("Hi mom! +Newbie &A", t.allocator);
    defer td.deinit();

    try t.expectEqualStrings("Hi mom!", td.inner.description);
    try t.expect(td.inner.group == 'A');
    const expected_tags = &[_][]const u8{"Newbie"};
    try t.expectEqualStrings("ea7e8167ce8b6ad93d43ac5aa869a920", td.hash);

    for (expected_tags, td.inner.tags) |expected, actual| {
        try t.expectEqualSlices(u8, expected, actual);
    }
}

test "Check formatting" {
    const line = "Hi mom! #Newbie +Tag &A";

    var td = try Todo.init(line, t.allocator);
    defer td.deinit();

    const expected_tags = [_][]const u8{ "Newbie", "Tag" };

    for (expected_tags, td.inner.tags) |e, a| {
        try t.expectEqualStrings(e, a);
    }

    const expected_format = "A Hi mom! +Newbie +Tag (ea7e8167ce8b6ad93d43ac5aa869a920)\n";

    const actual_format = try td.formatToStringAlloc();
    defer t.allocator.free(actual_format);

    try t.expectEqualStrings(expected_format, actual_format);
}

test "Reconstruct from a formatted line" {
    const line = "B All your todo are belong to us. +1337 (abc123)";

    const todo = try StaticTodo.init(line, t.allocator);
    defer todo.deinit();

    try t.expect(todo.inner.group == 'B');
    try t.expectEqualStrings("All your todo are belong to us.", todo.inner.description);
    try t.expectEqualStrings("abc123", todo.hash);
}

test "Mix of # and + in tags" {
    const input = "Hi mom! #A +B";
    var taglist = ArrayList([]const u8).init(t.allocator);
    defer taglist.deinit();

    const expected = [_][]const u8{ "A", "B" };

    _ = try generateTags(input, 8, input.len, &taglist);

    for (expected, taglist.items) |e, a| {
        try t.expectEqualStrings(e, a);
    }
}

test "Generating a hash" {
    const actual = try generateTodoHashAlloc("Hi mom!", t.allocator);
    defer t.allocator.free(actual);
    try t.expectEqualStrings("ea7e8167ce8b6ad93d43ac5aa869a920", actual);
}

test "Trying to write a bad todo." {
    try t.expectError(error.IncorrectFormat, Todo.init("Hello World! &A +Newbie", t.allocator));
}
