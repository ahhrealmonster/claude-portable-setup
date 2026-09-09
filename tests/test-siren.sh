#!/bin/bash
# Executable tests for tooling-rot-siren.sh.
#
# Why these exist: two parsing bugs shipped in this hook while the INSTALL.md
# smoke probes said it was fine — a manual probe you run once is not a
# regression test. Every bug that has escaped this hook gets a case here.
#
# Isolation: each case runs against a throwaway $HOME, so the siren reads a
# synthetic ~/.claude and never touches the real one. That is also why the
# script under test must derive every path from $HOME and never hardcode one.
#
#   ./tests/test-siren.sh
#
set -u

SIREN="$(cd "$(dirname "$0")/.." && pwd)/home/hooks/tooling-rot-siren.sh"
PASS=0
FAIL=0
FAILED_NAMES=()

# ── plumage ──────────────────────────────────────────────────────────────────
# Themed to match canary's own banner (birds of prey network). Cosmetic only.
C_DIM=$'\033[38;2;85;85;85m'; C_GOLD=$'\033[38;2;240;192;64m'
C_RED=$'\033[38;2;220;80;80m'; C_OFF=$'\033[0m'

banner() {
  printf '%s\n' "  ${C_GOLD}▲${C_OFF}   ${C_GOLD}siren${C_OFF} ${C_DIM}· rot-watch regression flock${C_OFF}"
  printf '%s\n' " ${C_GOLD}▲█▲${C_OFF}  ${C_DIM}$SIREN${C_OFF}"
  printf '%s\n\n' "  ${C_DIM}▀${C_OFF}"
}

ok()   { PASS=$((PASS+1)); printf '  %s✔%s %s\n' "$C_GOLD" "$C_OFF" "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1")
         printf '  %s✘ %s%s\n' "$C_RED" "$1" "$C_OFF"
         printf '    %sexpected:%s %s\n' "$C_DIM" "$C_OFF" "$2"
         printf '    %sgot:%s      %s\n' "$C_DIM" "$C_OFF" "${3:0:400}"; }

# ── fixtures ─────────────────────────────────────────────────────────────────
# Builds a synthetic $HOME with a fake CLI on PATH and a fake npm that records
# every invocation, so a test can assert the hot path made NO network call.
setup() {
  TMP=$(mktemp -d)
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/plugins" "$TMP/bin"
  printf '{"enabledPlugins":{}}' > "$HOME/.claude/settings.json"
  printf '{}' > "$HOME/.claude/plugins/installed_plugins.json"

  # Fake watched CLI, pinned at 6.4.0.
  printf '#!/bin/bash\necho "mycli v6.4.0"\n' > "$TMP/bin/mycli"
  # Fake npm: records that it ran, then answers like `npm view <pkg> version`.
  printf '#!/bin/bash\necho "$@" >> "%s/npm-calls"\necho "6.5.0"\n' "$TMP" > "$TMP/bin/npm"
  chmod +x "$TMP/bin/mycli" "$TMP/bin/npm"
  export PATH="$TMP/bin:$PATH"
}

teardown() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; }

config()     { printf '%s' "$1" > "$HOME/.claude/hooks/rot-watch.json"; }
cache()      { printf '%s' "$1" > "$HOME/.claude/hooks/.rot-npm-cache.json"; }
run_siren()  { echo '{}' | bash "$SIREN" 2>&1; }
npm_called() { [ -f "$TMP/npm-calls" ]; }

# Timestamp N hours in the past, ISO-8601 Z. Tests must never depend on the
# wall clock beyond this.
hours_ago() { python3 -c "
import datetime as d
print((d.datetime.now(d.timezone.utc)-d.timedelta(hours=$1)).strftime('%Y-%m-%dT%H:%M:%SZ'))"; }

assert_has() { case "$2" in *"$1"*) ok "$3";; *) bad "$3" "output contains '$1'" "$2";; esac; }
assert_not() { case "$2" in *"$1"*) bad "$3" "output does NOT contain '$1'" "$2";; *) ok "$3";; esac; }

banner

# ── 1. abstention: no config at all ──────────────────────────────────────────
setup
OUT=$(run_siren)
[ -z "$OUT" ] && ok "no config → silent (nothing was asked for)" \
              || bad "no config → silent" "empty output" "$OUT"
teardown

# ── 2. empty watchlist is a finding, not a pass ──────────────────────────────
setup
config '{"watch":[]}'
OUT=$(run_siren)
assert_has "empty watchlist" "$OUT" "empty watchlist → reports itself"
teardown

