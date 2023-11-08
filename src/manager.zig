const std = @import("std");
const fs = std.fs;
const builtin = @import("builtin");
const t = std.testing;
const lib_todo = @import("todo.zig");
const Todo = lib_todo.Todo;
const md5 = std.crypto.hash.Md5;
const ArrayList = std.ArrayList;

const TD_HOME_DIR: []const u8 = ".td";

const Commands = enum {
    add,
    help,
    ls,
    remove,
    rm,
};

/// Generates a string hash from the `Todo`'s description.
/// Returns the generated hash.
fn generateTodoHash(todo_description: []const u8) ![32]u8 {
    var hash_buf: [md5.digest_length]u8 = undefined;
    var output: [32]u8 = undefined;

    md5.hash(todo_description, &hash_buf, .{});

    _ = try std.fmt.bufPrint(&output, "{s}", .{std.fmt.fmtSliceHexLower(&hash_buf)});

    return output;
}

/// Removes the todo from the file.
/// TODO: This uses an ArrayList to track and remove lines. May be ineffecient.
fn removeTodoAlloc(todo_file: fs.File, todo_hash: []const u8, allocator: std.mem.Allocator) !void {

    // Go to the beginning.
    try todo_file.seekTo(0);
    const file_contents = try todo_file.readToEndAlloc(allocator, 4096);
    defer allocator.free(file_contents);

    var lines_to_write = ArrayList(u8).init(allocator);
    defer lines_to_write.deinit();

    var lines = splitLines(file_contents);

    while (lines.next()) |line| {
        if (!std.mem.containsAtLeast(u8, line, 1, todo_hash)) {
            try lines_to_write.appendSlice(line);
        }
    }

    // Politely go back to the start.
    try todo_file.seekTo(0);

    // "Truncate" the file so we can write the new contents.
    try todo_file.setEndPos(0);

    _ = try todo_file.write(lines_to_write.items);
}

fn addTodoAlloc(todo_file: fs.File, todo: Todo, allocator: std.mem.Allocator) ![32]u8 {
    const todo_hash = try generateTodoHash(todo.description.items);

    // TODO: check that we already have this file generated.
    if (try getTodoFromHashAlloc(todo_file, &todo_hash, allocator) != null) {
        return error.ExistingHashFound;
    }

    // Go to the end of the file to start appending to.
    try todo_file.seekTo(try todo_file.getEndPos());

    var contents_to_write = ArrayList(u8).init(allocator);
    defer contents_to_write.deinit();

    if (todo.tags.items.len > 0) {
        try std.fmt.format(contents_to_write.writer(), "{c} {s} {s} ({s})\n", .{ todo.group, todo.description.items, todo.tags.items, todo_hash });
    } else {
        try std.fmt.format(contents_to_write.writer(), "{c} {s} ({s})\n", .{ todo.group, todo.description.items, todo_hash });
    }

    // Write to the file
    _ = try todo_file.write(contents_to_write.items);

    return todo_hash;
}

fn readFileContentsToLinesAlloc(file_contents: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    var result_lines = ArrayList([]const u8).init(allocator);
    defer result_lines.deinit();

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
fn getTodoFromHashAlloc(todo_file: fs.File, todo_hash: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
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

fn maybeGenerateConfigFileAlloc(allocator: std.mem.Allocator) !void {
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

// fn parseQuery(query: []const u8) type {
//     _ = query;
//     return .{};
// }

/// Filter through the todos and return those that match.
/// +<tag> checks to see if the tag is the same.
/// &<group> checks to see if the group is the same.
fn queryAndFilterTodosAlloc(todo_lines: [][]const u8, query: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // BUG: this is technically a bug: a Todo can be made without a description.
    var parsed_query = try Todo.fromLineNoDescription(query, allocator);
    defer parsed_query.deinit();

    var matches = ArrayList(Todo).init(allocator);
    defer matches.deinit();

    var result = ArrayList(u8).init(allocator);
    defer result.deinit();

    for (todo_lines) |line| {
        var todo = try Todo.fromFormattedLine(line, allocator);

        if (parsed_query.group != '-' and todo.group == parsed_query.group) {
            try matches.append(todo);
        }
    }

    return result.toOwnedSlice();
}

pub fn evalCommandAlloc(command: []const u8, input: ?[]const u8, allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    const user_home_string = try getHomeDirAbsolute();
    const config_file_string = try fs.path.join(allocator, &[_][]const u8{ user_home_string, ".config", "td", "config.txt" });
    defer allocator.free(config_file_string);

    // TODO: this is just to check that we have a config file by the time we want to use it.
    fs.accessAbsolute(config_file_string, .{}) catch {
        try maybeGenerateConfigFileAlloc(allocator);
    };

    // Could free `config_file_string` right here.

    const todo_file_path = try fs.path.join(allocator, &[_][]const u8{ user_home_string, TD_HOME_DIR, "todo.txt" });
    defer allocator.free(todo_file_path);

    _ = fs.openFileAbsolute(todo_file_path, .{}) catch try generateTodoFile(user_home_string);

    const todo_file = try std.fs.openFileAbsolute(todo_file_path, .{ .mode = .read_write });

    const cmd_to_enum = std.meta.stringToEnum(Commands, command) orelse {
        // try stdout.print("Invalid Command!\n", .{});
        return error.UnknownCommand;
    };

    switch (cmd_to_enum) {
        .add => {
            // Remove surrounding quotation marks.
            var td = try Todo.fromLine(input.?[0..input.?.len], allocator);
            defer td.deinit();
            const id = try addTodoAlloc(todo_file, td, allocator);
            std.debug.print("{s}\n", .{id});
        },
        .remove, .rm => {
            const maybe_todo_hash = try getTodoFromHashAlloc(todo_file, input.?, allocator);

            if (maybe_todo_hash) |hash| {
                try removeTodoAlloc(todo_file, hash, allocator);
                return;
            }
            return error.NoHashFound;
        },
        .ls => {
            const file_contents = try todo_file.readToEndAlloc(allocator, 4096);
            defer allocator.free(file_contents);

            if (input == null) {
                try stdout.print("{s}", .{file_contents});
            } else {
                const lines: [][]const u8 = try readFileContentsToLinesAlloc(file_contents, allocator);

                const matching_todos = try queryAndFilterTodosAlloc(lines, input.?, allocator);
                defer matching_todos.deinit();

                // TODO: print out these todos using the format in addTodo.

                for (matching_todos.items) |td| {
                    try stdout.print("{s}\n", .{td.description.items});
                }
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

        const added_todo_id = try addTodoAlloc(todo_file, td, t.allocator);

        try std.testing.expect(added_todo_id.len > 0);

        try Self.remove_test_file();
    }

    test "Remove todo from test file" {
        _ = try std.fs.cwd().createFile(testing_todo_file_path, .{});

        const todo_file = try std.fs.cwd().openFile("todo.txt", .{ .mode = .read_write });
        defer todo_file.close();

        var td = try Todo.fromLine("Hello World!", t.allocator);
        defer td.deinit();

        const added_todo_id = try addTodoAlloc(todo_file, td, t.allocator);
        _ = try removeTodoAlloc(todo_file, &added_todo_id, t.allocator);

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

        const fake_todos =
            \\B All your todo are belong to us. (abc123)
        ;

        const lines = try readFileContentsToLinesAlloc(fake_todos, t.allocator);

        const result = try queryAndFilterTodosAlloc(lines, query, t.allocator);

        try t.expect(std.mem.eql(u8, result, fake_todos));
    }
};
