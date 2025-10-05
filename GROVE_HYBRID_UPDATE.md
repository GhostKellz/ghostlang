# Grove Hybrid Update Guide for Ghostlang

**Date:** 2025-10-04
**Grove Version:** 0.1.1
**Ghostlang Integration:** Full tree-sitter grammar with control flow extensions
**Status:** ✅ Production Ready

## Overview

This document describes the **hybrid integration** between Ghostlang's tree-sitter grammar and Grove's language support system. It serves as a reference for maintaining synchronization as Ghostlang's parser evolves.

## What We Built

Grove now has **full Ghostlang support** with all Phase A control flow extensions integrated:

### Grammar Features
- ✅ Numeric `for` loops: `for i = start, stop[, step] do ... end`
- ✅ `repeat...until` blocks: `repeat ... until <condition>`
- ✅ Negative step support in numeric loops
- ✅ Nested loop constructs
- ✅ All Lua-style keywords: `do`, `end`, `repeat`, `until`
- ✅ **Generic `for` loops**: `for key[, value] in iterator do ... end`
- ✅ **Function literals**: `local function` declarations and anonymous `function (...) ... end`

### Integration Components
- ✅ **Parser**: `vendor/tree-sitter-ghostlang/src/parser.c` compiled into Grove
- ✅ **Queries**: All 4 query files updated (highlights, locals, textobjects, injections)
- ✅ **Tests**: 16/16 corpus tests passing (100% coverage)
- ✅ **Build**: Full Zig build integration with tree-sitter 25.0 (ABI 15)

---

## Architecture Decision: Approach A (Full Repo Vendoring)

### Why Full Repo vs. Flattened?

Grove uses **two vendoring patterns**:

| Pattern | Location | Use Case | Examples |
|---------|----------|----------|----------|
| **A: Full Repo** | `vendor/tree-sitter-*/` | Active development, needs tests | Rust, **Ghostlang** |
| **B: Flattened** | `vendor/grammars/*/` | Stable upstream, parser only | Bash, Python, JS |

**Ghostlang uses Approach A** because:

1. **Active Development** – Parser evolving rapidly (Phase A extensions, future Lua syntax)
2. **Runnable Tests** – Can execute `npm install && npm test` inside Grove's vendor directory
3. **Easy Updates** – Replace entire directory when Ghostlang tags a release
4. **Full Infrastructure** – Includes `grammar.js`, `tree-sitter.json`, corpus tests

### Directory Structure

```
vendor/tree-sitter-ghostlang/          ← Full repo from github.com/ghostkellz/ghostlang
├── src/
│   └── parser.c                       ← Referenced in build.zig
├── queries/
│   ├── highlights.scm                 ← Keyword captures, loop variables
│   ├── locals.scm                     ← Scoping, __for_* hiding
│   ├── textobjects.scm                ← Loop block selections
│   └── injections.scm                 ← Embedded language support
├── test/
│   └── corpus/
│       ├── basic.txt                  ← Original tests
│       └── control_flow.txt           ← NEW: numeric for/repeat tests (16 tests)
├── grammar.js                         ← Source of truth
├── tree-sitter.json                   ← ABI 15 config
├── package.json
└── node_modules/                      ← Built by npm install
```

---

## Update Workflow: Ghostlang → Grove

When Ghostlang's parser changes (new control flow, keywords, AST nodes), follow this workflow:

### 1. Ghostlang Side (Your Repo)

**A. Update Grammar**
```bash
cd /path/to/ghostlang/tree-sitter-ghostlang
# Edit grammar.js
npx tree-sitter generate
npm test  # Ensure corpus tests pass
```

**B. Add Corpus Tests**
```bash
# Create/update test/corpus/*.txt files
# Example: test/corpus/phase_a_lua.txt for new Lua syntax
npm test  # Verify 100% pass rate
```

**C. Update Queries** (if needed)
```bash
# queries/highlights.scm   → New keywords
# queries/locals.scm       → New scope rules
# queries/textobjects.scm  → New AST nodes
```

