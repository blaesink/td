const std = @import("std");
const fs = std.fs;
const builtin = @import("builtin");
const t = std.testing;
const lib_todo = @import("todo.zig");
const Todo = lib_todo.Todo;
const md5 = std.crypto.hash.Md5;

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
fn removeTodo(todo_file_path: []const u8, todo_hash: []const u8) !void {
    _ = todo_hash;
    _ = todo_file_path;
}

fn addTodoAlloc(todo_file: fs.File, todo: Todo, allocator: std.mem.Allocator) ![32]u8 {
    const todo_hash = try generateTodoHash(todo.description.items);

    // TODO: check that we already have this file generated.
    if (try getTodoFromHashAlloc(todo_file, &todo_hash, allocator) != null) {
        return error.ExistingHashFound;
    }

    // Go to the end of the file to start appending to.
    try todo_file.seekTo(try todo_file.getEndPos());

    var contents_to_write = std.ArrayList(u8).init(allocator);
    defer contents_to_write.deinit();

    try std.fmt.format(contents_to_write.writer(), "({s}) {s}\n", .{ todo_hash, todo.description.items });

    // Write to the file
    _ = try todo_file.write(contents_to_write.items);

    return todo_hash;
}

fn getFileLines(file_contents: []const u8) std.mem.SplitIterator(u8, .scalar) {
    if (builtin.os.tag == .windows) {
        return getFileLinesWindows(file_contents);
    } else {
        return getFileLinesPosix(file_contents);
    }
}

fn getFileLinesWindows(file_contents: []const u8) std.mem.SplitIterator(u8, .scalar) {
    return std.mem.splitSequence(u8, file_contents, "\r\n");
}

fn getFileLinesPosix(file_contents: []const u8) std.mem.SplitIterator(u8, .scalar) {
    return std.mem.splitScalar(u8, file_contents, '\n');
}

/// TODO: this is going to be really, really bad because it's linear search.
fn getTodoFromHashAlloc(todo_file: fs.File, todo_hash: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    // Read each line and see if the hash is there. Again, bad.

    // TODO: 4096 bytes isn't that big.
    const file_contents = try todo_file.readToEndAlloc(allocator, 4096);
    defer allocator.free(file_contents);

    var lines = getFileLines(file_contents);

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

/// Generate the todo file under `$HOME/td/`.
fn generateTodoFile(home_path: []const u8) !void {
    const home_dir = try fs.openDirAbsolute(home_path, .{});

    const td_dir = try home_dir.makeOpenPath("td", .{});
    _ = try td_dir.createFile("todo.txt", .{});
}

pub fn evalCommandAlloc(command: []const u8, input: ?[]const u8, allocator: std.mem.Allocator) !void {
    const user_home_string = try getHomeDirAbsolute();
    const config_file_string = try fs.path.join(allocator, &[_][]const u8{ user_home_string, ".config", "td", "config.txt" });
    defer allocator.free(config_file_string);

    try std.io.getStdOut().writer().print("{s}\n", .{config_file_string});

    fs.accessAbsolute(config_file_string, .{}) catch {
        try maybeGenerateConfigFileAlloc(allocator);
    };

    const todo_file_path = try fs.path.join(allocator, &[_][]const u8{ user_home_string, "td", "todo.txt" });
    defer allocator.free(todo_file_path);

    _ = fs.openFileAbsolute(todo_file_path, .{}) catch try generateTodoFile(user_home_string);

    const todo_file = try std.fs.openFileAbsolute(todo_file_path, .{ .mode = .read_write });

    // TODO: make this an enum switch.
    if (std.mem.eql(u8, command, "add")) {
        var td = try Todo.fromLine(input.?[0..input.?.len], allocator);
        defer td.deinit();
        const id = try addTodoAlloc(todo_file, td, allocator);
        std.debug.print("{s}\n", .{id});
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
};
