# Getting Started with Ghostlang

Welcome to **Ghostlang**! The project is still early, but the core pieces are now stable enough for experimentation. This guide walks you through installing the toolchain, running the demo, and exploring the currently supported language features.

## 🏗️ Installation

### Prerequisites

- **Zig 0.16.0+** – [Download Zig](https://ziglang.org/download/)
- **Git** – For cloning the repository

### Add as a dependency

```bash
zig fetch --save https://github.com/ghostkellz/ghostlang/archive/refs/heads/main.tar.gz
```

### Build from source

```bash
git clone https://github.com/ghostkellz/ghostlang.git
cd ghostlang
zig build
```

The demo executable is emitted at `./zig-out/bin/ghostlang`.

### Quick smoke test

```bash
zig build run
```

You should see `Script result: 7`, which comes from executing the bundled `3 + 4` sample.

## 🚀 Your First Script

Create `hello.gza` with the following contents:

```ghost
var who = "Ghostlang"
print("Hello, ", who)

var answer = 1 + 2 * 3
print("math result:", answer)

var enable_feature = true
print("feature enabled?", enable_feature)
```

Run it with the demo binary:

```bash
./zig-out/bin/ghostlang hello.gza
```

## � Language Basics (Today)

| Feature | Status | Notes |
| --- | --- | --- |
| Numbers (`f64`) | ✅ | `+`, `-`, `*`, `/`, parentheses, unary minus | 
| Strings | ✅ | Double-quoted with `\n`, `\r`, `\t`, `\"`, `\\` escapes |
| Booleans | ✅ | `true`, `false`, `nil` literals |
| Variables | ✅ | `var name = expression;` declares a global |
| Host calls | ✅ | Call Zig functions registered through `registerFunction` with any number of arguments |
| Control flow | ⚠️ experimental | `if (...) { ... } else { ... }` blocks work, but reassigning existing variables and loops are not implemented yet |
| Tables / arrays / user types | ⏳ | Planned; track the roadmap for progress |

### Expressions & Precedence

Ghostlang now honours standard arithmetic precedence. These produce `7` and `9` respectively:

```ghost
1 + 2 * 3
(1 + 2) * 3
```

### String Literals

Double quotes create immutable strings:

```ghost
"ghost"            // string value
"line\nbreak"     // newline escape
"quote: \"hi\"" // embedded quotes
```

### Host Function Calls

Register Zig callbacks and invoke them from scripts:

```zig
try engine.registerFunction("sum", sumNumbers);
```

```ghost
sum(1, 2, 3)   // => 6 (number)
print("hi")   // returns its first argument so you can chain it
```

Arguments are evaluated left-to-right and results are written back into the first argument register. Return values currently support the same primitive variants as script literals.

### Conditionals

Basic `if / else` blocks are available:

```ghost
var result = 0
if (true) {
    var tmp = 42
    print(tmp)
} else {
    var tmp = 1
    print(tmp)
}
result
```

Blocks require braces; single-line bodies and loop constructs are on the roadmap.

## 🧪 What’s Missing (for now)

- Local re-assignment (`foo = expr`) outside of `var` declarations
- Arrays, tables, user-defined types, and module system
- Looping constructs (`for`, `while`)
- Standard library facilities (I/O helpers, math utilities, etc.)
- CLI / REPL polish

These items are tracked in `ROADMAP.md` and `TODO.md`; contributions and feedback are welcome.

## 📚 Next Steps

- Read the [embedding guide](embedding.md) for host integration tips
- Check the [API reference](api.md) for the exposed Zig surface area
- Follow the roadmap to see when larger language features will arrive

Ghostlang is evolving quickly—expect breaking changes until the beta milestone lands. Please file issues for any crashes, parse errors, or feature requests so we can prioritise the right upgrades.