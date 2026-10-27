#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf "  \033[31mFAIL\033[0m  %s\n" "$1"; }

# check LABEL CMD...: pass if CMD succeeds and prints nothing, else show its output.
# The tools come from the flake's devShell: nix develop -c ./lint.sh
check() {
  local label=$1 output
  shift
  if ! command -v "$1" >/dev/null; then
    fail "$label ($1 not installed)"
  elif output=$("$@" 2>&1) && [ -z "$output" ]; then
    pass "$label"
  else
    fail "$label"
    echo "$output" | head -30
  fi
}

# find, not ./**: bash has globstar off, so ** only matches one level deep
mapfile -t nix_files < <(find . -name '*.nix' -not -path './.git/*' | sort)
mapfile -t sh_files < <(find . -name '*.sh' -not -path './.git/*' | sort)

printf "\n\033[1m── Nix ──\033[0m\n"
check "statix (anti-patterns)" statix check .
check "deadnix (unused code)" deadnix -f -- .
# --quiet: nixfmt --check prints nothing when all is well
check "nixfmt (${#nix_files[@]} files; fix: nixfmt \$(find . -name '*.nix'))" \
  nixfmt --check --quiet "${nix_files[@]}"

printf "\n\033[1m── Shell ──\033[0m\n"
# Scripts built with writeShellApplication are also checked at build time;
# these run as-is (template/deploy.sh, test.sh, ...). media-fixup.sh has no shebang.
check "shellcheck (${#sh_files[@]} files)" shellcheck --shell=bash "${sh_files[@]}"

printf "\n\033[1m── Python ──\033[0m\n"
check "ruff check (config: ruff.toml)" ruff check --quiet --output-format concise .
check "ruff format (fix: ruff format .)" ruff format --check --quiet .

printf "\n\033[1m── Repo ──\033[0m\n"
check "gitleaks (no plaintext secrets; config: .gitleaks.toml)" \
  gitleaks dir --no-banner --redact --log-level error .
check "typos (spelling; config: _typos.toml)" typos --format brief .

printf "\n\033[1m── Summary ──\033[0m\n"
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf "  \033[32m%d passed, 0 failed\033[0m\n" "$PASS_COUNT"
else
  printf "  \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n" "$PASS_COUNT" "$FAIL_COUNT"
fi

[ "$FAIL_COUNT" -eq 0 ]
