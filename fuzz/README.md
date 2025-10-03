# Ghostlang Fuzzing Infrastructure

This directory contains fuzzing harnesses for testing Ghostlang's robustness against malformed and malicious input.

## Fuzzing Targets

### Parser Fuzzing (`parser_fuzz.zig`)
Tests the parser's ability to handle arbitrary input without crashing. This includes:
- Malformed syntax
- Deeply nested structures
- Invalid tokens
- Buffer boundary conditions

### VM Fuzzing (`vm_fuzz.zig`)
Tests the VM's execution safety with focus on:
- Execution timeout enforcement
- Memory limit enforcement
- Invalid instruction sequences (via malformed parse trees)
- Stack manipulation edge cases

## Running Fuzzers

### Using Zig's Built-in Fuzzing
```bash
# Fuzz the parser (basic mode)
zig build fuzz-parser

# Fuzz the VM
zig build fuzz-vm
```

### Using AFL++ (Advanced)
```bash
# Install AFL++
# Ubuntu: apt-get install afl++
# macOS: brew install afl++

# Compile with AFL instrumentation
afl-clang-fast++ -o parser_fuzz fuzz/parser_fuzz.zig -I.

# Run AFL fuzzer
afl-fuzz -i fuzz/corpus -o fuzz/findings ./parser_fuzz @@
```

### Using libFuzzer (LLVM)
```bash
# Build with libFuzzer support
zig build-exe fuzz/parser_fuzz.zig -fsanitize=fuzzer

# Run libFuzzer
./parser_fuzz fuzz/corpus
```

## Corpus

The `corpus/` directory contains seed inputs for fuzzing:
- `basic.ghost` - Valid basic arithmetic
- `variable.ghost` - Variable declarations and assignments
- `control_flow.ghost` - Loops and conditionals
- `malformed.ghost` - Intentionally broken syntax for edge case testing

## Findings

Fuzzer findings (crashes, hangs, etc.) will be stored in:
- `findings/crashes/` - Inputs that caused crashes
- `findings/hangs/` - Inputs that caused timeouts
- `findings/queue/` - Interesting inputs discovered during fuzzing

## Best Practices

1. **Run fuzzing continuously**: Set up CI to run fuzzing on every commit
2. **Minimize crashes**: Use `afl-tmin` to reduce crash test cases to minimal reproducers
3. **Update corpus**: Add interesting valid inputs to the corpus regularly
4. **Monitor coverage**: Use `afl-cov` to track code coverage from fuzzing
5. **Triage quickly**: Address any crashes or hangs discovered immediately

## Integration with CI

The GitHub Actions workflow includes fuzzing as part of the test suite:
```yaml
- name: Run fuzzing tests
  run: |
    zig build fuzz-parser -- -runs=10000
    zig build fuzz-vm -- -runs=10000
```

## Expected Results

**Good signs:**
- No crashes after 1M+ executions
- Graceful error handling for all malformed inputs
- All timeouts and memory limits enforced correctly

**Red flags:**
- Segfaults or memory corruption
- Infinite loops without timeout
- Unbounded memory allocation
- Panic/assert failures in production code

## Security Considerations

Fuzzing is critical for security because:
- Malicious plugins may craft inputs designed to exploit parser bugs
- Untrusted scripts should never crash the editor
- Memory safety violations could lead to code execution
- DoS attacks via infinite loops must be prevented

The fuzzing harnesses run with sandboxed security settings (`allow_io=false`, `deterministic=true`) to ensure we're testing the worst-case scenario.
