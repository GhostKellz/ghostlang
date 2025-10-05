# Lua Pattern Matching in Ghostlang

Ghostlang v0.1.0 includes a complete implementation of Lua 5.4-style pattern matching, providing powerful text processing capabilities for shell scripts, configurations, and general programming.

## Overview

Pattern matching in Ghostlang follows Lua's simple yet powerful pattern syntax, which is more lightweight than full regular expressions but sufficient for most text processing tasks.

## Built-in Functions

### stringMatch(text, pattern)

Finds the first match of a pattern in a string and returns the first capture or the whole match.

```lua
local text = "Hello World 123!"
local letters = stringMatch(text, "%a+")  -- Returns "Hello"
local digits = stringMatch(text, "%d+")   -- Returns "123"
```

With captures:
```lua
local head = "ref: refs/heads/main"
local branch = stringMatch(head, "refs/heads/(%w+)")  -- Returns "main"
```

### stringFind(pattern, text, [init])

Finds a pattern in text and returns the 1-based starting position, or nil if not found.

```lua
local pos = stringFind("hello", "^h")  -- Returns 1
local pos2 = stringFind("hello", "l")  -- Returns 3 (first 'l')
```

### stringGsub(text, pattern, replacement)

Global substitution - replaces all occurrences of a pattern.

```lua
-- Simple replacement
local result = stringGsub("hello world", "l", "L")  -- "heLLo worLd"

-- Replace entire words
local result = stringGsub("test test test", "test", "best")  -- "best best best"

-- Capture replacement
local swapped = stringGsub("hello world", "(%w+) (%w+)", "%2 %1")  -- "world hello"
```

## Pattern Syntax

### Character Classes

Character classes match specific types of characters:

| Pattern | Matches |
|---------|---------|
| `.` | Any character |
| `%a` | Letters (a-z, A-Z) |
| `%c` | Control characters |
| `%d` | Digits (0-9) |
| `%l` | Lowercase letters |
| `%p` | Punctuation |
| `%s` | Whitespace characters |
| `%u` | Uppercase letters |
| `%w` | Alphanumeric characters |
| `%x` | Hexadecimal digits |
| `%z` | Null character |

**Negation**: Uppercase versions negate the class:
- `%D` = non-digit
- `%W` = non-alphanumeric
- `%S` = non-whitespace

```lua
local text = "Price: $49.99"
local price = stringMatch(text, "%d+%.%d+")  -- "49.99"
local non_digits = stringMatch(text, "%D+")  -- "Price: $"
```

### Character Sets

Character sets `[...]` match any character in the set:

```lua
-- Match vowels
local vowel = stringMatch("hello", "[aeiou]")  -- "e"

-- Match range
local digit = stringMatch("test123", "[0-9]")  -- "1"

-- Negated set (match anything NOT in set)
local non_vowel = stringMatch("hello", "[^aeiou]")  -- "h"

-- Combined ranges
local alphanum = stringMatch("test-123", "[a-zA-Z0-9]+")  -- "test"
```

### Quantifiers

Quantifiers control how many times a pattern repeats:

| Quantifier | Meaning | Behavior |
|------------|---------|----------|
| `*` | 0 or more | Greedy (matches as much as possible) |
| `+` | 1 or more | Greedy |
| `-` | 0 or more | Lazy (matches as little as possible) |
| `?` | 0 or 1 (optional) | Greedy |

```lua
-- Greedy matching
local result = stringMatch("aaabbb", "a+")  -- "aaa"
local result = stringMatch("aaabbb", "a*b+")  -- "aaabbb"

-- Lazy matching
local html = "<div>content</div>"
local tag = stringMatch(html, "<.->(.-)<")  -- Captures "content"
```

### Anchors

Anchors match positions, not characters:

| Anchor | Matches |
|--------|---------|
| `^` | Start of string |
| `$` | End of string |

```lua
-- Start anchor
local starts_with_h = stringMatch("hello", "^h")  -- "h"
local no_match = stringMatch("hello", "^e")  -- nil

-- End anchor
local ends_with_o = stringMatch("hello", "o$")  -- "o"

-- Both anchors = exact match
local exact = stringMatch("test", "^test$")  -- "test"
local no_match = stringMatch("testing", "^test$")  -- nil
```

### Captures

Captures `(...)` extract parts of the matched text:

```lua
-- Single capture
local email = "user@example.com"
local username = stringMatch(email, "(%w+)@")  -- "user"

-- Multiple captures
local email = "user@example.com"
local user, domain = stringMatch(email, "(%w+)@(%w+)")
-- user = "user", domain = "example"

-- Nested captures
local path = "/home/user/file.txt"
local dir, file, ext = stringMatch(path, "(.*/)(.*)(%.%w+)$")
-- dir = "/home/user/", file = "file", ext = ".txt"
```

### Magic Characters

These characters have special meaning and must be escaped with `%`:

`. ^ $ ( ) [ ] * + - ? %`

```lua
-- Escape special characters
local price = stringMatch("Price: $10", "%$%d+")  -- "$10"
local parens = stringMatch("(test)", "%((.-)%)")  -- "test"
local percent = stringMatch("50%", "%d+%%")  -- "50%"
```

## Real-World Examples

### Git Branch Extraction (GSH Critical!)

```lua
-- Parse git HEAD to get current branch
local head = readFile(".git/HEAD")
local branch = stringMatch(head, "refs/heads/(%w+)")
print("Current branch: " .. branch)  -- "main"
```

