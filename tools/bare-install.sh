#!/bin/bash
# Carry out INSTALL.md §§1–4 into a scratch $HOME, then prove it landed.
#
# Why this exists: this is SC-3. `tools/check-drift.sh` reserves exit **2** for
# "nothing of this bundle is installed at this root, so nothing was compared" —
# an abstention. A CI job that shelled out to the drift check and accepted any
# non-1 status would therefore go green on an install that copied *zero files*,
# and the report would be indistinguishable from a real pass. So this script
# demands exit 0 specifically, and treats 2 as the failure it is.
#
# What it proves, in one sentence: a stranger with no ~/.claude, no overlay, and
# nothing of the author's on their machine can run INSTALL.md and end up with a
# working core (STRATEGY.md, "Who it's for"). Every other suite in this repo
# exercises the artifacts; this one exercises the act of installing them.
#
# Read-only with respect to the real $HOME. With no argument it installs into a
# fresh `mktemp -d` and removes it afterwards; given a path, it installs there
# and leaves it alone, because a script that deletes a directory a caller handed
# it is a worse tool than one that only cleans up after itself.
#
#   ./tools/bare-install.sh            # scratch root, cleaned up
#   ./tools/bare-install.sh /tmp/probe # your root, left in place
#
set -u

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
STATUS=0

# OWNED_TMP is the whole reason the cleanup trap is safe: it fires only for a
# root this script created. A caller-supplied path is never removed.
#
# An empty argument is refused rather than resolved: ROOT="" would turn the
# mkdir and cp below into "/.claude/hooks" and "/.claude/CLAUDE.md" — an
# install into the filesystem root, from a tool whose header promises to touch
# nothing of the user's. macOS's read-only / only made that fail by luck.
if [ "$#" -ge 1 ]; then
  if [ -z "$1" ]; then
    printf '✘ refusing an empty root path: "" would resolve to /, not to a scratch home\n' >&2
    exit 1
  fi
  ROOT="$1"
  OWNED_TMP=0
else
  ROOT="$(mktemp -d)"
  OWNED_TMP=1
fi

# Inlined rather than written as a cleanup() function: shellcheck cannot see
# that a trap invokes one, so the function form raises SC2329 and this repo
# requires tools to be clean at shellcheck's *default* severity. Single quotes
# are deliberate — the body is evaluated when the trap fires, not now.
trap '[ "$OWNED_TMP" -eq 1 ] && rm -rf "$ROOT"' EXIT

printf 'scratch root: %s\n' "$ROOT"

# ── the install, mirroring INSTALL.md §§1–4 ──────────────────────────────────
# §1's "never overwrite without asking" cannot trigger here: a scratch $HOME is
# empty by construction, which is exactly the condition this job is testing.
mkdir -p "$ROOT/.config/ai-rules" "$ROOT/.claude/hooks" "$ROOT/.claude/skills"

cp "$BUNDLE/home/CLAUDE.md"          "$ROOT/.claude/CLAUDE.md"          # §1
cp "$BUNDLE/home/ai-rules/global.md" "$ROOT/.config/ai-rules/global.md" # §1
cp -R "$BUNDLE/home/skills/visual-decisions" "$ROOT/.claude/skills/"    # §2

# Glob, not a hardcoded list: check-drift compares the hooks directory in BOTH
# directions, so a file added to home/hooks/ and missed here surfaces as
# "missing" rather than passing quietly. The glob keeps this script from
# becoming a second file list that can go stale (§3, §4).
cp "$BUNDLE"/home/hooks/*            "$ROOT/.claude/hooks/"

# A deployed hook without +x never runs, and Claude Code reports nothing when a
# hook fails to execute — so the session silently loses that hook's coverage.
# Scoped to *.sh because rot-watch.example.json ships 0644 on purpose.
chmod +x "$ROOT"/.claude/hooks/*.sh

# The tool's own denominator. check-drift prints "N check(s)" of its own, but a
# count borrowed from the verifier says nothing about the install: with the
# checker stubbed out (or silent) the run would state no number at all. This
# is what the tool placed, counted after the fact rather than tallied from the
# cp lines above, so a copy that silently failed is not counted as done.
INSTALLED=$(find "$ROOT" -type f | wc -l | tr -d ' ')
printf 'installed %s file(s) into %s\n' "$INSTALLED" "$ROOT"

# Deliberately NOT installed: settings.json (§5) and the memory/ seeds (§6).
# The drift check does not compare either — the template ships an empty
# allowlist while a live file grows entries, and seeds accumulate — so
# installing them here would claim coverage this verification does not have.

# SC-4. This job installs INSTALL.md §§1-4 and verifies §§1-4. It never touches
# §5 (settings.json is a merge target, not a copy target) or §6 (the memory
# seeds accumulate), so an unqualified "verified" would claim coverage it does
# not have. Printed on every non-early-exit path, including the failures:
# disclosing only on green would imply a red run's findings were exhaustive.
print_uncovered() {
  printf '  not verified: settings.json (INSTALL.md §5), memory/ seeds (§6)\n'
  printf '  — this job proves 4 of the 6 things INSTALL.md deploys\n'
}

# ── the verification ─────────────────────────────────────────────────────────
# SC-3 must survive M2's bash-to-Python rename. A job hardcoding the old
# filename would find nothing afterwards and — depending on how it was written —
# either fail confusingly or skip the criterion silently, which is the worse of
# the two because the run stays green. Prefer the Python artifact once it
# exists; fail hard, and by name, when neither does.
if   [ -f "$BUNDLE/tools/check_drift.py" ]; then DRIFT=(python3 "$BUNDLE/tools/check_drift.py")
elif [ -f "$BUNDLE/tools/check-drift.sh" ]; then DRIFT=(bash    "$BUNDLE/tools/check-drift.sh")
else
  printf '✘ no drift artifact — neither tools/check_drift.py nor tools/check-drift.sh\n'
  printf '  exists, so SC-3 did not run. That is an abstention, not a pass.\n'
  print_uncovered
  exit 1
fi

OUT=$(CHECK_ROOT="$ROOT" "${DRIFT[@]}" 2>&1)
rc=$?
printf '%s\n' "$OUT"

case "$rc" in
  0) printf '⌂ bare install verified — drift check exited 0\n' ;;
  2) printf '✘ exit 2: nothing of the bundle was found under %s,\n' "$ROOT"
     printf '  so nothing was compared. That is an abstention, not a pass —\n'
     printf '  SC-3 requires exit 0, and an exit of 2 proves nothing at all.\n'
     STATUS=1 ;;
  *) printf '✘ drift check exited %s\n' "$rc"
     STATUS=1 ;;
esac

print_uncovered
exit "$STATUS"
