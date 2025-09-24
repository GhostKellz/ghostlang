# Ghostlang Language Guide

This comprehensive guide covers all aspects of the Ghostlang programming language.

## Table of Contents

1. [Basic Syntax](#basic-syntax)
2. [Data Types](#data-types)
3. [Variables](#variables)
4. [Operators](#operators)
5. [Control Flow](#control-flow)
6. [Functions](#functions)
7. [Tables and Objects](#tables-and-objects)
8. [Arrays](#arrays)
9. [Strings](#strings)
10. [Modules](#modules)
11. [Error Handling](#error-handling)

## Basic Syntax

### Comments

```lua
-- Single line comment

--[[
Multi-line comment
can span multiple lines
--]]
```

### Statements

Statements can be separated by newlines or semicolons:

```lua
local x = 10
local y = 20; local z = 30  -- Multiple statements on one line
```

### Blocks

Blocks are delimited by keywords and `end` or by curly braces `{}`:

```lua
-- Lua-style blocks
if condition then
    -- statements
end

-- C-style blocks (also supported)
if (condition) {
    // statements
}
```

## Data Types

Ghostlang supports several built-in data types:

### Numbers

```lua
local integer = 42
local float = 3.14159
local scientific = 1.23e-4
local negative = -100
```

### Booleans

```lua
local is_true = true
local is_false = false
```

### Nil

```lua
local nothing = nil
```

### Strings

```lua
local single_quotes = 'Hello'
local double_quotes = "World"
local concatenated = "Hello" .. " " .. "World"
```

### Arrays

```lua
local numbers = [1, 2, 3, 4, 5]
local mixed = [1, "hello", true, nil]
local nested = [[1, 2], [3, 4]]
```

### Tables

```lua
local person = {
    name = "Alice",
    age = 30,
    active = true
}
```

## Variables

### Local Variables

```lua
local x = 10          -- Local variable
local y, z = 20, 30   -- Multiple assignment
```

### Global Variables

```lua
global_var = "I'm global"  -- Global variable (no 'local' keyword)
```

### Variable Scope

```lua
local x = 10  -- Outer scope

if x > 5 then
    local y = 20  -- Inner scope
    x = x + y     -- Can access outer scope
end

-- y is not accessible here
```

## Operators

### Arithmetic Operators

```lua
local a = 10
local b = 3

local sum = a + b        -- 13
local diff = a - b       -- 7
local product = a * b    -- 30
local quotient = a / b   -- 3.333...
local remainder = a % b  -- 1
```

### Comparison Operators

```lua
local a = 10
local b = 20

local equal = (a == b)        -- false
local not_equal = (a != b)    -- true
local less = (a < b)          -- true
local less_equal = (a <= b)   -- true
local greater = (a > b)       -- false
local greater_equal = (a >= b) -- false
```

### Logical Operators

```lua
local a = true
local b = false

local and_result = a && b    -- false
local or_result = a || b     -- true
local not_result = !a        -- false
```

### String Operators

```lua
local greeting = "Hello" .. " " .. "World"  -- "Hello World"
```

## Control Flow

### Conditional Statements

#### If Statement

```lua
local score = 85

if score >= 90 then
    print("Excellent!")
end
```

#### If-Else Statement

```lua
if score >= 70 then
    print("Pass")
else
    print("Fail")
end
```

#### If-ElseIf-Else Chain

```lua
if score >= 90 then
    print("A")
elseif score >= 80 then
    print("B")
elseif score >= 70 then
    print("C")
elseif score >= 60 then
    print("D")
else
    print("F")
end
```

#### Complex Conditions

```lua
local age = 25
local has_license = true
local has_insurance = true

if age >= 18 && (has_license && has_insurance) then
    print("Can drive legally!")
elseif age >= 16 && has_license then
    print("Can drive with restrictions")
else
    print("Cannot drive")
end
```

### Loops

#### For Loop (Numeric)

```lua
-- Basic for loop
for i = 1, 10, 1 do
    print("Count:", i)
end

-- For loop with step
for i = 10, 1, -2 do  -- Count down by 2
    print("Countdown:", i)
end
```

#### While Loop

```lua
local count = 0
while count < 5 do
    print("Count:", count)
    count = count + 1
end
```

#### For-In Loop (Planned)

```lua
-- Iterate over table (future feature)
for key, value in pairs(person) do
    print(key, ":", value)
end
```

## Functions

### Function Definition

```lua
-- Basic function
function greet(name)
    return "Hello, " .. name .. "!"
end

-- Function with multiple parameters
function add(a, b)
    return a + b
end

-- Function with default behavior
function divide(a, b)
    if b == 0 then
        return nil  -- Handle division by zero
    end
    return a / b
end
```

### Function Calls

```lua
local message = greet("Alice")
local sum = add(10, 20)
local result = divide(10, 2)
```

### Local Functions

```lua
local function helper(x)
    return x * 2
end

function main()
    return helper(5)  -- Returns 10
end
```

## Tables and Objects

### Table Creation

```lua
-- Empty table
local empty = {}

-- Table with initial values
local person = {
    name = "Alice",
    age = 30,
    city = "New York"
}
```

### Property Access

```lua
-- Dot notation
local name = person.name
person.age = 31

-- Bracket notation (for dynamic keys)
local key = "city"
local city = person[key]
```

### Nested Tables

```lua
local config = {
    window = {
        width = 800,
        height = 600,
        title = "My App"
    },
    theme = {
        background = "dark",
        foreground = "white"
    }
}

-- Access nested properties
local window_width = config.window.width
local bg_color = config.theme.background
```

### Methods

```lua
local calculator = {
    value = 0,

    add = function(self, n)
        self.value = self.value + n
        return self
    end,

    multiply = function(self, n)
        self.value = self.value * n
        return self
    end,

    result = function(self)
        return self.value
    end
}

-- Method chaining
local result = calculator:add(5):multiply(2):result()  -- 10
```

## Arrays

### Array Creation

```lua
local numbers = [1, 2, 3, 4, 5]
local mixed = ["hello", 42, true, nil]
local empty = []
```

### Array Access

```lua
local first = numbers[0]    -- Arrays are 0-indexed
local second = numbers[1]
local last = numbers[4]
```

### Array Modification

```lua
numbers[0] = 10        -- Change first element
numbers[5] = 6         -- Add new element (if supported)
```

### Array Operations

```lua
local length = array_length(numbers)
array_push(numbers, 6)  -- Add to end (if implemented)
```

## Strings

### String Creation

```lua
local simple = "Hello"
local with_quotes = 'Say "Hello"'
local multiline = "Line 1\nLine 2"
```

### String Operations

```lua
local text = "Ghostlang"

-- Length
local len = strlen(text)  -- 9

-- Case conversion
local upper = str_upper(text)    -- "GHOSTLANG"
local lower = str_lower(text)    -- "ghostlang"

-- Substring
local sub = substr(text, 0, 5)   -- "Ghost"

-- Search
local pos = str_find(text, "lang")  -- Position of "lang"

-- Concatenation
local greeting = "Hello" .. " " .. "World"
```

## Modules

### Creating a Module

```lua
-- mathutils.gza
local mathutils = {}

function mathutils.add(a, b)
    return a + b
end

function mathutils.multiply(a, b)
    return a * b
end

mathutils.pi = 3.14159

return mathutils
```

### Using a Module

```lua
-- main.gza
local math = require("mathutils")

local sum = math.add(10, 20)
local area = math.pi * 5 * 5  -- Circle area
```

## Error Handling

### Basic Error Handling

```lua
-- Check for nil values
local result = some_function()
if result == nil then
    print("Function failed")
    return
end

-- Validate parameters
function divide(a, b)
    if b == 0 then
        print("Error: Division by zero")
        return nil
    end
    return a / b
end
```

### File Operations Error Handling

```lua
local content = file_read("config.txt")
if content == nil then
    print("Failed to read configuration file")
    -- Use default configuration
    content = "default_config"
end
```

## Best Practices

### Code Organization

```lua
-- Group related functionality
local config = {
    window = { width = 800, height = 600 },
    theme = { background = "dark" }
}

-- Use meaningful names
local is_file_modified = true
local user_input_buffer = ""

-- Keep functions focused
function validate_email(email)
    return str_find(email, "@") ~= nil
end
```

### Performance Tips

```lua
-- Cache frequently accessed values
local window_config = config.window
local width = window_config.width
local height = window_config.height

-- Avoid repeated string concatenation in loops
local parts = []
for i = 1, 100 do
    array_push(parts, "item" .. i)
end
local result = array_join(parts, ", ")
```

---

This guide covers the core features of Ghostlang. For more specific topics, see the individual documentation files for [Control Flow](control-flow.md), [Functions](functions.md), and [Data Types](data-types.md).