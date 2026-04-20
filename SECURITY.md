# Security Policy

## Supported Versions

Security fixes are targeted at the latest development line in this repository.

| Version | Supported |
| --- | --- |
| `main` / latest unreleased | Yes |
| older tags and archived snapshots | No |

## Reporting A Vulnerability

Please do not open a public issue for suspected security vulnerabilities.

Report privately with:

- a clear description of the issue
- affected files or subsystems
- reproduction steps or a minimal script
- impact assessment if known

If a private security contact is not yet published for this repository, use the maintainer's private contact channel or GitHub security advisories if enabled.

## Scope

Ghostlang includes sandboxing and resource-limiting features, but security should be treated as an actively verified property, not a blanket guarantee.

Areas most likely to matter for security reports:

- sandbox or policy bypasses
- memory limit or timeout bypasses
- unsafe file or process access from restricted execution modes
- crashes, memory corruption, or unbounded resource consumption triggered by untrusted scripts
- parser, VM, FFI, or embedding behaviors that violate documented isolation guarantees

## Current Security Model

The project currently aims to provide:

- execution timeout limits
- memory usage limits
- security-context based access control
- deterministic sandboxed execution modes for restricted embeddings

These controls should always be validated with tests before being relied on for production isolation.

## Response Expectations

When a report is reproducible and in scope, the expected response is:

1. confirm impact and affected versions
2. prepare a fix with regression coverage when possible
3. coordinate disclosure timing if the issue is significant

## Hardening Guidance

If you embed Ghostlang in a security-sensitive system:

- run only the latest patched revision you have verified
- keep resource limits enabled
- avoid granting file, process, or host integration capabilities unless required
- treat host-exposed native functions as part of your attack surface