**D. Tag Release**
```bash
git tag v0.x.y
git push origin v0.x.y
```

### 2. Grove Side (This Repo)

**A. Pull Updated Grammar**
```bash
cd /data/projects/grove
git clone https://github.com/ghostkellz/ghostlang /tmp/ghostlang-update
rm -rf vendor/tree-sitter-ghostlang
cp -r /tmp/ghostlang-update/tree-sitter-ghostlang vendor/
```

**B. Verify Grammar Builds**
```bash
cd vendor/tree-sitter-ghostlang
npm install
npx tree-sitter generate
npm test  # Should show 100% pass rate
```

**C. Update Grove Build (if needed)**

Only if Ghostlang adds a **scanner** (scanner.c):

**build.zig**
```zig
const ghostlang_grammar_source = b.path("vendor/tree-sitter-ghostlang/src/parser.c");
const ghostlang_scanner_source = b.path("vendor/tree-sitter-ghostlang/src/scanner.c");  // ADD THIS

// Later in file:
mod.addCSourceFile(.{ .file = ghostlang_scanner_source, .flags = &.{"-std=c99"} });
```

**D. Run Grove Tests**
```bash
cd /data/projects/grove
zig build test --summary all  # Should pass 5/5 steps
```

**E. Update Documentation**

**README.md** – Update Ghostlang section:
```markdown
### Ghostlang Support Snapshot

- **Control flow**: [List new features]
- **Grammar tests**: X/X tree-sitter corpus tests passing (100% coverage)
```

**GHOSTLANG_TODO.md** – Mark completed items:
```markdown
### ✅ [Feature Name] - COMPLETED
- ✅ Grammar – [What changed]
- ✅ Tests – [New corpus files]
```

---

## Current Integration Status

### Files Modified in This Update

**Grammar & Queries:**
- `vendor/tree-sitter-ghostlang/grammar.js` → Added `numeric_for_statement`, `repeat_statement`
- `vendor/tree-sitter-ghostlang/queries/highlights.scm` → Keywords: `do`, `end`, `repeat`, `until`
- `vendor/tree-sitter-ghostlang/queries/locals.scm` → Loop scoping, `__for_*` hiding
- `vendor/tree-sitter-ghostlang/queries/textobjects.scm` → Loop block selections
- `vendor/tree-sitter-ghostlang/test/corpus/control_flow.txt` → **NEW** 16 tests

**Grove Build:**
- `build.zig` → `vendor/tree-sitter-ghostlang/src/parser.c`
- `build.zig.zon` → Added `vendor/tree-sitter-ghostlang` to `.paths`
- `src/languages.zig` → Already had `extern fn tree_sitter_ghostlang()` (no changes needed)

**Documentation:**
- `README.md` → Updated Ghostlang section with control flow features
- `GHOSTLANG_TODO.md` → Marked "Immediate follow-up" as ✅ COMPLETED

### Test Coverage

**Grammar Tests (tree-sitter):**
```
16/16 tests passing (100%)

Basic Tests (7):
✓ Variable declaration
✓ Function declaration
✓ If statement
✓ Editor API calls
✓ Object literal
✓ Array literal and loops
✓ Comments

Control Flow Tests (9):
✓ Numeric for loop - basic
✓ Numeric for loop - with step
✓ Numeric for loop - negative step
✓ Numeric for loop - nested
✓ Numeric for loop - using variable in body
✓ Repeat until loop - basic
✓ Repeat until loop - multiple statements
✓ Repeat until loop - nested
✓ Repeat until - with function call
```

**Grove Build Tests:**
```
zig build test --summary all
→ 5/5 steps succeeded
→ 1/1 tests passed
```

---

## Quick Reference Commands

### Update Grammar from Ghostlang
```bash
# In Grove repo
git clone https://github.com/ghostkellz/ghostlang /tmp/ghostlang-sync
rm -rf vendor/tree-sitter-ghostlang
cp -r /tmp/ghostlang-sync/tree-sitter-ghostlang vendor/
cd vendor/tree-sitter-ghostlang
npm install && npm test
cd ../..
zig build test --summary all
```

