# Lua Pattern Matching - Implementation Spec

## What We Need to Implement for v0.1.0

### 1. Character Classes
- `.` - Any character
- `%a` - Letters (a-z, A-Z)
- `%c` - Control characters
- `%d` - Digits (0-9)
- `%l` - Lowercase letters
- `%p` - Punctuation
- `%s` - Whitespace
- `%u` - Uppercase letters
- `%w` - Alphanumeric
- `%x` - Hexadecimal digits
- `%z` - Null character
- `%X` - Negated class (e.g., `%D` = non-digit)

### 2. Character Sets
- `[abc]` - Any of a, b, c
- `[^abc]` - None of a, b, c
- `[a-z]` - Range (lowercase)
- `[a-zA-Z0-9]` - Combined ranges

### 3. Quantifiers
- `*` - 0 or more (greedy)
- `+` - 1 or more (greedy)
- `-` - 0 or more (lazy)
- `?` - 0 or 1 (optional)

### 4. Anchors
- `^` - Start of string
- `$` - End of string

### 5. Captures
- `(pattern)` - Capture group
- Return captured substrings as multiple values

### 6. Magic Characters
- `%` - Escape character
- `.`, `^`, `$`, `(`, `)`, `[`, `]`, `*`, `+`, `-`, `?`, `%` need escaping

## Examples to Support

```lua
-- Git branch extraction (GSH critical!)
local head = "ref: refs/heads/main\n"
local branch = stringMatch(head, "refs/heads/(%w+)")  -- "main"

-- Email validation
local email = "user@example.com"
local valid = stringMatch(email, "%w+@%w+%.%w+") ~= nil

-- Split on whitespace
local parts = {}
for word in stringGmatch("hello world  test", "%S+") do
    tableInsert(parts, word)
end
-- parts = {"hello", "world", "test"}

-- Filename parsing
local path = "/home/user/file.txt"
local dir, name, ext = stringMatch(path, "^(.*/)(.*)(%.%w+)$")
-- dir="/home/user/", name="file", ext=".txt"

-- Number extraction
local text = "Port: 8080, Timeout: 30s"
for num in stringGmatch(text, "%d+") do
    print(num)  -- 8080, 30
end

-- Replace with captures
local result = stringGsub("hello world", "(%w+) (%w+)", "%2 %1")
-- result = "world hello"
```

## Implementation Strategy

### Phase 1: Pattern Compiler
Create a pattern AST from the pattern string:
- Parse character classes, sets, quantifiers
- Build finite state machine or recursive matcher
- Handle captures with group tracking

### Phase 2: Matcher Engine
- Match against input string
- Track capture groups
- Support greedy vs lazy quantifiers
- Return match position + captures

### Phase 3: Integration
- Update `stringMatch()` to use pattern engine
- Update `stringFind()` to return captures
- Update `stringGsub()` to support capture replacements
- Add `stringGmatch()` for iterator

## Performance Targets
- Simple patterns (literals): <100ns
- Character classes: <500ns
- Complex patterns with captures: <5µs
- Should be competitive with Lua 5.4

## Testing
Need ~50 test cases covering:
- All character classes
- Quantifiers (greedy/lazy)
- Captures (nested, multiple)
- Edge cases (empty, special chars)
- GSH real-world patterns

## Estimated Effort
- Pattern parser: 2-3 hours
- Matcher engine: 3-4 hours
- Integration + testing: 2-3 hours
- **Total: 7-10 hours** (one good session!)

This is totally doable for v0.1.0! 🚀
