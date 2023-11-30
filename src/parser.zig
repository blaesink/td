const std = @import("std");
const t = std.testing;
const lexer = @import("lexer.zig");
const Token = lexer.Token;

const And = struct {
    left: Token,
    right: Token,
};

const Or = struct {
    left: Token,
    right: Token,
};

const Not = struct {
    right: Token,
};

const Node = union(enum) {
    @"and": And,
    @"or": Or,
    not: Not,
};

/// Rules
/// ===
/// S  -> (I) VP+
/// VP -> V I
/// VP -> I V I
/// VP -> V
const Parser = struct {
    const Self = @This();

    tokens: []Token,
    allocator: std.mem.Allocator,
    position: usize = 0,
    read_position: usize = 1,

    // NOTE: previous_token could be `usize` for index.
    //       but it's a needless optimization ATM.
    previous_token: Token = undefined,
    current_token: Token,

    pub fn init(tokens: []Token, allocator: std.mem.Allocator) Self {
        return .{
            .tokens = tokens,
            .allocator = allocator,
            .current_token = tokens[0],
        };
    }

    pub fn peekToken(self: Self) Token {
        if (self.read_position >= self.tokens.len)
            return .eof;

        return self.tokens[self.read_position];
    }

    pub fn advanceToken(self: *Self) void {
        if (self.read_position >= self.tokens.len) {
            return;
        }

        self.previous_token = self.current_token;
        self.position = self.read_position;
        self.current_token = self.tokens[self.position];
        self.read_position += 1;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.tokens);
    }

    pub fn parseAlloc(self: *Self) ![]Node {
        var nodes = std.ArrayList(Node).init(self.allocator);
        errdefer nodes.deinit();

        while (self.current_token != .eof) {
            const this_node = switch (self.current_token) {
                // Just some generic identifier.
                .tag, .group => blk: {
                    const lhs = self.current_token;
                    const maybe_operator_token = self.peekToken();

                    if (maybe_operator_token == .@"and" or maybe_operator_token == .@"or") {
                        self.advanceToken();

                        const rhs = self.peekToken();

                        if (rhs == .group and lhs == .group and maybe_operator_token == .@"and")
                            return error.IllegalFormat;

                        if (rhs == .tag or rhs == .group) {
                            if (maybe_operator_token == .@"and")
                                break :blk Node{ .@"and" = .{ .left = lhs, .right = rhs } };
                            break :blk Node{ .@"or" = .{ .left = lhs, .right = rhs } };
                        }
                    }
                },
                .not => blk: {
                    const rhs = self.peekToken();
                    switch (rhs) {
                        .tag, .group => break :blk Node{ .not = .{ .right = rhs } },
                        else => return error.IllegalFormat,
                    }
                },
                else => return error.IllegalFormat,
            };
            self.advanceToken();
            try nodes.append(this_node);
        }

        return nodes.toOwnedSlice();
    }
};

test "Checking a few tokens" {
    var l = lexer.Lexer.init("Hi Mom");
    var p = Parser.init(try l.collectAlloc(t.allocator), t.allocator);
    defer p.deinit();

    try t.expectEqualDeep(.{ .ident = "Hi" }, p.peekToken());
    p.advanceToken();
    try t.expectEqualDeep(.{ .ident = "Mom" }, p.peekToken());
    p.advanceToken();
    try t.expectEqual(Token.eof, p.peekToken());
}

test "Going out of bounds" {
    var l = lexer.Lexer.init("One Two");
    var p = Parser.init(try l.collectAlloc(t.allocator), t.allocator);
    defer p.deinit();

    // Go way out of bounds.
    for (0..10) |_| {
        p.advanceToken();
    }

    try t.expectEqual(Token.eof, p.current_token);
}

test "Parse a simple query" {
    {
        var l = lexer.Lexer.init("+A and +B");
        var p = Parser.init(try l.collectAlloc(t.allocator), t.allocator);
        defer p.deinit();

        const expected = .{ .@"and" = .{ .left = .{ .tag = "A" }, .right = .{ .tag = "B" } } };

        const actual = try p.parseAlloc();
        defer t.allocator.free(actual);
        try t.expectEqualDeep(expected, actual[0]);
    }
    {
        var l = lexer.Lexer.init("&A or &B");
        var p = Parser.init(try l.collectAlloc(t.allocator), t.allocator);
        defer p.deinit();

        const expected = [_]Node{
            .{ .@"or" = .{ .left = .{ .group = "A" }, .right = .{ .group = "B" } } },
        };

        const actual = try p.parseAlloc();
        defer t.allocator.free(actual);
        try t.expectEqualDeep(expected[0], actual[0]);
    }
}

test "Bad queries" {
    {
        var l = lexer.Lexer.init("not not");
        var p = Parser.init(try l.collectAlloc(t.allocator), t.allocator);
        defer p.deinit();

        try t.expectError(error.IllegalFormat, p.parseAlloc());
    }
    {
        var l = lexer.Lexer.init("and and");
        var p = Parser.init(try l.collectAlloc(t.allocator), t.allocator);
        defer p.deinit();

        try t.expectError(error.IllegalFormat, p.parseAlloc());
    }
    {
        var l = lexer.Lexer.init("&A and &B");
        var p = Parser.init(try l.collectAlloc(t.allocator), t.allocator);
        defer p.deinit();

        try t.expectError(error.IllegalFormat, p.parseAlloc());
    }
}