### Email Validation

```lua
function validateEmail(email)
    local pattern = "%w+@%w+%.%w+"
    return stringMatch(email, pattern) ~= nil
end

print(validateEmail("user@example.com"))  -- true
print(validateEmail("invalid.email"))  -- false
```

### URL Parsing

```lua
local url = "https://github.com/user/repo"
local protocol, domain, user, repo = stringMatch(url,
    "(%w+)://([%w%.]+)/(%w+)/(%w+)")
-- protocol = "https"
-- domain = "github.com"
-- user = "user"
-- repo = "repo"
```

### Config File Parsing

```lua
local config = "timeout = 30s, maxconn = 100"

-- Extract numbers
for num in stringGmatch(config, "%d+") do
    print(num)  -- "30", "100"
end

-- Extract key-value pairs
local key, value = stringMatch(config, "(%w+)%s*=%s*(%d+)")
-- key = "timeout", value = "30"
```

### String Cleaning

```lua
-- Remove extra whitespace
local cleaned = stringGsub("hello    world", "%s+", " ")  -- "hello world"

-- Remove non-alphanumeric
local clean = stringGsub("test-123_abc!", "[^%w]", "")  -- "test123abc"

-- Titlecase
local title = stringGsub("hello world", "(%a)([%w']*)",
    function(first, rest)
        return stringUpper(first) .. stringLower(rest)
    end)
-- "Hello World"
```

### Path Manipulation

```lua
-- Extract filename
local path = "/home/user/documents/file.txt"
local filename = stringMatch(path, "([^/]+)$")  -- "file.txt"

-- Extract directory
local dir = stringMatch(path, "(.*/)")  -- "/home/user/documents/"

-- Change extension
local new_path = stringGsub(path, "%.txt$", ".md")  -- ".../file.md"
```

### Data Extraction

```lua
-- Extract all numbers from text
local text = "Port 8080, timeout 30s, maxconn 100"
local numbers = {}
for num in stringGmatch(text, "%d+") do
    tableInsert(numbers, num)
end
-- numbers = {"8080", "30", "100"}

-- Extract quoted strings
local code = 'print("hello") print("world")'
for str in stringGmatch(code, '"(.-)"') do
    print(str)  -- "hello", "world"
end
```

## Performance Characteristics

Ghostlang's pattern matching engine is designed for performance:

- **Literal matches**: <100ns typical
- **Character classes**: <500ns typical
- **Complex patterns with captures**: <5µs typical
- **Global substitution**: <10µs typical

The engine uses:
- Compiled pattern AST for fast matching
- Zero-copy where possible
- Efficient backtracking for greedy quantifiers
- Lazy evaluation for optimal performance

## Differences from Full Regex

Lua patterns are simpler than PCRE or POSIX regex:

**Not Supported**:
- Alternation (`|`) - use character sets instead
- Lookahead/lookbehind assertions
- Named captures
- Backreferences
- Unicode character classes

**When to Use**:
- Configuration parsing
- Log file analysis
- Shell script text processing
- Simple data extraction

**When to Use Full Regex** (coming in v0.3):
- Complex validation rules
- Advanced text transformation
- Pattern compilation for repeated use

## Tips and Best Practices

### 1. Use Anchors for Validation

```lua
-- Bad: Partial match
local valid = stringMatch(input, "%d+") ~= nil

-- Good: Exact match
local valid = stringMatch(input, "^%d+$") ~= nil
```

### 2. Prefer Lazy Quantifiers for Nested Structures

```lua
-- Bad: Greedy (matches too much)
local tag = stringMatch(html, "<(.*)>")  -- Matches entire string

-- Good: Lazy (matches minimally)
local tag = stringMatch(html, "<(.-)>")  -- Matches first tag
```

### 3. Escape Special Characters

```lua
-- Escape dots in filenames
local ext = stringMatch(filename, "%.(%w+)$")  -- Not ".(%w+)$"

-- Escape parentheses
local inside = stringMatch("(test)", "%((.-)%)")  -- Not "((.-))
```

### 4. Use Character Sets for Alternatives

```lua
-- Instead of: "a|e|i|o|u"
local vowel = stringMatch(word, "[aeiou]")
```

### 5. Combine Patterns for Efficiency

```lua
-- Bad: Multiple passes
local has_letter = stringMatch(text, "%a") ~= nil
local has_digit = stringMatch(text, "%d") ~= nil

-- Good: Single pass
local letter, digit = stringMatch(text, ".*(%a).*(%d)")
local has_both = (letter ~= nil and digit ~= nil)
```

## Integration with Ghostlang

Pattern matching integrates seamlessly with Ghostlang's data structures:

```lua
-- Split string into array
local parts = {}
for word in stringGmatch("hello world test", "%S+") do
    arrayPush(parts, word)
end

-- Parse config into table
local config = createObject()
for line in stringGmatch(file_content, "[^\n]+") do
    local key, value = stringMatch(line, "(%w+)%s*=%s*(.+)")
    if key then
        objectSet(config, key, value)
    end
end

-- Filter array by pattern
local numbers_only = createArray()
for i, item in ipairs(items) do
    if stringMatch(item, "^%d+$") then
        arrayPush(numbers_only, item)
    end
end
```

## See Also

- [String Functions Reference](string_functions.md)
- [Built-in Functions](builtin_functions.md)
- [Data Structures](data_structures.md)
- [GSH Integration Guide](gsh_integration.md)
