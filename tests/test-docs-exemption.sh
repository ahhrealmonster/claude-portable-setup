#!/bin/bash
# Executable guard for the documentation-coverage exemption (#17).
#
# `harness check-docs` abstains on this repo — "0 source files scanned" — and
# that is correct rather than broken: `checkDocCoverage` globs
# `**/*.{ts,js,tsx,jsx,mjs,cjs}`, and this bundle is bash, JSON and Markdown. No
# `rootDir` value can produce a non-zero denominator for a repo with nothing the
# scanner recognises as source.
#
# The repo's own rule is that silence must be EARNED by declaring the gap, never
# granted by omission. So the exemption is declared — in EXEMPTIONS.md, and here.
#
# The reason this is a TEST and not just a paragraph: a declaration can outlive
# its reason. Add one `.mjs` helper and the premise silently becomes false while
# the prose keeps asserting it, which is the same false-green shape the
# exemption is being granted against. This asserts the premise still holds, so
# the exemption expires the moment it stops being true.
#
#   ./tests/test-docs-exemption.sh
#
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
FAILED_NAMES=()

C_DIM=$'\033[38;2;85;85;85m'; C_GOLD=$'\033[38;2;240;192;64m'
C_RED=$'\033[38;2;220;80;80m'; C_OFF=$'\033[0m'

printf '%s\n'   "  ${C_GOLD}▲${C_OFF}   ${C_GOLD}exemption${C_OFF} ${C_DIM}· docs-coverage premise watch${C_OFF}"
printf '%s\n\n' "  ${C_DIM}▀${C_OFF}  ${C_DIM}$ROOT${C_OFF}"

ok()  { PASS=$((PASS+1)); printf '  %s✔%s %s\n' "$C_GOLD" "$C_OFF" "$1"; }
bad() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1")
        printf '  %s✘ %s%s\n' "$C_RED" "$1" "$C_OFF"
        printf '    %sexpected:%s %s\n' "$C_DIM" "$C_OFF" "$2"
        printf '    %sgot:%s      %s\n' "$C_DIM" "$C_OFF" "${3:0:400}"; }

# Exactly the extensions checkDocCoverage globs. Tracked files only: a stray
# build artifact or a dependency vendored into an ignored directory is not this
# repo's source and must not expire the exemption.
scanner_sources() {
  git -C "$ROOT" ls-files \
    '*.ts' '*.js' '*.tsx' '*.jsx' '*.mjs' '*.cjs' 2>/dev/null \
    | grep -v '^\.harness/' || true
}

# ── 1. the premise: nothing in this repo is scannable as source ─────────────
FOUND=$(scanner_sources)
N=$(printf '%s' "$FOUND" | grep -c . || true)
if [ "$N" -eq 0 ]; then
  ok "no ts/js/tsx/jsx/mjs/cjs tracked — check-docs abstention is structural"
else
  bad "docs-coverage exemption has EXPIRED" \
      "zero scannable source files" \
      "$N file(s) now exist, so check-docs can report a real denominator and the exemption in EXEMPTIONS.md is no longer justified — wire check-docs into CI and delete it: $(printf '%s' "$FOUND" | tr '\n' ' ')"
fi

# ── 2. the gap is actually declared, not merely true ────────────────────────
# An undeclared exemption is indistinguishable from nobody having looked.
if [ -f "$ROOT/EXEMPTIONS.md" ]; then
  ok "EXEMPTIONS.md exists"
  if grep -q "check-docs" "$ROOT/EXEMPTIONS.md"; then
    ok "  and names check-docs"
  else
    bad "EXEMPTIONS.md names check-docs" "a check-docs entry" "no mention found"
  fi
  if grep -qE "#17" "$ROOT/EXEMPTIONS.md"; then
    ok "  and links the issue that granted it"
  else
    bad "EXEMPTIONS.md links #17" "a reference to #17" "no issue reference"
  fi
else
  bad "EXEMPTIONS.md exists" "a declared-exemptions file" "missing"
fi

# ── report ───────────────────────────────────────────────────────────────────
printf '\n  %s────────────────────────────────────────%s\n' "$C_DIM" "$C_OFF"
if [ "$FAIL" -eq 0 ]; then
  printf '  %s▲ all %d checks flew clean%s\n\n' "$C_GOLD" "$PASS" "$C_OFF"
  exit 0
fi
printf '  %s✘ %d failed%s, %d passed\n' "$C_RED" "$FAIL" "$C_OFF" "$PASS"
for n in "${FAILED_NAMES[@]}"; do printf '      %s- %s%s\n' "$C_DIM" "$n" "$C_OFF"; done
printf '\n'
exit 1
