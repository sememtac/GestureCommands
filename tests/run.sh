#!/usr/bin/env bash
# Runs every test suite, each in its own process. Uses luajit, or Neovim's built-in LuaJIT (nvim -l).
# Usage: tests/run.sh [suite...]   e.g. tests/run.sh engine ui
set -u
cd "$(dirname "$0")/.."
if command -v luajit >/dev/null 2>&1; then lua=(luajit)
elif command -v nvim >/dev/null 2>&1; then lua=(nvim -l)
else echo "needs luajit or nvim on PATH" >&2; exit 2; fi
suites=("$@")
if [ ${#suites[@]} -eq 0 ]; then for f in tests/*_test.lua; do s=${f#tests/}; suites+=("${s%_test.lua}"); done; fi
failed=0
for s in "${suites[@]}"; do
	out=$(GC_TESTS_QUIET=1 "${lua[@]}" "tests/${s}_test.lua" 2>&1); code=$?
	printf '%-8s %s\n' "$s" "$(printf '%s\n' "$out" | tail -n 1)"
	if [ $code -ne 0 ]; then printf '%s\n' "$out" | grep -v '^ALL PASSED' | sed 's/^/    /'; failed=1; fi
done
exit $failed
