# Getting Started with Ghostlang

Welcome to **Ghostlang**! This guide will help you get up and running with Ghostlang in just a few minutes.

## 🏗️ Installation

### Prerequisites

- **Zig 0.16.0+** - [Download Zig](https://ziglang.org/download/)
- **Git** - For cloning the repository

### Building from Source

```bash
# Clone the repository
git clone https://github.com/your-org/ghostlang.git
cd ghostlang

# Build the project
zig build

# The executable will be at ./zig-out/bin/ghostlang
```

### Verify Installation

```bash
# Test the installation
./zig-out/bin/ghostlang --version

# Run the interactive mode
./zig-out/bin/ghostlang

# Run a script file
./zig-out/bin/ghostlang examples/hello.gza
```

## 🚀 Your First Ghostlang Script

Create a file called `hello.gza`:

```lua
-- Your first Ghostlang script
print("Hello, Ghostlang!")

-- Variables and basic math
local x = 10
local y = 20
local sum = x + y
print("Sum:", sum)

-- Conditionals
if sum > 25 then
    print("Sum is greater than 25!")
else
    print("Sum is 25 or less")
end
```

Run it:

```bash
./zig-out/bin/ghostlang hello.gza
```

Expected output:
```
Hello, Ghostlang!
Sum: 30
Sum is greater than 25!
```

## 📖 Core Language Features

### Variables and Data Types

```lua
-- Numbers
local age = 25
local temperature = 98.6

-- Strings
local name = "Alice"
local message = "Hello, " .. name .. "!"

-- Booleans
local is_active = true
local is_finished = false

-- Arrays
local numbers = [1, 2, 3, 4, 5]
print("First number:", numbers[0])  -- Arrays are 0-indexed

-- Tables (objects)
local person = {
    name = "Bob",
    age = 30,
    city = "New York"
}
print("Person name:", person.name)
```

### Control Flow

#### Conditionals

```lua
local score = 85

if score >= 90 then
    print("Grade: A")
elseif score >= 80 then
    print("Grade: B")  -- This will execute
elseif score >= 70 then
    print("Grade: C")
else
    print("Grade: F")
end

-- Logical operators
local age = 25
local has_license = true

if age >= 18 && has_license then
    print("Can drive!")
end
```

#### Loops

```lua
-- For loop
for i = 1, 5, 1 do
    print("Count:", i)
end

-- While loop
local count = 0
while count < 3 do
    print("While count:", count)
    count = count + 1
end
```

### Functions

```lua
-- Function definition
function greet(name)
    return "Hello, " .. name .. "!"
end

-- Function call
local message = greet("World")
print(message)

-- Function with multiple parameters
function calculate_area(length, width)
    return length * width
end

local area = calculate_area(10, 5)
print("Area:", area)
```

### String Operations

```lua
local text = "Ghostlang"

-- String length
print("Length:", strlen(text))

-- String manipulation
print("Uppercase:", str_upper(text))
print("Lowercase:", str_lower(text))

-- Substring
print("Substring:", substr(text, 0, 5))  -- "Ghost"

-- String concatenation
local greeting = "Hello" .. " " .. "World"
print(greeting)
```

## 🔧 Working with Files

### Reading Files

```lua
-- Read a file
local content = file_read("config.txt")
if content then
    print("File content:", content)
else
    print("Failed to read file")
end
```

### Writing Files

```lua
-- Write to a file
local success = file_write("output.txt", "Hello from Ghostlang!")
if success then
    print("File written successfully")
else
    print("Failed to write file")
end
```

## 🎯 Editor Integration Example

Here's a simple example showing how Ghostlang can be used to configure an editor:

```lua
-- Editor configuration example
local config = {
    theme = "dark",
    font_size = 14,
    line_numbers = true,
    auto_save = true
}

-- Key bindings
local keybindings = {
    save = "Ctrl+S",
    quit = "Ctrl+Q",
    find = "Ctrl+F"
}

-- Plugin configuration
function on_file_save(filename)
    print("Saving file:", filename)
    -- Auto-format code
    if str_find(filename, ".zig") then
        print("Formatting Zig code")
    end
end

-- Register the handler
register_event_handler("file_save", on_file_save)
```

## 📚 Next Steps

Now that you have the basics down, explore these topics:

1. **[Language Guide](language-guide.md)** - Complete language reference
2. **[Control Flow](control-flow.md)** - Advanced conditionals and loops
3. **[Functions](functions.md)** - Advanced function usage
4. **[Examples](examples/)** - More complex examples
5. **[Grim Integration](grim-integration.md)** - Using Ghostlang with Grim editor

## 🔍 Getting Help

- **Documentation**: Browse the [docs](README.md) directory
- **Examples**: Check out the [examples](examples/) directory
- **Issues**: Report bugs on [GitHub Issues](https://github.com/your-org/ghostlang/issues)

---

**Happy scripting with Ghostlang!** 🎉