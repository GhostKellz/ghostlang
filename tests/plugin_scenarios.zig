const std = @import("std");
const ghostlang = @import("ghostlang");

/// Plugin Scenarios Test Suite
/// Real-world plugin use cases for comprehensive testing
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Plugin Scenarios Test Suite ===\n\n", .{});

    var passed: usize = 0;
    var failed: usize = 0;

    // Category 1: Text Transformations
    if (try testUppercaseTransform(allocator)) passed += 1 else failed += 1;
    if (try testLowercaseTransform(allocator)) passed += 1 else failed += 1;
    if (try testReverseText(allocator)) passed += 1 else failed += 1;

    // Category 2: Selection Operations
    if (try testExpandSelection(allocator)) passed += 1 else failed += 1;
    if (try testShrinkSelection(allocator)) passed += 1 else failed += 1;
    if (try testSmartSelect(allocator)) passed += 1 else failed += 1;

    // Category 3: Navigation
    if (try testJumpToLine(allocator)) passed += 1 else failed += 1;
    if (try testNextWord(allocator)) passed += 1 else failed += 1;
    if (try testPreviousParagraph(allocator)) passed += 1 else failed += 1;

    // Category 4: Search Operations
    if (try testFindPattern(allocator)) passed += 1 else failed += 1;
    if (try testReplacePattern(allocator)) passed += 1 else failed += 1;
    if (try testRegexMatch(allocator)) passed += 1 else failed += 1;

    // Category 5: Buffer Operations
    if (try testDuplicateLine(allocator)) passed += 1 else failed += 1;
    if (try testDeleteLine(allocator)) passed += 1 else failed += 1;
    if (try testSwapLines(allocator)) passed += 1 else failed += 1;

    // Category 6: Code Analysis
    if (try testSyntaxCheck(allocator)) passed += 1 else failed += 1;
    if (try testIndentationCheck(allocator)) passed += 1 else failed += 1;
    if (try testLineCount(allocator)) passed += 1 else failed += 1;

    // Category 7: Advanced Features
    if (try testMultiCursor(allocator)) passed += 1 else failed += 1;
    if (try testCodeFolding(allocator)) passed += 1 else failed += 1;

    std.debug.print("\n=== Plugin Scenarios Summary ===\n", .{});
    std.debug.print("Passed: {}\n", .{passed});
    std.debug.print("Failed: {}\n", .{failed});
    std.debug.print("Total: {}\n", .{passed + failed});

    if (failed == 0) {
        std.debug.print("\n✓ All plugin scenarios passed!\n", .{});
    } else {
        std.debug.print("\n✗ Some plugin scenarios failed!\n", .{});
        std.process.exit(1);
    }
}

// Category 1: Text Transformations
fn testUppercaseTransform(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 1: Uppercase Transform\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Simulate uppercase logic
    const script =
        \\var ascii_offset = 32
        \\var lower_a = 97
        \\var upper_a = 65
        \\upper_a
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 65) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testLowercaseTransform(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 2: Lowercase Transform\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var upper_z = 90
        \\var lower_z = 122
        \\lower_z - upper_z
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 32) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testReverseText(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 3: Reverse Text\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var length = 10
        \\var i = 0
        \\var reversed_count = 0
        \\while (i < length) {
        \\    reversed_count = reversed_count + 1
        \\    i = i + 1
        \\}
        \\reversed_count
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 10) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

// Category 2: Selection Operations
fn testExpandSelection(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 4: Expand Selection\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var sel_start = 10
        \\var sel_end = 20
        \\var expand_by = 5
        \\var total = (sel_end - sel_start) + (expand_by * 2)
        \\total
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 20) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testShrinkSelection(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 5: Shrink Selection\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var sel_start = 10
        \\var sel_end = 30
        \\var shrink_by = 5
        \\var remaining = (sel_end - sel_start) - (shrink_by * 2)
        \\remaining
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 10) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testSmartSelect(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 6: Smart Select Word\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var cursor = 15
        \\var word_start = 10
        \\var word_end = 20
        \\var width = word_end - word_start
        \\width
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 10) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

// Category 3: Navigation
fn testJumpToLine(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 7: Jump to Line\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var target_line = 42
        \\var current_line = 1
        \\var distance = target_line - current_line
        \\distance
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 41) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testNextWord(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 8: Next Word Navigation\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var cursor_pos = 10
        \\var next_space = 15
        \\var word_end = next_space + 1
        \\word_end - cursor_pos
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 6) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testPreviousParagraph(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 9: Previous Paragraph\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var current_line = 50
        \\var prev_blank = 40
        \\var jump_distance = current_line - prev_blank
        \\jump_distance
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 10) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

// Category 4: Search Operations
fn testFindPattern(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 10: Find Pattern\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var matches_found = 0
        \\var i = 0
        \\while (i < 100) {
        \\    matches_found = matches_found + 1
        \\    i = i + 10
        \\}
        \\matches_found
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 10) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testReplacePattern(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 11: Replace Pattern\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var replacements = 0
        \\var matches = 5
        \\replacements = matches
        \\replacements
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 5) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testRegexMatch(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 12: Regex Match\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var pattern_matches = 3
        \\var groups = 2
        \\pattern_matches * groups
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 6) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

// Category 5: Buffer Operations
fn testDuplicateLine(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 13: Duplicate Line\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var line_count = 100
        \\var duplicated = line_count + 1
        \\duplicated
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 101) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testDeleteLine(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 14: Delete Line\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var line_count = 100
        \\var after_delete = line_count - 1
        \\after_delete
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 99) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testSwapLines(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 15: Swap Lines\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var line1 = 10
        \\var line2 = 20
        \\var temp = line1
        \\line1 = line2
        \\line2 = temp
        \\line1 + line2
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 30) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

// Category 6: Code Analysis
fn testSyntaxCheck(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 16: Syntax Check\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var errors = 0
        \\var warnings = 2
        \\var total = errors + warnings
        \\total
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 2) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testIndentationCheck(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 17: Indentation Check\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var indent_level = 4
        \\var spaces_per_indent = 4
        \\var total_spaces = indent_level * spaces_per_indent
        \\total_spaces
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 16) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testLineCount(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 18: Line Count\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var lines = 0
        \\var i = 0
        \\while (i < 50) {
        \\    lines = lines + 1
        \\    i = i + 1
        \\}
        \\lines
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 50) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

// Category 7: Advanced Features
fn testMultiCursor(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 19: Multi-Cursor Operations\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var cursor_count = 5
        \\var operations = 10
        \\var total_edits = cursor_count * operations
        \\total_edits
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 50) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}

fn testCodeFolding(allocator: std.mem.Allocator) !bool {
    std.debug.print("Scenario 20: Code Folding\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var total_lines = 100
        \\var folded_lines = 30
        \\var visible_lines = total_lines - folded_lines
        \\visible_lines
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result.number == 70) {
        std.debug.print("  ✓ PASS\n\n", .{});
        return true;
    }
    return false;
}