### Test Grammar Locally (in Grove)
```bash
cd vendor/tree-sitter-ghostlang
npm test                              # Run corpus tests
npx tree-sitter parse test.ghost     # Parse sample file
```

### Verify Grove Integration
```bash
zig build test --summary all          # All Grove tests
zig build                             # Build with Ghostlang parser
```

---

## Phase A Preparation (Future)

When Ghostlang implements full Lua-style syntax on `feature/parser-phase-a`:

### Expected Changes
1. **Keywords**: `then`, `elseif` (grammar already includes `local`, `function`, `in`)
2. **Iterator sugar**: ensure grammar nodes align with `generic_for_statement`
3. **Function enhancements**: parameter lists, nested scopes, return handling (alignment work continues in Phase B)

### Grove Update Checklist
- [ ] Update `grammar.js` with new rules
- [ ] Add keywords to `highlights.scm`
- [ ] Extend `locals.scm` for `local` scoping
- [ ] Create corpus tests: `test/corpus/phase_a_lua.txt`
- [ ] Create paired fixtures: `phase_a_brace.ghost`, `phase_a_lua.ghost`
- [ ] Verify all tests pass before merging to main

---

## AST Node Reference

### Current Nodes (Main Branch)

**Statements:**
- `source_file` – Root
- `variable_declaration` – `var x = 5;`
- `function_declaration` – `function foo() { ... }`
- `if_statement` – `if (cond) { ... } else { ... }`
- `while_statement` – `while (cond) { ... }`
- `for_statement` – C-style `for (var i = 0; i < 10; i++)` or `for (var x in arr)`
- `numeric_for_statement` – **NEW** `for i = 1, 10[, step] do ... end`
- `repeat_statement` – **NEW** `repeat ... until cond`
- `return_statement` – `return expr;`
- `block_statement` – `{ ... }`

**Fields:**
- `numeric_for_statement`:
  - `variable` (identifier)
  - `start` (expression)
  - `stop` (expression)
  - `step` (expression, optional)
  - `body` (repeat of statements)

- `repeat_statement`:
  - `body` (repeat of statements)
  - `condition` (expression)

---

## Troubleshooting

### Grammar Tests Failing After Update

**Symptom:** `npm test` shows failures in `control_flow.txt`

**Fix:**
1. Check AST structure changed → Update expected output in corpus tests
2. Re-generate parser: `npx tree-sitter generate`
3. If operator precedence changed, adjust test expectations

### Grove Build Errors

**Symptom:** `zig build` fails with "parser.c not found"

**Fix:**
```bash
cd vendor/tree-sitter-ghostlang
npx tree-sitter generate  # Regenerate parser.c
cd ../..
zig build
```

### Query Validation Errors

**Symptom:** Grove complains about invalid query syntax

**Fix:**
```bash
cd vendor/tree-sitter-ghostlang
npx tree-sitter test  # Validates queries automatically
# Or manually:
npx tree-sitter query queries/highlights.scm
```

---

## Contact & Maintenance

**Ghostlang Repo:** https://github.com/ghostkellz/ghostlang
**Grove Repo:** https://github.com/GhostKellz/grove
**Tree-sitter Version:** 25.0+ (ABI 15)
**Zig Version:** 0.16.0-dev+

**Maintainer Notes:**
- Ghostlang grammar lives in Ghostlang repo as source of truth
- Grove vendors full grammar directory for easy updates
- Update workflow: Ghostlang tags release → Grove copies directory → Tests pass → Ship

**Next Milestones:**
- [ ] Phase A: Full Lua syntax (feature branch)
- [ ] Phase B: Advanced features (TBD)
- [ ] Grove v1.0: Production-ready multi-grammar support

---

**Last Updated:** 2025-10-04
**Integration Version:** Grove 0.1.1 + Ghostlang main branch (numeric for/repeat support)
**Status:** ✅ All systems green. Ready for production use in Grim editor.
