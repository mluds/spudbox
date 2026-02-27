#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf "  \033[31mFAIL\033[0m  %s\n" "$1"; }

printf "\n\033[1m── Lint ──\033[0m\n"

# statix — nix anti-pattern linter
if output=$(statix check . 2>&1) && [ -z "$output" ]; then
  pass "statix"
else
  fail "statix"
  echo "$output" | head -20
fi

# deadnix — unused code detector
if output=$(deadnix -f . 2>&1) && [ -z "$output" ]; then
  pass "deadnix"
else
  fail "deadnix"
  echo "$output" | head -20
fi

# nixfmt — formatting check
if nixfmt --check ./**/*.nix 2>/dev/null; then
  pass "nixfmt"
else
  fail "nixfmt (run 'nixfmt ./**/*.nix' to fix)"
fi

printf "\n\033[1m── Summary ──\033[0m\n"
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf "  \033[32m%d passed, 0 failed\033[0m\n" "$PASS_COUNT"
else
  printf "  \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n" "$PASS_COUNT" "$FAIL_COUNT"
fi

[ "$FAIL_COUNT" -eq 0 ]