# ── 3. parsing path: entries omitting different keys must not shift fields ───
# Regression: tab-delimited fields collapsed under IFS, shifting every field
# left whenever a key was omitted.
setup
config '{"watch":[{"plugin":"ghost@nowhere","marketplace":"nowhere","cli":"nope-1"},{"marketplace":"nowhere","cli":"nope-2"},{"cli":"nope-3"}]}'
OUT=$(run_siren)
assert_has "across 6 check(s)" "$OUT" "3 mixed entries → 6 checks (no entries dropped)"
for n in nope-1 nope-2 nope-3; do
  assert_has "CLI '$n' not on PATH" "$OUT" "  reports missing CLI $n"
done
assert_not "CLI '14' not on PATH" "$OUT" "  stale_days never read as a CLI name"
teardown

# ── 4. npm drift: cached latest ahead of local CLI → finding ─────────────────
setup
config '{"watch":[{"cli":"mycli","npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "6.5.0" "$OUT" "npm drift → finding names the published version"
assert_has "6.4.0" "$OUT" "  finding names the locally installed version"
teardown

# ── 5. no drift → silent ─────────────────────────────────────────────────────
setup
config '{"watch":[{"cli":"mycli","npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.4.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
[ -z "$OUT" ] && ok "local == npm latest → silent" \
              || bad "local == npm latest → silent" "empty output" "$OUT"
teardown

# ── 6. THE CONTRACT: fresh cache must not touch the network ─────────────────
# This is the whole reason for the cache. If the hot path ever shells out to
# npm, SessionStart inherits network latency and a timeout can kill the hook
# silently — the exact false-green this siren exists to prevent.
setup
config '{"watch":[{"cli":"mycli","npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.4.0\",\"checked\":\"$(hours_ago 1)\"}}"
run_siren >/dev/null
npm_called && bad "fresh cache → zero network calls" "npm never invoked" "$(cat "$TMP/npm-calls")" \
           || ok "fresh cache → zero network calls (hot path stays local)"
teardown

# ── 7. missing cache entry → cannot-verify is a finding, not silence ────────
setup
config '{"watch":[{"cli":"mycli","npm":"mypkg"}]}'
OUT=$(run_siren)
assert_has "cannot verify" "$OUT" "no cached data → cannot-verify finding"
teardown

# ── 8. stale cache dispatches a DETACHED refresh and never blocks ───────────
setup
config '{"watch":[{"cli":"mycli","npm":"mypkg","npm_ttl_hours":24}]}'
cache "{\"mypkg\":{\"latest\":\"6.4.0\",\"checked\":\"$(hours_ago 72)\"}}"
START=$(python3 -c 'import time;print(time.time())')
run_siren >/dev/null
ELAPSED=$(python3 -c "import time;print(time.time()-$START)")
python3 -c "import sys;sys.exit(0 if $ELAPSED < 2.0 else 1)" \
  && ok "stale cache → returns in ${ELAPSED:0:4}s (did not wait on refresh)" \
  || bad "stale cache → returns fast" "< 2.0s" "${ELAPSED}s"
for _ in 1 2 3 4 5 6 7 8 9 10; do npm_called && break; sleep 0.3; done
npm_called && ok "stale cache → detached refresh actually ran" \
           || bad "stale cache → detached refresh ran" "npm invoked in background" "npm never called"
teardown

# ── 9. stale cache still reports what it has, annotated ─────────────────────
setup
config '{"watch":[{"cli":"mycli","npm":"mypkg","npm_ttl_hours":24}]}'
cache "{\"mypkg\":{\"latest\":\"6.9.0\",\"checked\":\"$(hours_ago 100)\"}}"
OUT=$(run_siren)
assert_has "6.9.0" "$OUT" "stale cache → still reports known drift"
assert_has "stale" "$OUT" "  and flags the data as stale rather than implying fresh"
teardown

# ── 10. malformed cache must not crash the whole siren ──────────────────────
setup
config '{"watch":[{"cli":"nope-x","npm":"mypkg"}]}'
cache 'not json at all'
OUT=$(run_siren)
assert_has "nope-x" "$OUT" "corrupt cache → other checks still run"
teardown

# ── 11. partial coverage: a watched CLI with no npm key is a finding ────────
# The siren's own rot-watch.json shipped with 2 watched CLIs and only 1 `npm`
# key, so drift detection covered half the watchlist and said nothing about the
# other half. Omission read as coverage — the exact false-green this hook exists
# to catch, reproduced inside its own config.
setup
config '{"watch":[{"cli":"mycli"}]}'
OUT=$(run_siren)
assert_has "partial coverage" "$OUT" "cli without npm key → partial-coverage finding"
assert_has "mycli" "$OUT" "  finding names the uncovered CLI"
teardown

