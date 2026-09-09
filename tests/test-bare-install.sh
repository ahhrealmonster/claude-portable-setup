#!/bin/bash
# Executable tests for tools/bare-install.sh.
#
# Why these exist: the repo's success test is "a stranger clones it and it works
# on their machine" (STRATEGY.md). Nothing proved that. Every existing suite
# runs against a synthetic root that the *test* populated, so all four suites
# would still pass on a bundle whose install spec had quietly stopped working —
# they exercise the artifacts, never the act of installing them.
#
# The trap this suite exists to spring is SC-3. `tools/check-drift.sh` spends a
# whole exit code on "nothing of the bundle was installed at this root, so
# nothing was compared" — exit 2, an abstention. A bare-install job that shelled
# out to the drift check and accepted any non-1 status would therefore go green
# on an install that copied *zero files*, and it would look exactly like a real
# pass. That is this repo's founding bug in a new costume, so it is pinned here
# before the tool it describes exists.
#
# The contract, in four parts:
#   1. A fresh scratch root installs clean and exits 0.
#   2. The run states its own denominator, and the denominator is never zero.
#      "Its own" is load-bearing: the count must come from bare-install.sh,
#      not be borrowed from whatever the drift check happened to print.
#   3. A drift check that abstains (exit 2) fails the install, exit 1, and the
#      output says the word "abstention" — a red that does not say which red it
#      was sends the reader to the wrong place.
#   4. The success path leaves no scratch state behind.
#
# Isolation: the tool creates its own scratch root under $TMPDIR and prints it.
# The real ~/.claude is never read and never written — and this suite *proves*
# that rather than asserting it. Every invocation runs with $HOME pointed at an
# empty scratch directory, because check-drift.sh falls back to $HOME when
# CHECK_ROOT is unset. Review of PR #16 mutation-tested the one line in the
# tool that sets CHECK_ROOT: with it deleted, this suite still passed 23/23 on
# the author's laptop, because the drift check quietly verified the author's
# real, in-sync install instead of the scratch one. A suite that passes on any
# machine that has already run INSTALL.md is the false-green shape the repo is
# built to catch. With $HOME empty, that same mutation yields exit 2 and five
# red cases.
#
# Case 3 runs against a *copy* of the bundle with a stubbed drift check, so the
# production script needs no test-only seam — BUNDLE derives from `dirname
# "$0"`, so pointing the script at a copy of itself is the whole fixture.
#
#   ./tests/test-bare-install.sh
#
set -u

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
BARE="$BUNDLE/tools/bare-install.sh"
PASS=0
FAIL=0
FAILED_NAMES=()

# Nothing of the bundle lives here, by construction. See the header: a
# verification that quietly falls back to the real $HOME passes on any machine
# that already ran INSTALL.md, and this is what makes that fallback visible.
EMPTY_HOME=$(mktemp -d)

# Every fixture this suite creates is appended here and removed on exit, so an
# interrupted run honours contract part 4 as well as a completed one.
CLEANUP=("$EMPTY_HOME")
trap 'rm -rf "${CLEANUP[@]}"' EXIT

# ── plumage ──────────────────────────────────────────────────────────────────
C_DIM=$'\033[38;2;85;85;85m'; C_GOLD=$'\033[38;2;240;192;64m'
C_RED=$'\033[38;2;220;80;80m'; C_OFF=$'\033[0m'

banner() {
  printf '%s\n' "  ${C_GOLD}⇱${C_OFF}   ${C_GOLD}bare-install${C_OFF} ${C_DIM}· the stranger's first flight${C_OFF}"
  printf '%s\n' " ${C_GOLD}⇱█⇱${C_OFF}  ${C_DIM}$BARE${C_OFF}"
  printf '%s\n\n' "  ${C_DIM}▀${C_OFF}"
}

ok()   { PASS=$((PASS+1)); printf '  %s✔%s %s\n' "$C_GOLD" "$C_OFF" "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1")
         printf '  %s✘ %s%s\n' "$C_RED" "$1" "$C_OFF"
         printf '    %sexpected:%s %s\n' "$C_DIM" "$C_OFF" "$2"
         printf '    %sgot:%s      %s\n' "$C_DIM" "$C_OFF" "${3:0:400}"; }

assert_has() { case "$2" in *"$1"*) ok "$3";; *) bad "$3" "output contains '$1'" "$2";; esac; }
assert_not() { case "$2" in *"$1"*) bad "$3" "output does NOT contain '$1'" "$2";; *) ok "$3";; esac; }
assert_rc()  { [ "$2" = "$1" ] && ok "$3" || bad "$3" "exit $1" "exit $2"; }

