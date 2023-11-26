const std = @import("std");
const lexer = @import("lexer.zig");
const Token = lexer.Token;

const Parser = struct {
    const Self = @This();

    tokens: []Token,
    position: usize = 0,
    read_position: usize = 1,

    // NOTE: previous_token could be `usize` for index.
    //       but it's a needless optimization ATM.
    previous_token: Token = undefined,
    current_token: Token,

    pub fn init(tokens: []Token) Self {
        return .{
            .tokens = tokens,
            .current_token = tokens[0],
        };
    }

    pub fn peekToken(self: Self) ?Token {
        if (self.read_position >= self.tokens.len)
            return null;

        return self.tokens[self.read_position];
    }

    pub fn advanceToken(self: *Self) !void {
        if (self.read_position >= self.tokens.len)
            return error.OutOfBounds;

        self.previous_token = self.current_token;
        self.position = self.read_position;
        self.current_token = self.tokens[self.position];
        self.read_position += 1;
    }

    fn @"and"(self: *Self, left: Token, right: Token) !void {
        _ = right;
        _ = left;
        _ = self;
    }

    fn @"or"(self: *Self, left: Token, right: Token) !void {
        _ = right;
        _ = left;
        _ = self;
    }

    fn not(self: *Self, right: Token) !void {
        _ = right;
        _ = self;
    }
};
