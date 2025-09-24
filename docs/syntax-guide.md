# Ghostlang Syntax Guide

A comprehensive reference for Ghostlang syntax and language constructs.

## Table of Contents

1. [Comments](#comments)
2. [Literals](#literals)
3. [Variables](#variables)
4. [Operators](#operators)
5. [Control Structures](#control-structures)
6. [Functions](#functions)
7. [Data Structures](#data-structures)
8. [Modules](#modules)

## Comments

### Single-line Comments
```lua
-- This is a single-line comment
local x = 10  -- Comment at end of line
```

### Multi-line Comments
```lua
--[[
This is a multi-line comment
that can span multiple lines
--]]
```

## Literals

### Number Literals
```lua
local integer = 42
local float = 3.14159
local scientific = 1.23e-4
local negative = -100
local zero = 0
```

### String Literals
```lua
local single = 'Single quotes'
local double = "Double quotes"
local empty = ""
local with_escape = "Line 1\nLine 2\tTabbed"
```

### Boolean Literals
```lua
local truth = true
local falsehood = false
```

### Nil Literal
```lua
local nothing = nil
```

### Array Literals
```lua
local empty_array = []
local numbers = [1, 2, 3, 4, 5]
local mixed = [1, "hello", true, nil]
local nested = [[1, 2], [3, 4], [5, 6]]
```

### Table Literals
```lua
local empty_table = {}
local person = {
    name = "Alice",
    age = 30,
    active = true
}
local nested_table = {
    config = {
        theme = "dark",
        size = 14
    },
    data = [1, 2, 3]
}
```

## Variables

### Local Variables
```lua
local x = 10
local name = "Alice"
local active = true
```

### Global Variables
```lua
global_counter = 0  -- No 'local' keyword = global
app_name = "MyApp"
```

### Multiple Assignment
```lua
local a, b, c = 1, 2, 3
local x, y = getValue()  -- If getValue returns multiple values
```

## Operators

### Arithmetic Operators
```lua
local a = 10
local b = 3

local sum = a + b         -- 13
local difference = a - b  -- 7
local product = a * b     -- 30
local quotient = a / b    -- 3.333...
local remainder = a % b   -- 1
```

### Comparison Operators
```lua
local a = 10
local b = 20

local equal = (a == b)        -- false
local not_equal = (a != b)    -- true
local less_than = (a < b)     -- true
local less_equal = (a <= b)   -- true
local greater = (a > b)       -- false
local greater_equal = (a >= b) -- false
```

### Logical Operators
```lua
local a = true
local b = false

local and_op = a && b     -- false
local or_op = a || b      -- true
local not_op = !a         -- false

-- Complex expressions
local result = (x > 0) && (y < 100) || (z == 0)
```

### String Operators
```lua
local greeting = "Hello" .. " " .. "World"  -- "Hello World"
local repeated = "Ha" .. "Ha" .. "Ha"       -- "HaHaHa"
```

### Assignment Operators
```lua
local x = 10
x = x + 5     -- Simple assignment

-- Note: Compound assignment operators (+=, -=, etc.) are not yet supported
```

## Control Structures

### If Statements

#### Basic If
```lua
if condition then
    -- statements
end

-- C-style syntax also supported
if (condition) {
    // statements
}
```

#### If-Else
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
else
    print("F")
end
```

#### Complex Conditions
```lua
if (age >= 18) && (has_license || has_permit) then
    print("Can drive")
elseif age >= 16 then
    print("Can drive with supervision")
else
    print("Cannot drive")
end
```

### Loops

#### For Loop (Numeric)
```lua
-- Basic for loop: for var = start, end, step do
for i = 1, 10, 1 do
    print("Count:", i)
end

-- Step can be omitted (defaults to 1)
for i = 1, 5 do
    print("Number:", i)
end

-- Negative step for counting down
for i = 10, 1, -1 do
    print("Countdown:", i)
end
```

#### While Loop
```lua
local count = 0
while count < 5 do
    print("Iteration:", count)
    count = count + 1
end

-- Infinite loop (use with caution)
while true do
    local input = get_input()
    if input == "quit" then
        break  -- Break statement (when implemented)
    end
    process_input(input)
end
```

#### For-In Loop (Future Feature)
```lua
-- Table iteration (planned feature)
for key, value in pairs(person) do
    print(key .. ": " .. value)
end

-- Array iteration (planned feature)
for index, item in ipairs(numbers) do
    print(index, item)
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
function calculate_area(width, height)
    return width * height
end

-- Function with no parameters
function get_timestamp()
    return os.time()  -- When os module is available
end
```

### Function Calls
```lua
local message = greet("Alice")
local area = calculate_area(10, 20)
local now = get_timestamp()

-- Nested calls
local result = process_data(get_input())
```

### Local Functions
```lua
local function helper(x)
    return x * 2
end

function main_function()
    local value = 10
    return helper(value)  -- Returns 20
end
```

### Anonymous Functions (Future Feature)
```lua
-- Function expressions (planned)
local multiply = function(a, b)
    return a * b
end

-- Arrow functions (planned)
local square = (x) => x * x
```

## Data Structures

### Arrays

#### Creation and Access
```lua
local numbers = [1, 2, 3, 4, 5]

-- Access elements (0-indexed)
local first = numbers[0]    -- 1
local second = numbers[1]   -- 2
local last = numbers[4]     -- 5
```

#### Modification
```lua
-- Change existing element
numbers[0] = 10

-- Add elements (if supported by implementation)
numbers[5] = 6
```

### Tables

#### Creation and Access
```lua
local person = {
    name = "Alice",
    age = 30,
    city = "New York"
}

-- Dot notation
local name = person.name
local age = person.age

-- Bracket notation (for dynamic keys)
local key = "city"
local city = person[key]
```

#### Modification
```lua
-- Add new properties
person.email = "alice@example.com"
person.active = true

-- Modify existing properties
person.age = 31

-- Delete properties (set to nil)
person.city = nil
```

#### Nested Tables
```lua
local config = {
    database = {
        host = "localhost",
        port = 5432,
        name = "myapp"
    },
    cache = {
        enabled = true,
        ttl = 3600
    }
}

-- Access nested properties
local db_host = config.database.host
local cache_enabled = config.cache.enabled
```

## Modules

### Creating Modules
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

-- Export the module
return mathutils
```

### Using Modules
```lua
-- Import module
local math = require("mathutils")

-- Use module functions
local sum = math.add(10, 20)
local product = math.multiply(5, 4)
local circle_area = math.pi * 5 * 5
```

### Module Patterns
```lua
-- Pattern 1: Table of functions
local utils = {
    capitalize = function(str)
        return str_upper(substr(str, 0, 1)) .. str_lower(substr(str, 1))
    end,

    is_empty = function(str)
        return strlen(str) == 0
    end
}

-- Pattern 2: Constructor pattern
local function createCounter(initial)
    local count = initial || 0

    return {
        increment = function()
            count = count + 1
            return count
        end,

        decrement = function()
            count = count - 1
            return count
        end,

        value = function()
            return count
        end
    }
end
```

## Syntax Variations

### Block Delimiters

Ghostlang supports both Lua-style and C-style block syntax:

#### Lua-style
```lua
if condition then
    -- statements
end

while condition do
    -- statements
end

function name()
    -- statements
end
```

#### C-style
```lua
if (condition) {
    // statements
}

while (condition) {
    // statements
}

function name() {
    // statements
}
```

### Expression vs Statement Context

#### Expression Context
```lua
local result = condition && value1 || value2
local max = (a > b) && a || b
```

#### Statement Context
```lua
if condition then
    do_something()
end
```

## Best Practices

### Naming Conventions
```lua
-- Use snake_case for variables and functions
local user_name = "Alice"
local file_path = "/home/user/file.txt"

function calculate_total(items)
    return total
end

-- Use UPPER_CASE for constants
local MAX_RETRY_COUNT = 3
local DEFAULT_TIMEOUT = 1000
```

### Code Organization
```lua
-- Group related variables
local config = {
    debug_mode = true,
    log_level = "info",
    max_connections = 100
}

-- Use meaningful names
local is_file_modified = check_file_status(file_path)
local user_input_buffer = read_user_input()

-- Keep functions focused and small
function validate_email(email)
    return str_find(email, "@") != nil && str_find(email, ".") != nil
end

function send_welcome_email(user)
    if validate_email(user.email) then
        return send_email(user.email, create_welcome_message(user.name))
    end
    return false
end
```

---

This syntax guide covers the current implementation of Ghostlang. For the most up-to-date features, see the [Language Guide](language-guide.md).