const std = @import("std");
const builtin = @import("builtin");
const lib_todo = @import("todo.zig");
const fs = std.fs;
const t = std.testing;
const Todo = lib_todo.Todo;
const ArrayList = std.ArrayList;

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

fn addTodo(todo_file: fs.File, todo: Todo, allocator: std.mem.Allocator) ![]const u8 {
    // TODO: check that we already have this file generated.
    if (try getTodoFromHash(todo_file, todo.hash, allocator) != null) return error.ExistingHashFound;

    // Go to the end of the file to start appending to.
    try todo_file.seekTo(try todo_file.getEndPos());

    const formatted_todo = try todo.formatToStringAlloc();
    defer allocator.free(formatted_todo);

    // Write to the file
    _ = try todo_file.write(formatted_todo);

    return todo.hash;
}

fn readFileContentsToLinesAlloc(file_contents: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    var result_lines = ArrayList([]const u8).init(allocator);

    var lines_iterator = std.mem.splitScalar(u8, file_contents, '\n');

    while (lines_iterator.next()) |line| {
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
fn queryAndFilterTodosAlloc(todo_lines: [][]const u8, query: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var parsed_query = try Todo.fromLineNoDescription(query, allocator);
    defer parsed_query.deinit();

    var matches: ArrayList(u8) = ArrayList(u8).init(allocator);
    const match_writer = matches.writer();

    for (todo_lines[0 .. todo_lines.len - 1]) |line| {
        if (parsed_query.group != '-' and line[0] == parsed_query.group) {
            try std.fmt.format(match_writer, "{s}\n", .{line});
            continue;
        }

        const todo = try Todo.fromFormattedLine(line, allocator);
        defer todo.deinit();

        if (parsed_query.tags.items.len > 0 and todo.tags.items.len > 0) {
            for (parsed_query.tags.items) |tag| {
                for (todo.tags.items) |todo_tag| {
                    if (std.mem.eql(u8, tag, todo_tag)) {
                        try std.fmt.format(match_writer, "{s}\n", .{line});
                    }
                }
            }
        }
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

    if (cmd_to_enum != .ls and input == null) return error.MissingArgument;

    switch (cmd_to_enum) {
        .add => {
            // Remove surrounding quotation marks.
            var td = try Todo.fromLine(input.?[0..input.?.len], allocator);
            defer td.deinit();
            const id = try addTodo(todo_file, td, allocator);
            std.debug.print("{s}\n", .{id});
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

                try stdout.print("{s}", .{matching_todos});
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

        var td = try Todo.fromLine("Hello World!", t.allocator);
        defer td.deinit();

        const added_todo_id = try addTodo(todo_file, td, t.allocator);

        try std.testing.expect(added_todo_id.len > 0);

        try Self.remove_test_file();
    }

    test "Remove todo from test file" {
        _ = try std.fs.cwd().createFile(testing_todo_file_path, .{});

        const todo_file = try std.fs.cwd().openFile("todo.txt", .{ .mode = .read_write });
        defer todo_file.close();

        var td = try Todo.fromLine("Hello World!", t.allocator);
        defer td.deinit();

        const added_todo_id = try addTodo(todo_file, td, t.allocator);
        _ = try removeTodo(todo_file, added_todo_id, t.allocator);

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

        try t.expect(result.len > 0);

        try t.expectEqualStrings(fake_todos, result);
    }
};
