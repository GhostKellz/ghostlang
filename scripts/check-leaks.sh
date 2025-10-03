#!/bin/bash
# Memory leak detection script for local development
# Requires Valgrind to be installed

set -e

echo "=== Ghostlang Memory Leak Detection ==="
echo ""

# Check if Valgrind is installed
if ! command -v valgrind &> /dev/null; then
    echo "Error: Valgrind is not installed"
    echo "Install with: sudo apt-get install valgrind"
    exit 1
fi

# Build with debug symbols
echo "Building with debug symbols..."
zig build -Doptimize=Debug

echo ""
echo "=== Test 1: Basic script execution ==="
echo "var x = 10" | valgrind --leak-check=full --show-leak-kinds=all \
    --track-origins=yes --error-exitcode=1 \
    ./zig-out/bin/ghostlang 2>&1 | tee /tmp/ghostlang-valgrind-1.log

echo ""
echo "=== Test 2: Memory limit allocator ==="
valgrind --leak-check=full --show-leak-kinds=all \
    --track-origins=yes --error-exitcode=1 \
    ./zig-out/bin/memory_limit_test 2>&1 | tee /tmp/ghostlang-valgrind-2.log

echo ""
echo "=== Test 3: Fuzzing tests ==="
timeout 5 valgrind --leak-check=full --error-exitcode=1 \
    ./zig-out/bin/simple_fuzz 2>&1 | tee /tmp/ghostlang-valgrind-3.log || true

echo ""
echo "=== Summary ==="
if grep -q "definitely lost: 0 bytes" /tmp/ghostlang-valgrind-*.log && \
   grep -q "indirectly lost: 0 bytes" /tmp/ghostlang-valgrind-*.log; then
    echo "✓ No memory leaks detected!"
    exit 0
else
    echo "✗ Memory leaks found. Check logs in /tmp/ghostlang-valgrind-*.log"
    exit 1
fi
