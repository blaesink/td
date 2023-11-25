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

    /// Skips all whitespace until an alphanumeric character is hit.
    fn skipWhitespace(self: *Self) void {
        while (std.ascii.isWhitespace(self.current_char)) {
            self.next();
        }
    }

    fn peek(self: Self) u8 {
        if (self.read_position >= self.query.len) return 0;

        return self.query[self.read_position];
    }

    fn next(self: *Self) void {
        if (self.read_position >= self.query.len) {
            self.current_char = 0;
        } else {
            self.current_char = self.query[self.read_position];
        }

        self.position = self.read_position;
        self.read_position += 1;
    }

    /// Scan forward until we can no longer build a word.
    fn readWord(self: *Self) []const u8 {
        const start_position = self.position;
        while (std.ascii.isAlphanumeric(self.current_char)) {
            self.next();
        }

        return self.query[start_position..self.position];
    }

    fn nextToken(self: *Self) Token {
        self.skipWhitespace();

        const token: Token = switch (self.current_char) {
            'a'...'z', 'A'...'Z' => {
                const word = self.readWord();

                if (Token.match(word)) |tok|
                    return tok;

                return .{ .ident = word };
            },
            '!' => .not,
            else => .eof,
        };

        self.next();
        return token;
    }
};

test "Check a simple query" {
    var lex = Lexer.init("&A and &B");

    try t.expectEqualStrings("&A", lex.nextToken().ident);
    try t.expectEqualDeep(Token.not, lex.nextToken());
    try t.expectEqualStrings("&B", lex.nextToken().ident);
}
