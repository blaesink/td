const manager = @import("manager.zig");

test {
    _ = @import("query.zig");
    _ = @import("todo.zig");
    _ = manager.TestingTodo;
    _ = manager.TestQueries;
}
