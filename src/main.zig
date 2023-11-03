const std = @import("std");
const lib_todo = @import("todo.zig");
const Todo = lib_todo.Todo;
const manager = @import("manager.zig");
const print = std.debug.print;

pub fn main() !void {
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

    try manager.evalCommandAlloc(command, args.next(), allocator);
}