# ── 12. the opt-out must be explicit, never inferred from omission ───────────
# Not everything on PATH is published to npm. Declaring that is one key; the
# point is that silence is EARNED by a declaration rather than granted by an
# omission — same rule as "no config = silent, empty watchlist = finding".
setup
config '{"watch":[{"cli":"mycli","npm_exempt":true}]}'
OUT=$(run_siren)
[ -z "$OUT" ] && ok "cli + npm_exempt → silent (coverage gap declared intentional)" \
              || bad "cli + npm_exempt → silent" "empty output" "$OUT"
teardown

# ── 13. a fully covered entry must not draw the warning ─────────────────────
# Guards the other direction: if this fired on covered entries too it would be
# unconditional noise, and an unconditional warning is one nobody reads.
setup
config '{"watch":[{"cli":"mycli","npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.4.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_not "partial coverage" "$OUT" "cli WITH npm key → no partial-coverage warning"
teardown

# ── 14. the warning is not a check — it must not inflate the denominator ────
# CHECKS_RUN counts checks that actually executed. Counting a coverage COMPLAINT
# as a check would pad the very number this siren exists to keep honest.
setup
config '{"watch":[{"cli":"mycli"}]}'
OUT=$(run_siren)
assert_has "across 1 check(s)" "$OUT" "coverage warning does not increment CHECKS_RUN"
teardown

# ── 15. local AHEAD of cache is not rot, and must never suggest a downgrade ──
# The comparison used to be a bare string inequality, so `local != cached` was
# read as "upstream published something newer" REGARDLESS of direction. Upgrade a
# watched CLI and the siren announced a "newer release" naming the OLDER version
# and told you to install it. The window lasts up to the full TTL — i.e. the whole
# day after a user does exactly the right thing. Worse than a missed finding: the
# remediation actively reverts a good upgrade, and it trains the user to ignore
# the siren right when it is loudest.
setup
config '{"watch":[{"cli":"mycli","npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.3.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_not "newer release published" "$OUT" "local ahead of cache → not a rot finding"
assert_not "mypkg@6.3.0" "$OUT" "  never prescribes installing the older version"
teardown

# ── 16. local ahead proves the cache is wrong — refresh regardless of TTL ────
# A fresh TTL normally means "trust the cache, touch nothing". But a local version
# ahead of the cached registry answer is direct evidence the cached answer is out
# of date, which outranks the clock. Without this the wrong value simply sits
# there until the TTL expires.
setup
config '{"watch":[{"cli":"mycli","npm":"mypkg","npm_ttl_hours":24}]}'
cache "{\"mypkg\":{\"latest\":\"6.3.0\",\"checked\":\"$(hours_ago 1)\"}}"
run_siren >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do npm_called && break; sleep 0.3; done
npm_called && ok "local ahead → refresh dispatched despite a fresh TTL" \
           || bad "local ahead → refresh dispatched" "npm invoked in background" "npm never called"
teardown

# ── 17. the ordinary drift finding must still fire (no over-correction) ──────
# Guard against "fixing" case 15 by muting the comparison outright.
setup
config '{"watch":[{"cli":"mycli","npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.9.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "newer release published" "$OUT" "local behind → drift finding still fires"
assert_has "mypkg@6.9.0" "$OUT" "  remediation names the NEWER version"
teardown

# ── 18. a non-semver version falls back to inequality, never to silence ─────
# Some CLIs report a build string or a git describe. Unparseable must degrade to
# the old behaviour (report the difference) rather than being treated as "equal"
# and going quiet — that would convert a parse gap into a false green.
setup
config '{"watch":[{"cli":"mycli","npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"nightly-abc123\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
[ -n "$OUT" ] && ok "unparseable version → still reports, does not go silent" \
              || bad "unparseable version → still reports" "a finding" "(silent)"
teardown

# ── 19. --refresh-npm-cache with no packages is a usage error, not a no-op ───
# `for PKG in "$@"` over an empty list exits 0 having done nothing, so a mistyped
# invocation looked like a successful refresh. In a hook whose whole job is to
# refuse silent success, that exit code is the bug.
setup
OUT=$(bash "$SIREN" --refresh-npm-cache 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok "refresh with no packages → non-zero exit (usage error)" \
                || bad "refresh with no packages → non-zero exit" "non-zero" "exit $RC: $OUT"
teardown

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
