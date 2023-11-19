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

const OpType = enum {
    @"and",
    @"or",
    not,
};

const Lexeme = struct {
    item: union(enum) {
        op: OpType,
        ident: []const u8,
    },
};

const OperationPhrase = struct {
    type: OpType,
    arguments: []const Lexeme,
};

fn wordToLexeme(word: []const u8) Lexeme {
    // If null at the end, then it's .ident.
    var node_type: ?OpType = null;

    // NOTE: this requires per-character scanning which isn't implemented.
    if (word.len == 0) {
        node_type = switch (word[0]) {
            '&' => .@"and",
            '|' => .@"or",
            '!' => .not,
            else => null,
        };
    } else {
        node_type = std.meta.stringToEnum(OpType, word);
    }

    if (node_type != null)
        return Lexeme{ .item = .{ .op = node_type.? } };

    return Lexeme{ .item = .{ .ident = word } };
}

/// TODO: per-character scanning.
fn lexAlloc(input: []const u8, allocator: std.mem.Allocator) ![]Lexeme {
    var tokens = std.ArrayList(Lexeme).init(allocator);

    var token_iterator = std.mem.splitScalar(u8, input, ' ');

    while (token_iterator.next()) |word| {
        try tokens.append(wordToLexeme(word));
    }

    return tokens.toOwnedSlice();
}

fn parseAlloc(input: []const u8, allocator: std.mem.Allocator) ![]OperationPhrase {
    var phrases = std.ArrayList(OperationPhrase).init(allocator);

    const lexemes = try lexAlloc(input, allocator);
    defer allocator.free(lexemes);

    var previous: ?Lexeme = null;
    _ = previous;
    var next: ?Lexeme = null;
    _ = next;

    // TODO: build the tree
    for (lexemes, 0..) |lex, i| {
        _ = lex;
        // Can't look out of bounds!
        if (i >= lexemes.len) break;

        switch (lexemes[i + 1]) {
            .ident => continue,
        }
    }
    return phrases.toOwnedSlice();
}

test "Lex a simple query" {
    const input = "&A and &B";
    const expected = [_]Lexeme{
        Lexeme{ .item = .{ .ident = "&A" } },
        Lexeme{ .item = .{ .op = .@"and" } },
        Lexeme{ .item = .{ .ident = "&B" } },
    };

    const actual = try lexAlloc(input, t.allocator);
    defer t.allocator.free(actual);

    // Can't use expectEqualSlices here because of tagged unions in the structs.
    for (expected, actual) |e, a| {
        try t.expectEqualDeep(e, a);
    }
}

test "Parse a simple query" {
    const input = "&A and &B";

    const expected = [_]OperationPhrase{
        OperationPhrase{
            .type = .@"and",
            .arguments = &[_]Lexeme{
                Lexeme{ .item = .{ .ident = "&A" } },
                Lexeme{ .item = .{ .ident = "&B" } },
            },
        },
    };

    const actual = try parseAlloc(input, t.allocator);
    defer t.allocator.free(actual);

    try t.expect(actual.len == 1);
    try t.expectEqualDeep(expected[0], actual[0]);
}
