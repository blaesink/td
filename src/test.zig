test {
    const manager = @import("manager.zig");
    _ = @import("todo.zig");
    _ = manager.TestingTodo;
}
