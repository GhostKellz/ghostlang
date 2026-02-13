# Ghostlang Troubleshooting Guide

Common issues and solutions when working with Ghostlang.

## Runtime Errors

### Memory Limit Exceeded

**Error**: `error: memory limit exceeded`

**Cause**: Script allocations exceeded the configured memory limit.

**Solutions**:
```zig
// Increase memory limit (default is 64MB)
vm.setMemoryLimit(128 * 1024 * 1024); // 128MB

// Or disable limit for trusted scripts
vm.setMemoryLimit(0);
```

**Prevention**: Avoid creating large tables in loops without cleanup.

### Instruction Limit Exceeded

**Error**: `error: instruction limit exceeded`

**Cause**: Script ran too many instructions (infinite loop protection).

**Solutions**:
```zig
// Increase instruction limit
vm.setInstructionLimit(10_000_000);

// Disable for trusted scripts
vm.setInstructionLimit(0);
```

**Check for**: Infinite loops, deeply recursive functions.

### Stack Overflow

**Error**: `error: stack overflow`

**Cause**: Too many nested function calls or deeply recursive code.

**Solutions**:
- Refactor recursive algorithms to iterative
- Increase stack size if needed
- Check for accidental infinite recursion

### Undefined Variable

**Error**: `error: undefined variable 'x'`

**Cause**: Variable used before declaration.

**Solutions**:
```ghostlang
-- Wrong
print(x)
local x = 10

-- Correct
local x = 10
print(x)
```

### Type Error

**Error**: `error: expected number, got string`

**Cause**: Operation applied to wrong type.

**Solutions**:
```ghostlang
-- Use type conversion
local num = tonumber(str_value)

-- Check type before operations
if type(value) == "number" then
    result = value + 1
end
```

## Parser Errors

### Unexpected Token

**Error**: `error: unexpected token 'end'`

**Cause**: Mismatched block delimiters or syntax error.

**Check**:
- All `if` statements have matching `then`/`end`
- All `function` declarations have `end`
- All `for`/`while` loops have `do`/`end`

### Missing Expression

**Error**: `error: expected expression`

**Cause**: Incomplete statement.

**Examples**:
```ghostlang
-- Wrong
local x =
local y = 10

-- Correct
local x = nil
local y = 10
```

## Security Context

### Security Check Failed

**Error**: `error: security check failed - file_io`

**Cause**: Script attempted operation not allowed by security policy.

**Solutions**:
```zig
// Allow specific capabilities
var security = SecurityContext.init();
security.allow(.file_io);
security.allow(.network);
vm.setSecurityContext(security);
```

**Note**: Only enable capabilities needed by the script.

### Sandbox Violation

**Error**: `error: sandbox violation`

**Cause**: Script tried to access restricted system resources.

**Solutions**:
- Review script for system calls
- Whitelist required paths/operations
- Run in appropriate security level

## Contract/Web3 Errors

### Invalid Signature

**Error**: `error: invalid signature`

**Cause**: Cryptographic signature verification failed.

**Check**:
- Correct public key for signer
- Message hasn't been modified
- Signature format is correct (Ed25519 or secp256k1)

### Insufficient Balance

**Error**: `error: insufficient balance`

**Cause**: Account doesn't have enough funds for transaction.

**Solution**: Check balance before transfers:
```ghostlang
local balance = getBalance(sender)
if balance >= amount then
    transfer(sender, recipient, amount)
end
```

### Contract Not Found

**Error**: `error: contract not found`

**Cause**: Calling non-existent contract address.

**Check**:
- Contract was deployed successfully
- Using correct address
- Contract wasn't destroyed

### Gas Exhausted

**Error**: `error: out of gas`

**Cause**: Transaction ran out of gas.

**Solutions**:
- Increase gas limit
- Optimize contract code
- Break complex operations into smaller transactions

## Editor Integration

### Buffer Not Found

**Error**: `error: buffer not found`

**Cause**: Editor API called without active buffer context.

**Solution**: Ensure editor context is set:
```zig
var ctx = EditorContext{ .buffer = buffer };
vm.setEditorContext(&ctx);
```

### Invalid Cursor Position

**Error**: `error: cursor position out of bounds`

**Cause**: Script set cursor beyond buffer limits.

**Solution**: Validate positions before setting:
```ghostlang
local lines = buffer:lineCount()
if line <= lines then
    buffer:setCursor(line, col)
end
```

## Performance Issues

### Slow Script Execution

**Symptoms**: Scripts take longer than expected.

**Diagnostics**:
```zig
// Enable timing
const report = try vm.runTimed(bytecode);
std.debug.print("Execution time: {}ms\n", .{report.duration_ms});
```

**Common Causes**:
1. String concatenation in loops (use table.concat)
2. Repeated table lookups (cache in local)
3. Unnecessary function calls in tight loops

**Optimizations**:
```ghostlang
-- Slow
for i = 1, 1000 do
    result = result .. tostring(i)  -- Creates new string each time
end

-- Fast
local parts = {}
for i = 1, 1000 do
    parts[i] = tostring(i)
end
result = table.concat(parts)
```

### High Memory Usage

**Diagnostics**:
```zig
const stats = vm.getMemoryStats();
std.debug.print("Allocated: {}KB\n", .{stats.allocated / 1024});
```

**Common Causes**:
1. Large tables not being garbage collected
2. Closures capturing unnecessary data
3. Circular references

**Solutions**:
- Set unused variables to `nil`
- Use weak references where appropriate
- Avoid creating objects in hot loops

## Debugging Tips

### Enable Debug Output

```zig
vm.setDebugLevel(.verbose);
```

### Print Stack Traces

```ghostlang
function problematic()
    error("Something went wrong")
end

-- Wrap in pcall for stack trace
local ok, err = pcall(problematic)
if not ok then
    print("Error:", err)
    print(debug.traceback())
end
```

### Inspect Values

```ghostlang
-- Print table contents
function dump(t, indent)
    indent = indent or ""
    for k, v in pairs(t) do
        if type(v) == "table" then
            print(indent .. k .. ":")
            dump(v, indent .. "  ")
        else
            print(indent .. k .. " = " .. tostring(v))
        end
    end
end
```

## Getting Help

- Check [language-guide.md](language-guide.md) for syntax reference
- See [api.md](api.md) for built-in functions
- Review [examples/](examples/) for working code
- File issues at the project repository
