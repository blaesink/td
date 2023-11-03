const manager = @import("manager.zig");
test {
    _ = @import("todo.zig");
    _ = manager.TestingTodo;
}
