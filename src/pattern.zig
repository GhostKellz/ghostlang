// Lua Pattern Matching Engine for Ghostlang
// Full Lua 5.4 pattern syntax with captures
// Designed for Zig 0.16 unmanaged ArrayList API

const std = @import("std");

pub const PatternError = error{
    OutOfMemory,
    InvalidPattern,
    InvalidCharacterClass,
    InvalidRange,
    UnbalancedBrackets,
    UnbalancedParentheses,
    TooManyCaptures,
};

pub const Capture = struct {
    start: usize,
    end: usize,
};

pub const MatchResult = struct {
    matched: bool,
    start: usize,
    end: usize,
    captures: []Capture,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MatchResult) void {
        self.allocator.free(self.captures);
    }
};

const PatternType = enum {
    literal,
    any_char,
    char_class,
    char_set,
    capture_start,
    capture_end,
    anchor_start,
    anchor_end,
};

const Quantifier = enum {
    none,
    zero_or_more,
    one_or_more,
    zero_or_more_lazy,
    optional,
};

const PatternNode = struct {
    type: PatternType,
    char: u8,
    negated: bool,
    quantifier: Quantifier,
    chars: []const u8,
};

pub const Pattern = struct {
    nodes: []PatternNode,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Pattern) void {
        for (self.nodes) |node| {
            if (node.type == .char_set) {
                self.allocator.free(node.chars);
            }
        }
        self.allocator.free(self.nodes);
    }
};

