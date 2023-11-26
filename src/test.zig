const manager = @import("manager.zig");

test {
    _ = @import("parser.zig");
    _ = @import("lexer.zig");
    _ = @import("todo.zig");
    _ = manager.TestingTodo;
    _ = manager.TestQueries;
}
