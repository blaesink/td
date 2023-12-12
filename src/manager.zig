const std = @import("std");
const builtin = @import("builtin");
const lib_todo = @import("todo.zig");
const parser = @import("parser.zig");

const fs = std.fs;
const t = std.testing;
const Todo = lib_todo.Todo;
const StaticTodo = lib_todo.StaticTodo;
const ArrayList = std.ArrayList;
const Parser = parser.Parser;

const TD_HOME_DIR: []const u8 = ".td";

const Commands = enum {
    add,
    help,
    ls,
    remove,
    rm,
};

/// Removes the todo from the file.
/// TODO: This uses an ArrayList to track and remove lines. May be ineffecient.
fn removeTodo(todo_file: fs.File, todo_hash: []const u8, allocator: std.mem.Allocator) !void {

    // Go to the beginning.
    try todo_file.seekTo(0);
    const file_contents = try todo_file.readToEndAlloc(allocator, 4096);
    defer allocator.free(file_contents);

    var lines_to_write = ArrayList(u8).init(allocator);
    defer lines_to_write.deinit();

    var lines = splitLines(file_contents);

    while (lines.next()) |line| {
        if (!std.mem.containsAtLeast(u8, line, 1, todo_hash) and (line.len > 1)) {
            try std.fmt.format(lines_to_write.writer(), "{s}\n", .{line});
        }
    }

    // Politely go back to the start.
    try todo_file.seekTo(0);

    // "Truncate" the file so we can write the new contents.
    try todo_file.setEndPos(0);

    _ = try todo_file.write(lines_to_write.items);
}

fn addTodo(todo_file: fs.File, todo: Todo, allocator: std.mem.Allocator) !void {
    // TODO: check that we already have this file generated.
    if (try getTodoFromHash(todo_file, todo.hash, allocator) != null)
        return error.ExistingHashFound;

    // Go to the end of the file to start appending to.
    try todo_file.seekTo(try todo_file.getEndPos());

    const formatted_todo = try todo.formatToStringAlloc();
    defer allocator.free(formatted_todo);

    // Write to the file
    _ = try todo_file.write(formatted_todo);
}

fn readFileContentsToLinesAlloc(file_contents: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    var result_lines = ArrayList([]const u8).init(allocator);

    var lines_iterator = std.mem.splitScalar(u8, file_contents, '\n');

    while (lines_iterator.next()) |line| {
        if (line.len > 0)
            try result_lines.append(line);
    }

    return result_lines.toOwnedSlice();
}

// FIXME: this keeps the last line! Can we fix that or do we need to check it at runtime?
fn splitLines(file_contents: []const u8) std.mem.SplitIterator(u8, .scalar) {
    if (builtin.os.tag == .windows) {
        return splitLinesWindows(file_contents);
    }
    return splitLinesPosix(file_contents);
}

fn splitLinesWindows(file_contents: []const u8) std.mem.SplitIterator(u8, .scalar) {
    return std.mem.splitSequence(u8, file_contents, "\r\n");
}

fn splitLinesPosix(file_contents: []const u8) std.mem.SplitIterator(u8, .scalar) {
    return std.mem.splitScalar(u8, file_contents, '\n');
}

/// TODO: this is going to be really, really bad because it's linear search.
fn getTodoFromHash(todo_file: fs.File, todo_hash: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    // Read each line and see if the hash is there. Again, bad.

    // TODO: 4096 bytes isn't that big.
    const file_contents = try todo_file.readToEndAlloc(allocator, 4096);
    defer allocator.free(file_contents);

    var lines = splitLines(file_contents);

    while (lines.next()) |line| {
        if (std.mem.containsAtLeast(u8, line, 1, todo_hash)) {
            return todo_hash;
        }
    }
    return null;
}

fn getHomeDirAbsolute() ![]const u8 {
    return std.os.getenv("HOME") orelse {
        std.log.err("Can't find HOME directory, set it before installing!", .{});
        return error.CannotFindHomeDir;
    };
}