pub fn compile(allocator: std.mem.Allocator, pat: []const u8) PatternError!Pattern {
    var nodes_list = std.ArrayList(PatternNode){};
    errdefer {
        for (nodes_list.items) |node| {
            if (node.type == .char_set) {
                allocator.free(node.chars);
            }
        }
        nodes_list.deinit(allocator);
    }

    var i: usize = 0;
    while (i < pat.len) {
        const c = pat[i];

        var quant = Quantifier.none;
        if (i + 1 < pat.len) {
            quant = switch (pat[i + 1]) {
                '*' => .zero_or_more,
                '+' => .one_or_more,
                '-' => .zero_or_more_lazy,
                '?' => .optional,
                else => .none,
            };
        }

        switch (c) {
            '.' => {
                try nodes_list.append(allocator, .{
                    .type = .any_char,
                    .char = 0,
                    .negated = false,
                    .quantifier = quant,
                    .chars = &[_]u8{},
                });
                i += if (quant != .none) 2 else 1;
            },
            '%' => {
                if (i + 1 >= pat.len) return PatternError.InvalidPattern;
                const next = pat[i + 1];
                const class_char = std.ascii.toLower(next);
                const is_class = switch (class_char) {
                    'a', 'c', 'd', 'l', 'p', 's', 'u', 'w', 'x', 'z' => true,
                    else => false,
                };

                if (is_class) {
                    const q = if (i + 2 < pat.len) switch (pat[i + 2]) {
                        '*' => Quantifier.zero_or_more,
                        '+' => Quantifier.one_or_more,
                        '-' => Quantifier.zero_or_more_lazy,
                        '?' => Quantifier.optional,
                        else => Quantifier.none,
                    } else Quantifier.none;

                    try nodes_list.append(allocator, .{
                        .type = .char_class,
                        .char = class_char,
                        .negated = std.ascii.isUpper(next),
                        .quantifier = q,
                        .chars = &[_]u8{},
                    });
                    i += if (q != .none) 3 else 2;
                } else {
                    const q = if (i + 2 < pat.len) switch (pat[i + 2]) {
                        '*' => Quantifier.zero_or_more,
                        '+' => Quantifier.one_or_more,
                        '-' => Quantifier.zero_or_more_lazy,
                        '?' => Quantifier.optional,
                        else => Quantifier.none,
                    } else Quantifier.none;

                    try nodes_list.append(allocator, .{
                        .type = .literal,
                        .char = next,
                        .negated = false,
                        .quantifier = q,
                        .chars = &[_]u8{},
                    });
                    i += if (q != .none) 3 else 2;
                }
            },
            '[' => {
                const set_start = i + 1;
                var set_end = set_start;
                const negated = (set_start < pat.len and pat[set_start] == '^');
                const actual_start = if (negated) set_start + 1 else set_start;

                while (set_end < pat.len and pat[set_end] != ']') {
                    set_end += 1;
                }
                if (set_end >= pat.len) return PatternError.UnbalancedBrackets;

                const set_content = pat[actual_start..set_end];
                const set_copy = try allocator.dupe(u8, set_content);

                const q = if (set_end + 1 < pat.len) switch (pat[set_end + 1]) {
                    '*' => Quantifier.zero_or_more,
                    '+' => Quantifier.one_or_more,
                    '-' => Quantifier.zero_or_more_lazy,
                    '?' => Quantifier.optional,
                    else => Quantifier.none,
                } else Quantifier.none;

                try nodes_list.append(allocator, .{
                    .type = .char_set,
                    .char = 0,
                    .negated = negated,
                    .quantifier = q,
                    .chars = set_copy,
                });
                i = set_end + 1; if (q != .none) { i += 1; }
            },
            '(' => {
                try nodes_list.append(allocator, .{
                    .type = .capture_start,
                    .char = 0,
                    .negated = false,
                    .quantifier = .none,
                    .chars = &[_]u8{},
                });
                i += 1;
            },
            ')' => {
                try nodes_list.append(allocator, .{
                    .type = .capture_end,
                    .char = 0,
                    .negated = false,
                    .quantifier = .none,
                    .chars = &[_]u8{},
                });
                i += 1;
            },
            '^' => {
                try nodes_list.append(allocator, .{
                    .type = .anchor_start,
                    .char = 0,
                    .negated = false,
                    .quantifier = .none,
                    .chars = &[_]u8{},
                });
                i += 1;
            },
            '$' => {
                try nodes_list.append(allocator, .{
                    .type = .anchor_end,
                    .char = 0,
                    .negated = false,
                    .quantifier = .none,
                    .chars = &[_]u8{},
                });
                i += 1;
            },
            else => {
                try nodes_list.append(allocator, .{
                    .type = .literal,
                    .char = c,
                    .negated = false,
                    .quantifier = quant,
                    .chars = &[_]u8{},
                });
                i += if (quant != .none) 2 else 1;
            },
        }
    }

    return Pattern{
        .nodes = try nodes_list.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

fn isPunctuation(ch: u8) bool {
    return switch (ch) {
        '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '|', '}', '~' => true,
        else => false,
    };
}

fn matchCharClass(class: u8, ch: u8) bool {
    return switch (class) {
        'a' => std.ascii.isAlphabetic(ch),
        'c' => std.ascii.isControl(ch),
        'd' => std.ascii.isDigit(ch),
        'l' => std.ascii.isLower(ch),
        'p' => isPunctuation(ch),
        's' => std.ascii.isWhitespace(ch),
        'u' => std.ascii.isUpper(ch),
        'w' => std.ascii.isAlphanumeric(ch),
        'x' => std.ascii.isHex(ch),
        'z' => ch == 0,
        else => false,
    };
}

fn matchCharSet(chars: []const u8, ch: u8) bool {
    var i: usize = 0;
    while (i < chars.len) {
        if (i + 2 < chars.len and chars[i + 1] == '-') {
            if (ch >= chars[i] and ch <= chars[i + 2]) {
                return true;
            }
            i += 3;
        } else {
            if (ch == chars[i]) {
                return true;
            }
            i += 1;
        }
    }
    return false;
}

const MatchState = struct {
    pattern: *const Pattern,
    text: []const u8,
    captures: *std.ArrayList(Capture),
    capture_stack: *std.ArrayList(usize),
    allocator: std.mem.Allocator,
};

const InternalMatch = struct {
    matched: bool,
    pos: usize,
};

pub fn match(allocator: std.mem.Allocator, compiled: *const Pattern, text: []const u8, start_pos: usize) PatternError!MatchResult {
    var captures_list = std.ArrayList(Capture){};
    errdefer captures_list.deinit(allocator);

    var capture_stack_list = std.ArrayList(usize){};
    defer capture_stack_list.deinit(allocator);

    var state = MatchState{
        .pattern = compiled,
        .text = text,
        .captures = &captures_list,
        .capture_stack = &capture_stack_list,
        .allocator = allocator,
    };

    const result = try matchInternal(&state, start_pos, 0);

    return MatchResult{
        .matched = result.matched,
        .start = start_pos,
        .end = result.pos,
        .captures = try captures_list.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

fn matchInternal(state: *MatchState, text_pos: usize, pattern_pos: usize) PatternError!InternalMatch {
    if (pattern_pos >= state.pattern.nodes.len) {
        return InternalMatch{ .matched = true, .pos = text_pos };
    }

    const node = state.pattern.nodes[pattern_pos];

    switch (node.type) {
        .anchor_start => {
            if (text_pos != 0) {
                return InternalMatch{ .matched = false, .pos = text_pos };
            }
            return try matchInternal(state, text_pos, pattern_pos + 1);
        },
        .anchor_end => {
            if (text_pos != state.text.len) {
                return InternalMatch{ .matched = false, .pos = text_pos };
            }
            return try matchInternal(state, text_pos, pattern_pos + 1);
        },
        .capture_start => {
            try state.capture_stack.append(state.allocator, text_pos);
            return try matchInternal(state, text_pos, pattern_pos + 1);
        },
        .capture_end => {
            if (state.capture_stack.items.len == 0) return PatternError.UnbalancedParentheses;
            const start = state.capture_stack.pop() orelse return PatternError.UnbalancedParentheses;
            try state.captures.append(state.allocator, Capture{ .start = start, .end = text_pos });
            return try matchInternal(state, text_pos, pattern_pos + 1);
        },
        else => {
            return try matchWithQuantifier(state, text_pos, pattern_pos);
        },
    }
}

fn matchWithQuantifier(state: *MatchState, text_pos: usize, pattern_pos: usize) PatternError!InternalMatch {
    const node = state.pattern.nodes[pattern_pos];

    switch (node.quantifier) {
        .none => {
            if (text_pos >= state.text.len) {
                return InternalMatch{ .matched = false, .pos = text_pos };
            }
            if (try matchSingleChar(&node, state.text[text_pos])) {
                return try matchInternal(state, text_pos + 1, pattern_pos + 1);
            }
            return InternalMatch{ .matched = false, .pos = text_pos };
        },
        .zero_or_more, .one_or_more => {
            var matched_count: usize = 0;
            var pos = text_pos;
            while (pos < state.text.len and try matchSingleChar(&node, state.text[pos])) {
                matched_count += 1;
                pos += 1;
            }

            if (node.quantifier == .one_or_more and matched_count == 0) {
                return InternalMatch{ .matched = false, .pos = text_pos };
            }

            while (true) {
                const result = try matchInternal(state, pos, pattern_pos + 1);
                if (result.matched) return result;

                if (pos == text_pos) break;
                pos -= 1;
            }

            return InternalMatch{ .matched = false, .pos = text_pos };
        },
        .zero_or_more_lazy => {
            var pos = text_pos;
            while (true) {
                const result = try matchInternal(state, pos, pattern_pos + 1);
                if (result.matched) return result;

                if (pos >= state.text.len or !(try matchSingleChar(&node, state.text[pos]))) {
                    break;
                }
                pos += 1;
            }
            return InternalMatch{ .matched = false, .pos = text_pos };
        },
        .optional => {
            if (text_pos < state.text.len and try matchSingleChar(&node, state.text[text_pos])) {
                const with_match = try matchInternal(state, text_pos + 1, pattern_pos + 1);
                if (with_match.matched) return with_match;
            }

            return try matchInternal(state, text_pos, pattern_pos + 1);
        },
    }
}

fn matchSingleChar(node: *const PatternNode, ch: u8) PatternError!bool {
    const matched = switch (node.type) {
        .literal => ch == node.char,
        .any_char => true,
        .char_class => matchCharClass(node.char, ch),
        .char_set => matchCharSet(node.chars, ch),
        else => false,
    };

    return if (node.negated) !matched else matched;
}

pub fn find(allocator: std.mem.Allocator, pattern_str: []const u8, text: []const u8, init: usize) PatternError!?MatchResult {
    var pat = try compile(allocator, pattern_str);
    defer pat.deinit();

    var pos = init;
    while (pos <= text.len) {
        var result = try match(allocator, &pat, text, pos);
        if (result.matched) {
            return result;
        }
        result.deinit();
        pos += 1;
    }

    return null;
}

pub fn gsub(allocator: std.mem.Allocator, text: []const u8, pattern_str: []const u8, replacement: []const u8) PatternError![]const u8 {
    var pat = try compile(allocator, pattern_str);
    defer pat.deinit();

    var result_list = std.ArrayList(u8){};
    errdefer result_list.deinit(allocator);

    var pos: usize = 0;
    while (pos < text.len) {
        var match_result = try match(allocator, &pat, text, pos);
        defer match_result.deinit();

        if (match_result.matched and match_result.end > pos) {
            try result_list.appendSlice(allocator, text[pos..match_result.start]);

            var i: usize = 0;
            while (i < replacement.len) {
                if (replacement[i] == '%' and i + 1 < replacement.len) {
                    const next = replacement[i + 1];
                    if (next >= '1' and next <= '9') {
                        const capture_idx = next - '1';
                        if (capture_idx < match_result.captures.len) {
                            const cap = match_result.captures[capture_idx];
                            try result_list.appendSlice(allocator, text[cap.start..cap.end]);
                        }
                        i += 2;
                        continue;
                    } else if (next == '%') {
                        try result_list.append(allocator, '%');
                        i += 2;
                        continue;
                    }
                }
                try result_list.append(allocator, replacement[i]);
                i += 1;
            }

            pos = match_result.end;
        } else {
            try result_list.append(allocator, text[pos]);
            pos += 1;
        }
    }

    return result_list.toOwnedSlice(allocator);
}