# Exit code is part of the contract: 0 installed and verified, 1 anything else.
# One invocation yields both the output and the status: `$?` after a command
# substitution is the subshell's exit code. The earlier run_bare/rc_of pair ran
# the tool twice and paired run 1's output with run 2's exit code — harmless for
# a read-only tool, not for one that creates and deletes directories.
run_bare() { HOME="$EMPTY_HOME" bash "$@" 2>&1; }

# The tool prints the scratch root it used, so case 4 can assert its removal
# without the suite having to dictate the path — a script that deleted a
# caller-supplied directory would be a worse tool for a slightly easier test.
# Takes the rest of the line, so a $TMPDIR containing a space still parses.
root_from() { printf '%s' "$1" | sed -n 's/.*scratch root: //p' | head -1; }

tally() {
  printf '\n'
  if [ "$FAIL" -eq 0 ]; then
    printf '  %s⇱ all %d checks cleared the nest%s\n\n' "$C_GOLD" "$PASS" "$C_OFF"
    exit 0
  fi
  printf '  %s✘ %d of %d failed:%s\n' "$C_RED" "$FAIL" "$((PASS+FAIL))" "$C_OFF"
  for n in "${FAILED_NAMES[@]}"; do printf '    %s- %s%s\n' "$C_DIM" "$n" "$C_OFF"; done
  printf '\n'
  exit 1
}

banner

# ── 0. the tool exists at all ────────────────────────────────────────────────
# Stated as its own case so a missing tool names the file instead of reporting
# four cascading exit-127s that describe nothing.
if [ ! -f "$BARE" ]; then
  bad "tools/bare-install.sh exists and is executable" \
      "a file at $BARE" \
      "absent"
  tally
fi
[ -x "$BARE" ] && ok "tools/bare-install.sh exists and is executable" \
                || bad "tools/bare-install.sh exists and is executable" \
                       "the exec bit set" "present but not executable"

# ── 1. a bare root installs clean ────────────────────────────────────────────
# The whole point: no overlay, no prior ~/.claude, nothing of the author's.
# STRATEGY.md's core layer contract says the core must be fully functional with
# every overlay absent, and this is the case that makes that falsifiable.
OUT=$(run_bare "$BARE"); RC=$?
assert_rc 0 "$RC" "bare scratch root → exit 0"
assert_not "abstention" "$OUT" "  and does not quietly report an abstention as success"

# ── 2. the run names its OWN denominator ─────────────────────────────────────
# The failure mode is test-drift.sh's case 2: a run that verified nothing and
# exited 0 is indistinguishable from one that verified everything, unless the
# count is on screen. But the count must be bare-install.sh's own — the number
# of files it placed — not check-drift's "N check(s)" re-printed. The first
# version of this case asserted on "check(s)", which is exactly the borrowed
# disclosure case 5 refuses to assert on. So the pass path is checked here, and
# the count is pinned again in case 3 where the stub checker prints nothing and
# nothing can be borrowed.
assert_has "installed " "$OUT" "install run → states how many files it placed"
assert_not "installed 0 " "$OUT" "  and the count is never zero"