fn maybeGenerateConfigFile(allocator: std.mem.Allocator) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var choice: [1:0]u8 = undefined;

    try stdout.print("Would you like to generate a config file? (y/n): ", .{});
    _ = try stdin.read(&choice);

    if (choice[0] == 'y' or choice[0] == 'Y') {
        const home_dir_string = try getHomeDirAbsolute();
        const home_dir = try fs.openDirAbsolute(home_dir_string, .{});
        const td_config_dir_string = try fs.path.join(allocator, &[_][]const u8{ home_dir_string, ".config", "td" });
        defer allocator.free(td_config_dir_string);

        const td_config_dir = try home_dir.makeOpenPath(td_config_dir_string, .{});

        _ = try td_config_dir.createFile("config.txt", .{});
        try stdout.print("Created config file in {s}! \n", .{td_config_dir_string});
    }
}

/// Generates the todo file under `$HOME/.td/`.
fn generateTodoFile(home_path: []const u8) !void {
    const home_dir = try fs.openDirAbsolute(home_path, .{});

    const td_dir = try home_dir.makeOpenPath(TD_HOME_DIR, .{});
    _ = try td_dir.createFile("todo.txt", .{});
}

/// Filter through the todos and return those that match.
/// +<tag> checks to see if the tag is the same.
/// &<group> checks to see if the group is the same.
fn queryAndFilterTodosAlloc(todo_lines: [][]const u8, query: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    var criteria = try Parser.lexAndParseLineAlloc(query, allocator);
    defer allocator.free(criteria);

    var matches: ArrayList([]const u8) = ArrayList([]const u8).init(allocator);

    for (todo_lines) |line| {
        const todo = try StaticTodo.init(line, allocator);
        defer todo.deinit();

        var is_match = false;

        for (criteria) |criterion| {
            switch (criterion) {
                .Literal => |lit| is_match = std.mem.containsAtLeast(u8, todo.inner.description, 1, lit),
                .Group => |grp| is_match = todo.inner.group == grp,
                .Tag => |tag| is_match = lib_todo.containsTag(todo, tag),
                .@"and" => |a| is_match = blk: {
                    // Can never be two groups!
                    for (a.ops) |op| {
                        if (op == .tag) {
                            if (!lib_todo.containsTag(todo, op.tag))
                                break :blk false;
                        } else if (op == .group) {
                            if (todo.inner.group != op.group)
                                break :blk false;
                        }
                    }
                    break :blk true;
                },
                .@"or" => |o| is_match = blk: {
                    for (o.ops) |op| {
                        if (op == .tag and lib_todo.containsTag(todo, op.tag))
                            break :blk true;
                        if (op == .group and todo.inner.group == op.group)
                            break :blk true;
                    }
                    break :blk false;
                },
                .not => |n| is_match = blk: {
                    switch (n.right) {
                        .group => |grp| break :blk todo.inner.group != grp,
                        .tag => |tag| break :blk !lib_todo.containsTag(todo, tag),
                        else => unreachable,
                    }
                },
            }
        }

        if (is_match)
            try matches.append(line);
    }
    return try matches.toOwnedSlice();
}

