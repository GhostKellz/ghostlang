# Ghostlang API Cookbook

**Practical recipes for common plugin tasks**

## Table of Contents

1. [Text Manipulation](#text-manipulation)
2. [Navigation](#navigation)
3. [Selection](#selection)
4. [Search & Replace](#search--replace)
5. [Buffer Operations](#buffer-operations)
6. [Code Analysis](#code-analysis)
7. [User Interaction](#user-interaction)
8. [Advanced Patterns](#advanced-patterns)

---

## Text Manipulation

### Recipe 1: Convert to Uppercase

```ghostlang
// Convert selected text to uppercase
var sel_start = getSelectionStart()
var sel_end = getSelectionEnd()

var line = sel_start
while (line < sel_end + 1) {
    var text = getLineText(line)
    var upper = toUpperCase(text)
    setLineText(line, upper)
    line = line + 1
}

notify("Converted to uppercase")
```

### Recipe 2: Trim Whitespace

```ghostlang
// Remove leading/trailing whitespace from all lines
var line_count = getLineCount()
var i = 0
var trimmed = 0

while (i < line_count) {
    var text = getLineText(i)
    var cleaned = trim(text)

    if (text != cleaned) {
        setLineText(i, cleaned)
        trimmed = trimmed + 1
    }

    i = i + 1
}

notify("Trimmed " + trimmed + " lines")
```

### Recipe 3: Add Prefix to Lines

```ghostlang
// Add prefix to selected lines
var prefix = "// "
var sel_start = getSelectionStart()
var sel_end = getSelectionEnd()

var line = sel_start
while (line < sel_end + 1) {
    var text = getLineText(line)
    var new_text = prefix + text
    setLineText(line, new_text)
    line = line + 1
}
```

---

## Navigation

### Recipe 4: Jump to Line

```ghostlang
// Jump to specific line number
var target_line = 42
var target_col = 0

setCursorPosition(target_line, target_col)
notify("Jumped to line " + target_line)
```

### Recipe 5: Next Empty Line

```ghostlang
// Find and jump to next empty line
var current = getCursorLine()
var line_count = getLineCount()
var found = -1

var i = current + 1
while (i < line_count) {
    var text = getLineText(i)
    var length = len(text)

    if (length == 0) {
        found = i
        i = line_count  // Break loop
    }

    i = i + 1
}

if (found > -1) {
    setCursorPosition(found, 0)
    notify("Found empty line at " + found)
} else {
    notify("No empty lines found")
}
```

### Recipe 6: Go to Matching Brace

```ghostlang
// Find matching brace/bracket
var cursor_line = getCursorLine()
var cursor_col = getCursorCol()
var char = getCharAt(cursor_line, cursor_col)

var depth = 0
var found = false

// Search forward for closing brace
if (char == 123) {  // {
    var i = cursor_line
    var line_count = getLineCount()

    while (i < line_count) {
        var text = getLineText(i)
        // Count braces...
        i = i + 1
    }
}
```

---

## Selection

### Recipe 7: Select Current Word

```ghostlang
// Select word under cursor
var line = getCursorLine()
var col = getCursorCol()
var text = getLineText(line)

// Find word boundaries
var start = col
var end = col

// Extend left
while (start > 0) {
    var c = charAt(text, start - 1)
    if (isWordChar(c)) {
        start = start - 1
    } else {
        break
    }
}

// Extend right
var length = len(text)
while (end < length) {
    var c = charAt(text, end)
    if (isWordChar(c)) {
        end = end + 1
    } else {
        break
    }
}

setSelection(line, start, line, end)
```

### Recipe 8: Expand Selection

```ghostlang
// Expand selection by N characters
var expand_by = 5

var start_line = getSelectionStartLine()
var start_col = getSelectionStartCol()
var end_line = getSelectionEndLine()
var end_col = getSelectionEndCol()

// Expand start
var new_start_col = start_col - expand_by
if (new_start_col < 0) {
    new_start_col = 0
}

// Expand end
var line_text = getLineText(end_line)
var line_length = len(line_text)
var new_end_col = end_col + expand_by
if (new_end_col > line_length) {
    new_end_col = line_length
}

setSelection(start_line, new_start_col, end_line, new_end_col)
```

### Recipe 9: Select Lines in Range

```ghostlang
// Select lines 10-20
var start_line = 10
var end_line = 20

var start_col = 0
var end_text = getLineText(end_line)
var end_col = len(end_text)

setSelection(start_line, start_col, end_line, end_col)
notify("Selected lines " + start_line + "-" + end_line)
```

---

## Search & Replace

### Recipe 10: Find All Occurrences

```ghostlang
// Find all occurrences of a pattern
var pattern = "TODO"
var line_count = getLineCount()
var matches = 0

var i = 0
while (i < line_count) {
    var text = getLineText(i)
    var found = indexOf(text, pattern)

    if (found > -1) {
        matches = matches + 1
    }

    i = i + 1
}

notify("Found " + matches + " matches")
```

### Recipe 11: Replace in Selection

```ghostlang
// Replace old with new in selection
var old_text = "foo"
var new_text = "bar"

var sel_start = getSelectionStart()
var sel_end = getSelectionEnd()
var replacements = 0

var line = sel_start
while (line < sel_end + 1) {
    var text = getLineText(line)
    var found = indexOf(text, old_text)

    if (found > -1) {
        var updated = replace(text, old_text, new_text)
        setLineText(line, updated)
        replacements = replacements + 1
    }

    line = line + 1
}

notify("Replaced " + replacements + " occurrences")
```

### Recipe 12: Case-Insensitive Search

```ghostlang
// Find text ignoring case
var pattern = "error"
var pattern_lower = toLowerCase(pattern)
var matches = 0

var i = 0
var line_count = getLineCount()

while (i < line_count) {
    var text = getLineText(i)
    var text_lower = toLowerCase(text)
    var found = indexOf(text_lower, pattern_lower)

    if (found > -1) {
        matches = matches + 1
    }

    i = i + 1
}

notify("Found " + matches + " matches (case-insensitive)")
```

---

## Buffer Operations

### Recipe 13: Duplicate Line

```ghostlang
// Duplicate current line
var line = getCursorLine()
var text = getLineText(line)

insertLineAfter(line, text)
notify("Line duplicated")
```

### Recipe 14: Delete Empty Lines

```ghostlang
// Delete all empty lines
var line_count = getLineCount()
var deleted = 0

var i = line_count - 1  // Start from end
while (i > -1) {
    var text = getLineText(i)
    var length = len(text)

    if (length == 0) {
        deleteLine(i)
        deleted = deleted + 1
    }

    i = i - 1
}

notify("Deleted " + deleted + " empty lines")
```

### Recipe 15: Sort Lines

```ghostlang
// Sort selected lines alphabetically
var sel_start = getSelectionStart()
var sel_end = getSelectionEnd()
var count = sel_end - sel_start + 1

// Simple bubble sort
var i = sel_start
while (i < sel_end) {
    var j = i + 1
    while (j < sel_end + 1) {
        var text_i = getLineText(i)
        var text_j = getLineText(j)

        if (compare(text_i, text_j) > 0) {
            // Swap lines
            setLineText(i, text_j)
            setLineText(j, text_i)
        }

        j = j + 1
    }
    i = i + 1
}

notify("Sorted " + count + " lines")
```

---

## Code Analysis

### Recipe 16: Count Functions

```ghostlang
// Count function definitions
var pattern = "function"
var count = 0

var i = 0
var line_count = getLineCount()

while (i < line_count) {
    var text = getLineText(i)
    var found = indexOf(text, pattern)

    if (found > -1) {
        count = count + 1
    }

    i = i + 1
}

notify("Found " + count + " functions")
```

### Recipe 17: Check Indentation

```ghostlang
// Check for inconsistent indentation
var tab_count = 0
var space_count = 0

var i = 0
var line_count = getLineCount()

while (i < line_count) {
    var text = getLineText(i)
    var first_char = charAt(text, 0)

    if (first_char == 9) {  // Tab
        tab_count = tab_count + 1
    } else if (first_char == 32) {  // Space
        space_count = space_count + 1
    }

    i = i + 1
}

if (tab_count > 0 && space_count > 0) {
    notify("Mixed indentation detected!")
}
```

### Recipe 18: Count Complexity

```ghostlang
// Simple complexity metric (count decision points)
var complexity = 0

var i = 0
var line_count = getLineCount()

while (i < line_count) {
    var text = getLineText(i)

    // Count if, while, for
    var has_if = indexOf(text, "if") > -1
    var has_while = indexOf(text, "while") > -1
    var has_for = indexOf(text, "for") > -1

    if (has_if) {
        complexity = complexity + 1
    }
    if (has_while) {
        complexity = complexity + 1
    }
    if (has_for) {
        complexity = complexity + 1
    }

    i = i + 1
}

notify("Complexity: " + complexity)
```

---

## User Interaction

### Recipe 19: Show Statistics

```ghostlang
// Display buffer statistics
var line_count = getLineCount()
var char_count = 0
var word_count = 0

var i = 0
while (i < line_count) {
    var text = getLineText(i)
    var length = len(text)
    char_count = char_count + length

    // Rough word count
    word_count = word_count + (length / 5)

    i = i + 1
}

var msg = "Lines: " + line_count + ", Words: ~" + word_count + ", Chars: " + char_count
notify(msg)
```

### Recipe 20: Progress Indicator

```ghostlang
// Show progress for long operations
var total = 1000
var chunk_size = 100

var i = 0
while (i < total) {
    // Do work...

    // Update progress every chunk
    if (i % chunk_size == 0) {
        var percent = (i * 100) / total
        notify("Progress: " + percent + "%")
    }

    i = i + 1
}

notify("Complete!")
```

---

## Advanced Patterns

### Recipe 21: Multi-Cursor Simulation

```ghostlang
// Apply operation at multiple positions
var positions = [10, 20, 30, 40, 50]  // Line numbers
var text_to_insert = "// TODO: "

var i = 0
var count = 5

while (i < count) {
    var line = positions[i]
    var current_text = getLineText(line)
    var new_text = text_to_insert + current_text
    setLineText(line, new_text)

    i = i + 1
}

notify("Applied to " + count + " positions")
```

### Recipe 22: Conditional Formatting

```ghostlang
// Format lines based on content
var i = 0
var line_count = getLineCount()
var formatted = 0

while (i < line_count) {
    var text = getLineText(i)

    // If line starts with "//", indent it
    var first = charAt(text, 0)
    var second = charAt(text, 1)

    if (first == 47 && second == 47) {  // //
        var new_text = "  " + text
        setLineText(i, new_text)
        formatted = formatted + 1
    }

    i = i + 1
}

notify("Formatted " + formatted + " comment lines")
```

### Recipe 23: Batch Processing

```ghostlang
// Process buffer in batches for performance
var line_count = getLineCount()
var batch_size = 100
var batches = line_count / batch_size

var batch = 0
while (batch < batches) {
    var start = batch * batch_size
    var end = start + batch_size
    if (end > line_count) {
        end = line_count
    }

    // Process batch
    var i = start
    while (i < end) {
        var text = getLineText(i)
        // Process...
        i = i + 1
    }

    batch = batch + 1
}
```

---

## Performance Tips

### ✓ DO: Cache Values

```ghostlang
// Good
var line_count = getLineCount()
var i = 0
while (i < line_count) {
    i = i + 1
}
```

### ✗ DON'T: Repeat Expensive Calls

```ghostlang
// Bad
var i = 0
while (i < getLineCount()) {  // Called every iteration!
    i = i + 1
}
```

### ✓ DO: Early Exit

```ghostlang
// Good
var found = false
var i = 0
while (i < line_count && !found) {
    if (condition) {
        found = true
    }
    i = i + 1
}
```

### ✗ DON'T: Process Unnecessary Data

```ghostlang
// Bad
var i = 0
while (i < line_count) {
    // Process everything even after finding what we need
    i = i + 1
}
```

---

## Next Steps

- Check `examples/plugins/` for complete working examples
- Read `plugin-quickstart.md` for language basics
- Join community to share recipes
- Contribute your own recipes!

---

**Happy Coding!** 🚀
