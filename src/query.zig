// This module generates query ASTs.
//
// not &A and not &B
//  |   |  |   |   |
//  op  |  op  op  |
//    ident        ident
//
//
//        S
//      /   \
//     OP    OP
//     /\    / \
//   op  i   op \
//   |   |   |   \
//  not  &A and   \
//                OP
//                /\
//              op  i
//              |   |
//             not  &B

const std = @import("std");
const t = std.testing;
const expect = std.testing.expect;

const Token = union(enum) {
    ident: []const u8,

    @"and",
    @"or",
    not,
    eof,
    illegal,

    pub fn match(word: []const u8) ?Token {
        const map = std.ComptimeStringMap(Token, .{
            .{ "and", .@"and" },
            .{ "or", .@"or" },
            .{ "not", .not },
        });
        return map.get(word);
    }
};

const Lexer = struct {
    const Self = @This();

    query: []const u8,
    position: usize = 0, // where we are now
    read_position: usize = 1, // for "peeking"
    current_char: u8, // current char

    pub fn init(query: []const u8) Self {
        return .{
            .query = query,
            .current_char = query[0],
        };
    }

    /// Skips all whitespace until a non whitespace character is hit.
    fn skipWhitespace(self: *Self) void {
        while (std.ascii.isWhitespace(self.current_char)) {
            self.advanceChar();
        }
    }

    fn peek(self: Self) u8 {
        if (self.read_position >= self.query.len) return 0;

        return self.query[self.read_position];
    }

    fn advanceChar(self: *Self) void {
        if (self.read_position >= self.query.len) {
            self.current_char = 0;
        } else {
            self.current_char = self.query[self.read_position];
        }

        self.position = self.read_position;
        self.read_position += 1;
    }

    /// Scan forward until we can no longer build a word out of alphanumeric characters.
    fn readWord(self: *Self) []const u8 {
        const start_position = self.position;
        while (std.ascii.isAlphanumeric(self.current_char)) {
            self.advanceChar();
        }

        return self.query[start_position..self.position];
    }

    fn nextToken(self: *Self) Token {
        self.skipWhitespace();

        const token: Token = switch (self.current_char) {
            '&', '+' => {
                switch (self.peek()) {
                    'a'...'z', 'A'...'Z' => {
                        self.advanceChar();
                        const word = self.readWord();

                        return .{ .ident = word };
                    },
                    else => return .illegal,
                }
            },
            'a'...'z', 'A'...'Z' => {
                const word = self.readWord();

                if (Token.match(word)) |tok| return tok;

                return .{ .ident = word };
            },
            else => .illegal,
        };
        return token;
    }
};

test "Test Peeking" {
    {
        var lex = Lexer.init("ABCDE");

        try t.expect(lex.peek() == 'B');
        lex.advanceChar();
        try t.expect(lex.peek() == 'C');
    }
    {
        var lex = Lexer.init("ABC");
        lex.advanceChar();
        lex.advanceChar();
        try t.expect(lex.peek() == 0);
    }
}

test "Collecting a word" {
    var lex = Lexer.init("Hi mom!");

    try t.expectEqualStrings("Hi", lex.readWord());
    lex.skipWhitespace();
    try t.expectEqualStrings("mom", lex.readWord());
}

test "Bad queries" {
    {
        var lex = Lexer.init("&&");
        try t.expectEqualDeep(Token.illegal, lex.nextToken());
    }
    {
        var lex = Lexer.init("&+");
        try t.expectEqualDeep(Token.illegal, lex.nextToken());
    }
    {
        var lex = Lexer.init("& ");
        try t.expectEqualDeep(Token.illegal, lex.nextToken());
    }
}

test "Two word queries" {
    var lex = Lexer.init("not &A");

    try t.expectEqualDeep(Token.not, lex.nextToken());
    try t.expectEqualDeep(.{ .ident = "&A" }, lex.nextToken());
}

test "Lex a simple query" {
    {
        var lex = Lexer.init("&A and &B");

        try t.expectEqualDeep(.{ .ident = "&A" }, lex.nextToken());
        try t.expectEqualDeep(Token.@"and", lex.nextToken());
        try t.expectEqualDeep(.{ .ident = "&B" }, lex.nextToken());
    }
    {
        var lex = Lexer.init("&A or &B");

        try t.expectEqualDeep(.{ .ident = "&A" }, lex.nextToken());
        try t.expectEqualDeep(Token.@"or", lex.nextToken());
        try t.expectEqualDeep(.{ .ident = "&B" }, lex.nextToken());
    }
}