pub fn evalCommand(command: []const u8, input: ?[]const u8, allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    const user_home_string = try getHomeDirAbsolute();
    const config_file_string = try fs.path.join(allocator, &[_][]const u8{ user_home_string, ".config", "td", "config.txt" });
    defer allocator.free(config_file_string);

    // TODO: this is just to check that we have a config file by the time we want to use it.
    fs.accessAbsolute(config_file_string, .{}) catch {
        try maybeGenerateConfigFile(allocator);
    };

    // Could free `config_file_string` right here.

    const todo_file_path = try fs.path.join(allocator, &[_][]const u8{ user_home_string, TD_HOME_DIR, "todo.txt" });
    defer allocator.free(todo_file_path);

    _ = fs.openFileAbsolute(todo_file_path, .{}) catch try generateTodoFile(user_home_string);

    const todo_file = try std.fs.openFileAbsolute(todo_file_path, .{ .mode = .read_write });
    defer todo_file.close();

    const cmd_to_enum = std.meta.stringToEnum(Commands, command) orelse {
        return error.UnknownCommand;
    };

    if (cmd_to_enum != .ls and input == null)
        return error.MissingArgument;

    // TODO: just assign this to a const w/ a block.
    switch (cmd_to_enum) {
        .add => {
            // Remove surrounding quotation marks.
            var td = try Todo.init(input.?[0..input.?.len], allocator);
            defer td.deinit();
            try addTodo(todo_file, td, allocator);
            try std.io.getStdOut().writer().print("{s}\n", .{td.hash});
        },
        .remove, .rm => {
            const maybe_todo_hash = try getTodoFromHash(todo_file, input.?, allocator);

            if (maybe_todo_hash) |hash| {
                try removeTodo(todo_file, hash, allocator);
                return;
            }
            return error.NoHashFound;
        },
        .ls => {
            const file_contents = try todo_file.readToEndAlloc(allocator, 4096);
            defer allocator.free(file_contents);

            if (input) |text| {
                const lines: [][]const u8 = try readFileContentsToLinesAlloc(file_contents, allocator);
                defer allocator.free(lines);

                const matching_todos = try queryAndFilterTodosAlloc(lines, text, allocator);
                defer allocator.free(matching_todos);

                for (matching_todos) |todo| {
                    try stdout.print("{s}\n", .{todo});
                }
            } else {
                try stdout.print("{s}", .{file_contents});
            }
        },
        .help => {
            try stdout.print("Help!\n", .{});
        },
    }
}

// ==Testing==
const testing_todo_file_path: []const u8 = "todo.txt";

pub const TestingTodo = struct {
    const Self = @This();

    /// Removes the test todo.txt file. Use at the end of every test in this struct!
    fn remove_test_file() !void {
        try fs.cwd().deleteFile(testing_todo_file_path);
    }

    fn create_test_file() !fs.File {
        return try fs.cwd().createFile(testing_todo_file_path, .{});
    }

    test "Add todo to test file" {
        _ = try std.fs.cwd().createFile(testing_todo_file_path, .{});

        const todo_file = try std.fs.cwd().openFile("todo.txt", .{ .mode = .read_write });
        defer todo_file.close();

        var td = try Todo.init("Hello World!", t.allocator);
        defer td.deinit();

        try addTodo(todo_file, td, t.allocator);
        try Self.remove_test_file();
    }

    test "Remove todo from test file" {
        _ = try std.fs.cwd().createFile(testing_todo_file_path, .{});

        const todo_file = try std.fs.cwd().openFile("todo.txt", .{ .mode = .read_write });
        defer todo_file.close();

        var td = try Todo.init("Hello World!", t.allocator);
        defer td.deinit();

        try addTodo(todo_file, td, t.allocator);
        _ = try removeTodo(todo_file, td.hash, t.allocator);

        const file_contents = try todo_file.readToEndAlloc(t.allocator, 4096);
        defer t.allocator.free(file_contents);

        // Should be totally empty.
        try std.testing.expectEqualSlices(u8, "", file_contents);

        try Self.remove_test_file();
    }
};

pub const TestQueries = struct {
    test "A simple query" {
        const query = "&B";

        const fake_todos = "B All your todo are belong to us. (abc123)\n";

        const lines = try readFileContentsToLinesAlloc(fake_todos, t.allocator);
        defer t.allocator.free(lines);

        const result = try queryAndFilterTodosAlloc(lines, query, t.allocator);
        defer t.allocator.free(result);

        try t.expectEqual(@as(usize, 1), result.len);
    }

    test "Exclusionary queries" {
        {
            const fake_todos = "B All your todo are belong to us. (abc123)\n";

            const lines = try readFileContentsToLinesAlloc(fake_todos, t.allocator);
            defer t.allocator.free(lines);

            const result = try queryAndFilterTodosAlloc(lines, "not &B", t.allocator);
            defer t.allocator.free(result);

            try t.expectEqual(@as(usize, 0), result.len);
        }
    }
};
