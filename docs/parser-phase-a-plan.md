# Parser Phase A Plan

## Context

Phase A focuses on unifying Ghostlang's control-flow parsing so that both brace-based and Lua-style syntax are first-class across all statements. The current `Parser` implementation in `src/root.zig` already supports mixed styles for `if`, `while`, and function bodies via `parseConditionalBody`, `parseLuaScopedBlock`, and `parseBlock`, but coverage is incomplete and several Lua keywords are still missing. This plan captures the gaps, defines goals, and outlines the workstream required to deliver Phase A.

## Current Capabilities Snapshot

- **Blocks** – `{ ... }` blocks and Lua `do ... end` blocks are supported. Conditional branches can auto-detect consistent style within a construct.
- **If / Elseif / Else** – Works with `if (...) {}` and `if cond then ... elseif ... else ... end`. Brace bodies require explicit parentheses around conditions; Lua style uses `then`/`end` terminators.
- **While** – Accepts both `while (cond) {}` and `while cond do ... end`, including `break`/`continue` unwinding logic.
- **For range** – Only brace + `..` range form is implemented (`for i in 0 .. 10 { ... }`). Lua numeric and generic `for` forms are not yet available.
- **Logical operators** – Both symbolic (`&&`, `||`) and keyword (`and`, `or`) variants are recognized.
- **Function declarations** – `function name(...) { ... }` already accepts Lua bodies (`function name(...) do ... end`). Anonymous functions or Lua-style `local function` are not implemented.

## Dual-Syntax Requirements

To complete Phase A, Ghostlang must parse these constructs interchangeably in brace and Lua forms:

1. `if` / `elseif` / `else` with consistent branch style per statement.
2. `while` loops with `do ... end` as the Lua body option.
3. **New:** `repeat ... until` loop for Lua parity, including condition placement after the block.
4. **New:** `for` statements
   - Numeric loop: `for i = start, stop[, step] do ... end`
   - Generic loop: `for k, v in iterator do ... end`
5. `function` declarations and expressions
   - Allow Lua `function foo()` bodies and local declarations (`local function foo()`)
   - Support anonymous functions (`function (...) ... end`) as values.
6. Control keywords must cross-map:
   - `break`, `continue` in both syntaxes.
   - Introduce `goto`? (explicitly **out of scope** for Phase A unless required by Grim embedding).
7. Enforce style consistency per construct to avoid mixing brace and `end` terminators within the same block (current behavior).

## Phase A Deliverables

| Workstream | Description | Exit Criteria |
|------------|-------------|---------------|
| Parser Enhancements | Implement missing Lua equivalents (`repeat/until`, numeric & generic `for`, local functions, anonymous functions). Normalize dual style handling helpers and resolve scope unwind logic for new constructs. | New unit/parser tests cover each construct in brace and Lua forms; CI passes. |
| VM/Instruction Support | Extend opcode set as needed (e.g., repeat loops, generic iterator protocol). Ensure existing control flow (jump, scope) logic works with added constructs. | No regressions in existing interpreter behavior; new loop instructions validated via tests. |
| Branch Staging | Create `feature/parser-phase-a` from latest `main`. Update `TODO.md` with Phase A checklist. | Branch pushed and linked in CODEX tracker. |
| Docs & Examples | Update language & syntax guides with dual examples. Expand Lua migration guide to explain new parity guarantees. | Docs published in `/docs` with illustrative snippets. |
| QA & Tooling | Add grove grammar fixtures covering new tokens/keywords. Wire parser smoke tests into CI. | Grove pipeline green with new fixtures; CI smoke suite runs on branch. |

## Implementation Steps

1. **Branch Setup**
   - Cut `feature/parser-phase-a` from `main`.
   - Enable nightly CI to run parser smoke tests against this branch until merged.

2. **Control Flow Coverage**
   - Implement `parseRepeatUntilStatement`; share block parsing helpers.
   - Extend `parseForRangeStatement` or create new `parseForNumeric`/`parseForGeneric` functions.
   - Add step expression parsing and iterator binding utilities.
   - Update loop stack bookkeeping to support `repeat` (condition evaluated at end) and nested generic loops.

3. **Function Handling**
   - Introduce `parseLocalFunctionDeclaration` and `parseFunctionExpression`.
   - Ensure anonymous functions emit `load_const` script functions with captured parameters; verify scope depth tracking.

4. **VM Updates**
   - Add instructions for iterator protocol (likely `call_iterator`, `iterator_has_next`, `iterator_next`).
   - Validate `repeat/until` uses inverted condition with `jump_if_true`/`jump_if_false` as needed.

5. **Testing**
   - Add parser test harness (if missing) or extend existing integration tests.
   - Cover edge cases: mixed styles in same file, nested Lua/brace constructs, empty bodies, `break`/`continue` within new loops.

6. **Documentation & Examples**
   - Provide code samples for each construct in both syntaxes.
   - Update migration guide and Grove grammar docs (tracked separately in this sprint).

## Risks & Mitigations

- **Scope unwinding bugs** – Ensure loop contexts record base scope depth and unwind correctly when `continue` or `break` occurs inside Lua-style loops.
- **Instruction explosion** – Prefer reusing existing VM opcodes; only add new ones if necessary. Document any instruction changes for Grim integration teams.
- **Parser regressions** – Introduce incremental unit tests per construct before refactoring large sections.

## Success Metrics

- All Phase A constructs parse identically in brace and Lua forms.
- New parser tests run under CI and pass on the staging branch.
- Documentation reflects the dual-syntax behavior.
- Grove grammar PR prepared with token updates before implementation merge.

## Next Actions

1. Approve this plan with the language council.
2. Create `feature/parser-phase-a` branch and update CODEX tracker.
3. Begin implementation following the steps above while coordinating docs and grammar workstreams.
