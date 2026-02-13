# Ghostlang Security Guide

Best practices for running Ghostlang scripts securely.

## Security Model

Ghostlang uses a capability-based security model. Scripts have no capabilities by default and must be explicitly granted access to system resources.

## Security Levels

### Sandbox (Default)

Most restrictive. No system access.

```zig
var vm = try VM.init(allocator);
// Default security - sandbox mode
```

**Capabilities**:
- Pure computation
- Memory allocation (within limits)
- Built-in math/string functions

**Blocked**:
- File system access
- Network access
- Process execution
- System information

### Restricted

Limited access to specific resources.

```zig
var security = SecurityContext.init();
security.allow(.file_read);  // Can read files
security.addPath("/allowed/path");  // Only this path
vm.setSecurityContext(security);
```

### Trusted

Full access (only for fully trusted scripts).

```zig
var security = SecurityContext.trusted();
vm.setSecurityContext(security);
```

## Capability Reference

| Capability | Description | Risk |
|------------|-------------|------|
| `file_read` | Read files | Low - data exposure |
| `file_write` | Write/create files | High - data loss |
| `file_delete` | Delete files | High - data loss |
| `network` | Network connections | High - data exfil |
| `process` | Execute processes | Critical |
| `system_info` | System information | Low - fingerprinting |
| `env_read` | Read env variables | Medium - credential exposure |
| `env_write` | Set env variables | High - privilege escalation |

## Resource Limits

Always set resource limits for untrusted code:

```zig
// Memory limit (bytes)
vm.setMemoryLimit(64 * 1024 * 1024);  // 64MB

// Instruction limit (prevents infinite loops)
vm.setInstructionLimit(1_000_000);

// Stack depth limit
vm.setStackLimit(1000);

// Execution timeout (microseconds)
vm.setTimeout(5_000_000);  // 5 seconds
```

## Path Restrictions

When allowing file access, restrict to specific paths:

```zig
var security = SecurityContext.init();
security.allow(.file_read);
security.allow(.file_write);

// Only allow access to specific directories
security.addPath("/app/data");
security.addPath("/tmp/app");

// Deny sensitive paths explicitly
security.denyPath("/etc");
security.denyPath("/home");

vm.setSecurityContext(security);
```

## Input Validation

### Script Source

Validate script source before execution:

```zig
// Size limit
if (source.len > 1024 * 1024) {
    return error.ScriptTooLarge;
}

// Parse-only validation
var parser = Parser.init(allocator);
const result = parser.parse(source);
if (result.hasErrors()) {
    return error.InvalidScript;
}
```

### Script Arguments

Validate data passed to scripts:

```zig
// Type checking
fn validateArgs(args: []const ScriptValue) !void {
    for (args) |arg| {
        switch (arg) {
            .string => |s| {
                if (s.len > 10000) return error.StringTooLong;
            },
            .table => |t| {
                if (t.size() > 1000) return error.TableTooLarge;
            },
            else => {},
        }
    }
}
```

## Cryptographic Operations

### Signature Verification

Always verify signatures for authenticated operations:

```zig
const web3 = @import("web3.zig");

// Verify before trusting
if (!web3.verifySignature(message, signature, public_key)) {
    return error.InvalidSignature;
}
```

### Key Management

```zig
// Generate secure random keys
var key: [32]u8 = undefined;
std.crypto.random.bytes(&key);

// Clear sensitive data when done
@memset(&key, 0);
```

## Contract Security

### Access Control

```ghostlang
-- Contract with access control
local owner = nil

function constructor(deployer)
    owner = deployer
end

function onlyOwner()
    if msg.sender ~= owner then
        error("unauthorized")
    end
end

function withdraw(amount)
    onlyOwner()
    -- perform withdrawal
end
```

### Reentrancy Protection

```ghostlang
local locked = false

function withdraw(amount)
    if locked then
        error("reentrancy detected")
    end

    locked = true

    -- perform external call
    transfer(msg.sender, amount)

    locked = false
end
```

### Integer Overflow

```ghostlang
function safeAdd(a, b)
    local result = a + b
    if result < a then
        error("overflow")
    end
    return result
end

function safeSub(a, b)
    if b > a then
        error("underflow")
    end
    return a - b
end
```

## Logging and Auditing

Log security-relevant events:

```zig
const SecurityLog = struct {
    fn logAccess(script: []const u8, capability: Capability, allowed: bool) void {
        std.log.info("Security: script={s} capability={} allowed={}", .{
            script, capability, allowed
        });
    }

    fn logViolation(script: []const u8, attempted: Capability) void {
        std.log.warn("Security violation: script={s} attempted={}", .{
            script, attempted
        });
    }
};
```

## Testing Security

### Fuzz Testing

```zig
test "fuzz script input" {
    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();

    for (0..1000) |_| {
        var input: [256]u8 = undefined;
        random.bytes(&input);

        var vm = try VM.init(std.testing.allocator);
        defer vm.deinit();

        // Should not crash, may error gracefully
        _ = vm.parse(&input) catch continue;
    }
}
```

### Capability Tests

```zig
test "sandbox blocks file access" {
    var vm = try VM.init(std.testing.allocator);
    defer vm.deinit();

    // Default sandbox
    const result = vm.run(
        \\local f = io.open("/etc/passwd", "r")
    );

    try std.testing.expectError(error.SecurityViolation, result);
}
```

## Checklist

Before deploying Ghostlang in production:

- [ ] Set memory limits appropriate for workload
- [ ] Set instruction limits to prevent infinite loops
- [ ] Configure minimal required capabilities
- [ ] Restrict file system paths
- [ ] Validate all script inputs
- [ ] Enable security logging
- [ ] Test with malicious inputs
- [ ] Review third-party scripts before running
- [ ] Keep Ghostlang updated for security patches
- [ ] Monitor resource usage in production
