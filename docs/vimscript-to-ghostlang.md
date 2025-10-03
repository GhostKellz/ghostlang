# Vimscript to Ghostlang Migration Guide

**For Vim/Neovim users transitioning to Ghostlang-based editor plugins**

## Overview

Ghostlang provides a modern, safer alternative to Vimscript for editor automation. This guide helps Vimscript developers understand Ghostlang's approach to plugin development.

## Table of Contents

1. [Philosophy Differences](#philosophy-differences)
2. [Syntax Comparison](#syntax-comparison)
3. [Variables & Scoping](#variables--scoping)
4. [Control Flow](#control-flow)
5. [Buffer Operations](#buffer-operations)
6. [Common Patterns](#common-patterns)
7. [Migration Examples](#migration-examples)

---

## Philosophy Differences

### Vimscript

- Ex command-oriented (`:command`)
- Global state by default
- Many built-in abbreviations (`:h`, `:w`, `:bd`)
- Tightly coupled to Vim/Neovim
- Extensive standard library

### Ghostlang

- Expression-oriented
- Explicit variable declaration
- No abbreviations
- Editor-agnostic (works with any editor)
- Minimal, focused API

---

## Syntax Comparison

### Variables

```vim
" Vimscript
let g:my_var = 10
let l:local_var = 20
let s:script_var = 30

" Ghostlang
var my_var = 10
var local_var = 20
// All variables are scoped
```

### String Concatenation

```vim
" Vimscript
let greeting = 'Hello, ' . name . '!'

" Ghostlang
var greeting = "Hello, " + name + "!"
```

### Conditionals

```vim
" Vimscript
if condition
    echo "yes"
elseif other
    echo "maybe"
else
    echo "no"
endif

" Ghostlang
if (condition) {
    print("yes")
} else if (other) {
    print("maybe")
} else {
    print("no")
}
```

### Loops

```vim
" Vimscript
for item in list
    echo item
endfor

while condition
    " code
endwhile

" Ghostlang
// No for-in loop yet
var i = 0
while (i < count) {
    var item = getItem(i)
    print(item)
    i = i + 1
}

while (condition) {
    // code
}
```

---

## Variables & Scoping

### Scope Prefixes (Vimscript)

```vim
" Vimscript has explicit scope prefixes
let g:global_var = 1      " global
let b:buffer_var = 2      " buffer-local
let w:window_var = 3      " window-local
let t:tab_var = 4         " tab-local
let s:script_var = 5      " script-local
let l:function_var = 6    " function-local
let v:version = 800       " vim variable
let a:arg = 'value'       " function argument

" Ghostlang: simpler scoping
var global_var = 1        // scoped to current block
var buffer_var = 2        // no explicit buffer scope
```

### Type Checking

```vim
" Vimscript (loose typing)
let x = 10
let x = "string"  " allowed

" Ghostlang (runtime type checking)
var x = 10
var x = "string"  // error: redeclaration
```

---

## Control Flow

### If Statements

```vim
" Vimscript
if line('.') > 100
    echo "past line 100"
elseif line('.') > 50
    echo "past line 50"
else
    echo "early in file"
endif

" Ghostlang
var current_line = getCursorLine()
if (current_line > 100) {
    print("past line 100")
} else if (current_line > 50) {
    print("past line 50")
} else {
    print("early in file")
}
```

### Loops

```vim
" Vimscript
for i in range(1, 10)
    echo i
endfor

" Ghostlang
var i = 1
while (i < 11) {
    print(i)
    i = i + 1
}
```

---

## Buffer Operations

### Getting Lines

```vim
" Vimscript
let line = getline(5)
let lines = getline(1, '$')
let last_line = line('$')

" Ghostlang
var line = getLineText(5)
var total_lines = getLineCount()
// No multi-line get - use loop
```

### Setting Lines

```vim
" Vimscript
call setline(5, 'new text')
call append(5, 'appended text')
call deletebufline('%', 5)

" Ghostlang
setLineText(5, "new text")
insertLineAfter(5, "appended text")
deleteLine(5)
```

### Cursor Position

```vim
" Vimscript
let [lnum, col] = getpos('.')[1:2]
call cursor(10, 5)

" Ghostlang
var line = getCursorLine()
var col = getCursorCol()
setCursorPosition(10, 5)
```

### Selection/Visual Mode

```vim
" Vimscript
let [start_line, start_col] = getpos("'<")[1:2]
let [end_line, end_col] = getpos("'>")[1:2]

" Ghostlang
var start_line = getSelectionStart()
var end_line = getSelectionEnd()
```

---

## Common Patterns

### 1. Line Counter

```vim
" Vimscript
function! CountLines()
    let total = line('$')
    let empty = 0

    for lnum in range(1, total)
        if getline(lnum) =~# '^\s*$'
            let empty += 1
        endif
    endfor

    echo printf('Total: %d, Empty: %d', total, empty)
endfunction

" Ghostlang
var total = getLineCount()
var empty = 0

var i = 0
while (i < total) {
    var line = getLineText(i)
    var trimmed = trim(line)
    if (len(trimmed) == 0) {
        empty = empty + 1
    }
    i = i + 1
}

print("Total:", total)
print("Empty:", empty)
```

### 2. Find and Replace

```vim
" Vimscript
function! ReplaceInBuffer(old, new)
    let save_cursor = getpos(".")
    silent! %s/\V\<old>/<new>/g
    call setpos('.', save_cursor)
endfunction

" Ghostlang
var i = 0
var count = getLineCount()
var replacements = 0

while (i < count) {
    var text = getLineText(i)
    var found = indexOf(text, old_text)
    if (found > -1) {
        var new_text = replace(text, old_text, new_text)
        setLineText(i, new_text)
        replacements = replacements + 1
    }
    i = i + 1
}

print("Replaced", replacements, "occurrences")
```

### 3. Comment Toggle

```vim
" Vimscript
function! ToggleComment() range
    for lnum in range(a:firstline, a:lastline)
        let line = getline(lnum)
        if line =~# '^\s*//'
            call setline(lnum, substitute(line, '^\(\s*\)//', '\1', ''))
        else
            call setline(lnum, substitute(line, '^\(\s*\)', '\1// ', ''))
        endif
    endfor
endfunction

" Ghostlang
var start = getSelectionStart()
var end = getSelectionEnd()

var i = start
while (i <= end) {
    var line = getLineText(i)
    var trimmed = trim(line)

    // Check if commented
    var first_two = substring(trimmed, 0, 2)
    if (first_two == "//") {
        // Uncomment
        var new_line = replace(line, "//", "")
        setLineText(i, trim(new_line))
    } else {
        // Comment
        setLineText(i, "// " + line)
    }

    i = i + 1
}
```

---

## Migration Examples

### Example 1: Uppercase Selection

```vim
" Vimscript
function! UppercaseSelection() range
    execute a:firstline . ',' . a:lastline . 's/.*/\U&/'
endfunction
vnoremap <leader>u :call UppercaseSelection()<CR>

" Ghostlang
var start = getSelectionStart()
var end = getSelectionEnd()

var i = start
while (i <= end) {
    var text = getLineText(i)
    var upper = toUpperCase(text)
    setLineText(i, upper)
    i = i + 1
}
```

### Example 2: Duplicate Line

```vim
" Vimscript
function! DuplicateLine()
    let line = getline('.')
    call append('.', line)
endfunction
nnoremap <leader>d :call DuplicateLine()<CR>

" Ghostlang
var line = getCursorLine()
var text = getLineText(line)
insertLineAfter(line, text)
```

### Example 3: Delete Empty Lines

```vim
" Vimscript
function! DeleteEmptyLines()
    g/^\s*$/d
endfunction

" Ghostlang
var i = getLineCount() - 1
while (i >= 0) {
    var text = getLineText(i)
    var trimmed = trim(text)
    if (len(trimmed) == 0) {
        deleteLine(i)
    }
    i = i - 1
}
```

### Example 4: Word Count

```vim
" Vimscript
function! WordCount()
    let words = 0
    for lnum in range(1, line('$'))
        let words += len(split(getline(lnum)))
    endfor
    echo 'Words: ' . words
endfunction

" Ghostlang
var words = 0
var i = 0
var count = getLineCount()

while (i < count) {
    var text = getLineText(i)
    var split_words = split(text, " ")
    words = words + len(split_words)
    i = i + 1
}

print("Words:", words)
```

---

## API Mapping Reference

### Buffer Commands

| Vimscript | Ghostlang | Notes |
|-----------|-----------|-------|
| `line('$')` | `getLineCount()` | Get total lines |
| `getline(n)` | `getLineText(n)` | Get line text |
| `setline(n, text)` | `setLineText(n, text)` | Set line text |
| `append(n, text)` | `insertLineAfter(n, text)` | Insert line |
| `deletebufline('%', n)` | `deleteLine(n)` | Delete line |

### Cursor Commands

| Vimscript | Ghostlang | Notes |
|-----------|-----------|-------|
| `line('.')` | `getCursorLine()` | Current line |
| `col('.')` | `getCursorCol()` | Current column |
| `cursor(l, c)` | `setCursorPosition(l, c)` | Set position |

### String Functions

| Vimscript | Ghostlang | Notes |
|-----------|-----------|-------|
| `len(s)` | `len(s)` | String length |
| `toupper(s)` | `toUpperCase(s)` | Uppercase |
| `tolower(s)` | `toLowerCase(s)` | Lowercase |
| `trim(s)` | `trim(s)` | Remove whitespace |
| `stridx(s, pattern)` | `indexOf(s, pattern)` | Find substring |
| `substitute(s, old, new)` | `replace(s, old, new)` | Replace text |
| `split(s, delim)` | `split(s, delim)` | Split string |
| `join(list, delim)` | `join(arr, delim)` | Join array |

---

## Key Differences Summary

### What Vimscript Has (that Ghostlang doesn't)

- ❌ Ex commands (`:s`, `:g`, `:v`)
- ❌ Ranges (`:%`, `:'<,'>`)
- ❌ Autocommands
- ❌ User commands
- ❌ Key mappings
- ❌ Regular expression engine
- ❌ File I/O
- ❌ System calls
- ❌ Vim-specific functions (`bufnr`, `winnr`, etc.)

### What Ghostlang Has (that Vimscript doesn't)

- ✅ Modern C-like syntax
- ✅ Explicit scoping (block-level)
- ✅ Type safety (runtime)
- ✅ Security sandbox
- ✅ Memory limits
- ✅ Execution timeouts
- ✅ Editor-agnostic API

---

## Migration Strategy

### 1. Start Simple

Begin with basic buffer transformations, not complex automation.

```vim
" Vimscript: complex automation
autocmd BufWritePre * %s/\s\+$//e
autocmd BufRead *.md setlocal spell

" Ghostlang: focus on transformations
// Plugin: trim-whitespace.gza
var i = 0
while (i < getLineCount()) {
    var text = getLineText(i)
    var trimmed = trim(text)
    setLineText(i, trimmed)
    i = i + 1
}
```

### 2. Think Functional, Not Imperative Commands

```vim
" Vimscript: command-based
normal! ggVGgU

" Ghostlang: function-based
var i = 0
while (i < getLineCount()) {
    var text = getLineText(i)
    setLineText(i, toUpperCase(text))
    i = i + 1
}
```

### 3. Use Editor API, Not Ex Commands

```vim
" Vimscript: ex commands
execute '5,10s/foo/bar/g'

" Ghostlang: API calls
var i = 5
while (i <= 10) {
    var text = getLineText(i)
    var new_text = replace(text, "foo", "bar")
    setLineText(i, new_text)
    i = i + 1
}
```

---

## Common Pitfalls

### 1. No Range Support

```vim
" Vimscript
:'<,'>s/foo/bar/g  " won't work in Ghostlang

" Ghostlang: manual loop
var start = getSelectionStart()
var end = getSelectionEnd()
var i = start
while (i <= end) {
    // process
    i = i + 1
}
```

### 2. No Regex

```vim
" Vimscript
if line =~# '^#'  " won't work in Ghostlang

" Ghostlang: use indexOf or substring
var text = getLineText(i)
var first_char = substring(text, 0, 1)
if (first_char == "#") {
    // is comment
}
```

### 3. No Global State

```vim
" Vimscript
let g:my_plugin_state = {}

" Ghostlang: use local variables only
var state = 0
// state lives in current execution only
```

---

## Next Steps

1. **Unlearn**: Forget Vim's ex commands and abbreviations
2. **Learn**: Ghostlang's API-first approach
3. **Read**: `plugin-quickstart.md` for basics
4. **Practice**: Convert simple Vimscript functions
5. **Build**: Create focused, single-purpose plugins

---

## Resources

- **Lua Guide**: See `lua-to-ghostlang.md` for Lua developers
- **Quick Start**: `plugin-quickstart.md` for 30-min intro
- **Cookbook**: `api-cookbook.md` for practical recipes
- **Examples**: `examples/plugins/` for working code

---

## Philosophy

> Vimscript: "Do everything in the editor"
> Ghostlang: "Transform text safely and predictably"

Focus on what Ghostlang does well: buffer transformations, text manipulation, and editor automation. Leave complex workflows to the host editor.

**Happy migrating!** 🚀