# A minimal stand-in bundle: `home/` plus the two scripts, which is everything
# bare-install.sh and check-drift.sh read. Cases then perturb exactly one
# artifact inside the copy, so every finding traces to one edit — and because
# BUNDLE derives from `dirname "$0"`, pointing the script at the copy is the
# entire fixture, with no test-only seam in the production code.
#
# Deliberately not `cp -R "$BUNDLE/."`: that drags .git along, and six cases
# each cloning the repo turns a fast suite into one nobody runs.
make_fake_bundle() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/tools"
  cp -R "$BUNDLE/home" "$d/home"
  cp "$BUNDLE/tools/check-drift.sh" "$BUNDLE/tools/bare-install.sh" "$d/tools/"
  chmod +x "$d/tools"/*.sh
  CLEANUP+=("$d")
  printf '%s' "$d"
}

# ── 3. SC-3: an abstaining drift check is a FAILURE, not a pass ──────────────
# The load-bearing case. A stubbed check-drift.sh that prints nothing and exits
# 2 stands in for the real failure this guards: an install that placed no files,
# leaving the drift check with nothing to compare. Accepting that as green would
# certify a bundle that installs nothing at all.
FAKE=$(make_fake_bundle)
printf '#!/bin/bash\nexit 2\n' > "$FAKE/tools/check-drift.sh"
chmod +x "$FAKE/tools/check-drift.sh"
OUT3=$(run_bare "$FAKE/tools/bare-install.sh"); RC3=$?
assert_rc 1 "$RC3" "drift check exits 2 → install fails"
assert_has "abstention" "$OUT3" "  and the failure says which failure it was"
# The stub printed nothing, so this count can only have come from the tool.
assert_has "installed " "$OUT3" "  and the tool's own file count is still stated"
assert_not "installed 0 " "$OUT3" "  and is not zero — the install itself did happen"

# ── 4. the success path leaves no scratch state behind ───────────────────────
# A tool that installs into $TMPDIR and never cleans up turns a CI matrix into a
# disk-usage bug, and turns a local run into a pile of half-installed roots that
# the next run might read.
SCRATCH=$(root_from "$OUT")
if [ -z "$SCRATCH" ]; then
  bad "success path names the scratch root it used" \
      "a line matching 'scratch root: <path>'" "$OUT"
else
  ok "success path names the scratch root it used"
  [ ! -d "$SCRATCH" ] && ok "  and removes it when the install succeeds" \
                      || bad "  and removes it when the install succeeds" \
                             "$SCRATCH gone" "$SCRATCH still present"
fi

# ── 5. SC-4: the uncovered targets are named on the PASS path ────────────────
# This job installs INSTALL.md §§1-4 and verifies §§1-4. It never touches §5
# (settings.json is a merge target, not a copy target) or §6 (memory seeds
# accumulate), so an unqualified "verified" would claim coverage it does not
# have.
#
# The assertion is on "not verified" specifically, and not on the section names:
# check-drift.sh's own output already contains "not compared: settings.json ...
# memory/ seeds", so asserting those here would pass on the wrong script's
# disclosure. Case 6 is where they are pinned honestly — there, the stubbed
# drift check prints nothing at all, so anything on screen came from
# bare-install.sh itself.
assert_has "not verified" "$OUT" "pass path → discloses what it did NOT verify"

# ── 6. ...and on the FAIL path ───────────────────────────────────────────────
# Verbatim from the reasoning check-drift.sh already carries: printing the
# caveat only on green would imply a red run's findings were exhaustive. A
# reader who sees one finding and no caveat concludes there was one problem.
assert_has "not verified" "$OUT3" "fail path → discloses its uncovered targets too"
assert_has "settings.json" "$OUT3" "  names settings.json, with no drift output to borrow it from"
assert_has "memory/ seeds" "$OUT3" "  and names the memory seeds"

# ── 6b. a caller-supplied root survives the FAIL path ────────────────────────
# Case 11 pins "never delete a given root" on success. The EXIT trap fires on
# failure too, and the moment a caller most wants to inspect a root is when the
# install into it went red. A "clean up on failure so CI doesn't fill up"
# regression would pass case 11 and delete exactly that. Same stub fixture as
# case 3, with a root the caller owns.
GIVEN3="$(mktemp -d)"; CLEANUP+=("$GIVEN3")
: > "$GIVEN3/.caller-sentinel"
OUT6=$(run_bare "$FAKE/tools/bare-install.sh" "$GIVEN3"); RC6=$?
assert_rc 1 "$RC6" "caller-supplied root + abstaining checker → still exit 1"
assert_has "abstention" "$OUT6" "  and it is the abstention that was reported, not a trap error"
[ -f "$GIVEN3/.caller-sentinel" ] \
  && ok "  and the failed install is left in place for inspection" \
  || bad "  and the failed install is left in place for inspection" \
         "$GIVEN3/.caller-sentinel still present" "removed by the cleanup trap"

# ── 7. the resolver prefers check_drift.py when it exists ────────────────────
# M2 ports check-drift.sh to Python. If this script kept hardcoding the .sh
# path, SC-3 would go silently unrun the moment the rename landed — the job
# would still be green, still be called "bare install verified", and be
# checking a file nobody maintained any more. That is the repo's founding
# failure shape, so the handover is pinned before the rename exists.
#
# The stub also echoes CHECK_ROOT, so this case pins the positive half of the
# isolation claim: the resolver forwards the scratch root, not just "something
# ran". Needs python3; without it the case cannot run, and "cannot verify" is
# reported as a finding rather than skipped.
if command -v python3 >/dev/null 2>&1; then
  FAKE7=$(make_fake_bundle)
  printf 'import os\nprint("PYDRIFT-MARKER root=" + os.environ.get("CHECK_ROOT", "UNSET"))\n' \
    > "$FAKE7/tools/check_drift.py"
  OUT7=$(run_bare "$FAKE7/tools/bare-install.sh"); RC7=$?
  assert_rc 0 "$RC7" "both artifacts present → exit 0"
  assert_has "PYDRIFT-MARKER" "$OUT7" "  and check_drift.py is the one that ran"
  assert_not "check(s)" "$OUT7" "  and check-drift.sh did not also run"
  assert_has "root=$(root_from "$OUT7")" "$OUT7" "  and it was pointed at the scratch root"
  assert_not "root=UNSET" "$OUT7" "  not left to fall back to \$HOME"
else
  bad "check_drift.py resolver" "python3 on PATH" \
      "absent — case 7 could not run (cannot verify is a finding)"
fi

# ── 8. ...and falls back to check-drift.sh when only it exists ───────────────
# Today's reality. The fallback must stay working for the whole of M1, or this
# task breaks the branch it is written on.
FAKE8=$(make_fake_bundle)
OUT8=$(run_bare "$FAKE8/tools/bare-install.sh"); RC8=$?
assert_rc 0 "$RC8" "only check-drift.sh present → exit 0"
assert_not "PYDRIFT-MARKER" "$OUT8" "  and no Python artifact is invented"

# ── 9. neither artifact exists → hard failure, named ─────────────────────────
# A criterion that could not run is not a criterion that passed. Silently
# skipping the verification would leave a job that installs files, checks
# nothing, and exits 0 — precisely the abstention case 3 exists to reject,
# arriving through a different door. The exit code alone is not enough: before
# the tool grew its explicit else-branch, this went red because bash could not
# execute an absent path (exit 127), which is red for an unintended reason.
# The assertion on the message is what holds the tool to a named failure.
FAKE9=$(make_fake_bundle)
rm -f "$FAKE9/tools/check-drift.sh" "$FAKE9/tools/check_drift.py"
OUT9=$(run_bare "$FAKE9/tools/bare-install.sh"); RC9=$?
assert_rc 1 "$RC9" "no drift artifact at all → install fails"
assert_has "no drift artifact" "$OUT9" "  and says the checker itself was missing"

# ── 10. the disclosure survives that path too ────────────────────────────────
assert_has "not verified" "$OUT9" "missing-checker path → still discloses uncovered targets"

# ── 11. a caller-supplied root is installed into, never deleted ──────────────
# The cleanup trap is armed only for a root this script created (OWNED_TMP).
# Verified by hand during t5 and left unpinned, which is how a safety property
# quietly becomes false. The sentinel is what makes the check honest: the tool
# runs `mkdir -p` on the root, so a bare `[ -d ]` afterwards would also pass on
# a tool that deleted the directory and recreated it. A file the caller put
# there first distinguishes "preserved mine" from "made one".
GIVEN="$(mktemp -d)"; CLEANUP+=("$GIVEN")
: > "$GIVEN/.caller-sentinel"
run_bare "$BARE" "$GIVEN" >/dev/null; RC11=$?
assert_rc 0 "$RC11" "caller-supplied root → exit 0"
[ -f "$GIVEN/.caller-sentinel" ] \
  && ok "  and the caller's own contents survive, not removed" \
  || bad "  and the caller's own contents survive, not removed" \
         "$GIVEN/.caller-sentinel still present" "removed by the cleanup trap"
[ -f "$GIVEN/.claude/hooks/tooling-rot-siren.sh" ] \
  && ok "  and the hooks actually landed in it" \
  || bad "  and the hooks actually landed in it" \
         "a hook at $GIVEN/.claude/hooks/" "absent"

# ── 12. an empty argument is refused, not resolved to / ──────────────────────
# `bare-install.sh ""` used to set ROOT="" and then mkdir -p "/.claude/hooks"
# and cp into "/.claude/CLAUDE.md". On macOS the read-only root made that fail
# harmlessly; on a host where the caller can write /, it is an install into the
# filesystem root under a tool whose header promises to touch nothing of the
# user's. An empty path is not a path.
OUT12=$(run_bare "$BARE" ""); RC12=$?
assert_rc 1 "$RC12" "empty-string root → refused, exit 1"
assert_has "empty" "$OUT12" "  and the refusal says why"
assert_not "scratch root: " "$OUT12" "  and no install was attempted"

tally
