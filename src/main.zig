const std = @import("std");
const lib_todo = @import("todo.zig");
const Todo = lib_todo.Todo;
const manager = @import("manager.zig");
const print = std.debug.print;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    // var input_buffer: [1024]u8 = undefined;
    // _ = input_buffer;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip the first arg (path of the executable).
    _ = args.skip();

    // There must be a command.
    const command = args.next().?;

    // The rest is optional depending on the command.
    const todo_input = args.next();

    manager.evalCommand(command, todo_input, allocator) catch |err| {
        switch (err) {
            error.EmptyLineError => {
                try stdout.print("Can't have a todo with an empty line!\n\"{?s}\"\n", .{todo_input});
            },
            error.ExistingHashFound => {
                try stdout.print("There's already a todo that matches this description: \"{s}\"\n", .{todo_input.?});
            },
            error.NoHashFound => {
                try stdout.print("Couldn't find a todo with that id!\n", .{});
            },
            error.UnknownCommand => {
                try stdout.print("Can't handle supplied command: `{s}`!\n", .{command});
            },
            error.MissingArgument => {
                try stdout.print("This command needs more context!\n", .{});
            },
            else => {
                @panic("Unknown error!");
            },
        }
        return;
    };
}
