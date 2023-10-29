const std = @import("std");
const lib_todo = @import("todo.zig");
const Todo = lib_todo.Todo;
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // const allocator = gpa.allocator();
    // const td = try Todo.from_line("Hello! +World", allocator);

    // print("{s}, {any}", .{ td.description, td.tags });
    const text = "Hello! +World &G";

    var it = std.mem.splitScalar(u8, text, '+');

    while (it.next()) |item| {
        print("{s}\n", .{item});
    }
}
