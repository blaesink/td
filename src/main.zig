const std = @import("std");
const lib_todo = @import("todo.zig");
const Todo = lib_todo.Todo;
const print = std.debug.print;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var input_buffer: [1024]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    const allocator = arena.allocator();

    while (true) {
        try stdout.print("Enter the description: ", .{});

        _ = try stdin.readUntilDelimiter(&input_buffer, '\n');

        // TODO: (hahaha), this is a bit rough to read.
        var td = Todo.fromLine(&input_buffer, allocator) catch |err| {
            switch (err) {
                lib_todo.Errors.FoundMultipleGroups => {
                    try stdout.print("Can't have multiple groups!\n", .{});
                    return;
                },
                else => continue,
            }
        };
        defer td.deinit();

        try stdout.print("{s}\n", .{td.description.items});
    }
}
