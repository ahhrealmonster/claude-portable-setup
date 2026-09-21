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

# ── fixture: an installed plugin whose manifest pins an npm package ─────────
# Mirrors the real shape: installed_plugins.json carries the installPath, and
# the manifest at that path embeds the pin inside an mcpServers args array.
# The pin is NOT a top-level field anywhere — it is buried in a command line,
# which is exactly why nothing was watching it.
plugin_with_pin() {
  local id="$1" pin="$2" dir="$HOME/.claude/plugins/cache/mkt/plug/0.1.0"
  mkdir -p "$dir/.claude-plugin"
  python3 - "$HOME/.claude/plugins/installed_plugins.json" "$id" "$dir" <<'EOF'
import json, sys
p, pid, d = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = {"version": 2, "plugins": {pid: [{"scope": "user", "version": "0.1.0",
                                        "installPath": d}]}}
json.dump(cfg, open(p, "w"))
EOF
  python3 - "$dir/.claude-plugin/plugin.json" "$pin" <<'EOF'
import json, sys
json.dump({"name": "plug", "version": "0.1.0",
           "mcpServers": {"plug": {"command": "npx",
                                   "args": ["-y", "-p", sys.argv[2], "plug-mcp"]}}},
          open(sys.argv[1], "w"))
EOF
  printf '{"enabledPlugins":{"%s":true}}' "$id" > "$HOME/.claude/settings.json"
}

# ── 20. a manifest pin behind npm latest is rot the other checks cannot see ──
# The case this was built for: a plugin hardcodes `pkg@12.7.0` inside an mcpServers
# args array while the machine's own CLI floats to latest. Checks 1-4 all pass —
# plugin installed, enabled, checkout fresh, CLI current — because not one of them
# reads the manifest. The skew is invisible until something calls the stale surface.
setup
plugin_with_pin "plug@mkt" "mypkg@6.4.0"
config '{"watch":[{"plugin":"plug@mkt","pin_npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "pin" "$OUT" "manifest pin behind latest → finding"
assert_has "6.4.0" "$OUT" "  finding names the pinned version"
assert_has "6.5.0" "$OUT" "  finding names the published version"
teardown

# ── 21. a pin that is current must be silent ────────────────────────────────
# Over-reporting here would fire on every session for a correctly-pinned plugin,
# and an unconditional warning is one nobody reads.
setup
plugin_with_pin "plug@mkt" "mypkg@6.5.0"
config '{"watch":[{"plugin":"plug@mkt","pin_npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
[ -z "$OUT" ] && ok "pin == npm latest → silent" \
              || bad "pin == npm latest → silent" "empty output" "$OUT"
teardown

# ── 22. a pin AHEAD of the cache is not rot (same direction rule as check 4) ─
# Upgrading the plugin before the TTL expires must not be read as rot and must
# never produce a "downgrade to the older version" remediation.
setup
plugin_with_pin "plug@mkt" "mypkg@6.6.0"
config '{"watch":[{"plugin":"plug@mkt","pin_npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_not "pin" "$OUT" "pin ahead of cache → no rot finding (no downgrade advice)"
teardown

# ── 23. pin_npm declared but the package is nowhere in the manifest ─────────
# Declared coverage that finds nothing is the false-green shape this whole hook
# exists to catch: it must report, never quietly succeed at checking nothing.
setup
plugin_with_pin "plug@mkt" "otherpkg@1.0.0"
config '{"watch":[{"plugin":"plug@mkt","pin_npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "no pin for 'mypkg'" "$OUT" "pin_npm matching nothing → reports, never silent"
teardown

# ── 24. pin_npm on a plugin whose manifest cannot be read ───────────────────
# Cannot-verify is a finding, not a skip.
setup
printf '{"version":2,"plugins":{"plug@mkt":[{"scope":"user","version":"0.1.0","installPath":"/nonexistent"}]}}' \
  > "$HOME/.claude/plugins/installed_plugins.json"
printf '{"enabledPlugins":{"plug@mkt":true}}' > "$HOME/.claude/settings.json"
config '{"watch":[{"plugin":"plug@mkt","pin_npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "cannot verify" "$OUT" "unreadable manifest → cannot-verify finding"
teardown

# ── 25. the pin check needs npm data, and says so when it has none ──────────
# Without a cached registry answer there is nothing to compare the pin against.
# It must report that and dispatch a refresh, exactly like check 4.
setup
plugin_with_pin "plug@mkt" "mypkg@6.4.0"
config '{"watch":[{"plugin":"plug@mkt","pin_npm":"mypkg"}]}'
OUT=$(run_siren)
assert_has "cannot verify" "$OUT" "pin check with no cache → cannot-verify, not silence"
teardown

# ── 26. the pin check counts in the denominator ─────────────────────────────
# It is a real check that really ran, so unlike the coverage COMPLAINT in check 5
# it must increment CHECKS_RUN. Entry has plugin + pin_npm = 2 checks.
setup
plugin_with_pin "plug@mkt" "mypkg@6.4.0"
config '{"watch":[{"plugin":"plug@mkt","pin_npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "across 2 check(s)" "$OUT" "pin check increments CHECKS_RUN"
teardown

# ── 27. a fresh cache must not touch the network on the pin path either ─────
# Same contract as case 6. A new check that shells out to npm would reintroduce
# SessionStart latency through the back door.
setup
plugin_with_pin "plug@mkt" "mypkg@6.4.0"
config '{"watch":[{"plugin":"plug@mkt","pin_npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
run_siren >/dev/null
npm_called && bad "pin path → zero network calls" "npm never invoked" "$(cat "$TMP/npm-calls")" \
           || ok "pin path → zero network calls (hot path stays local)"
teardown

# ── 28. pin_npm without a plugin key cannot locate a manifest ───────────────
# The manifest is found via the plugin's installPath, so pin_npm alone is a
# misconfiguration. Silently skipping it would be declared-but-absent coverage.
setup
config '{"watch":[{"cli":"mycli","npm":"mypkg","pin_npm":"mypkg"}]}'
cache "{\"mypkg\":{\"latest\":\"6.4.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "needs a 'plugin'" "$OUT" "pin_npm without plugin → misconfiguration finding"
teardown

# ── fixture: files carrying a pin, outside any plugin ───────────────────────
# The workflow-file case from #22: the pin lives in a repo file the plugin
# machinery knows nothing about, so nothing derived from installPath can see it.
pin_file() {
  local rel="$1"
  local pin="$2"
  local p="$HOME/$rel"
  mkdir -p "$(dirname "$p")"
  printf 'jobs:\n  x:\n    steps:\n      - run: npm install -g %s\n' "$pin" > "$p"
}

# ── 29. a stale pin in a watched file is a finding ──────────────────────────
# Issue #22 exactly: CI installs 6.4.0 while everything else is on 6.5.0, and
# check 5 cannot see it because the pin is not in a plugin manifest.
setup
pin_file "repo/.github/workflows/ci.yml" "mypkg@6.4.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "6.4.0" "$OUT" "stale pin in a watched file → finding names the pin"
assert_has "6.5.0" "$OUT" "  finding names the published version"
assert_has "ci.yml" "$OUT" "  finding names the FILE, so it is actionable"
teardown

# ── 30. a current pin in a watched file is silent ───────────────────────────
setup
pin_file "repo/.github/workflows/ci.yml" "mypkg@6.5.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
[ -z "$OUT" ] && ok "file pin == npm latest → silent" \
              || bad "file pin == npm latest → silent" "empty output" "$OUT"
teardown

# ── 31. THE ZERO DENOMINATOR: a glob matching no files ──────────────────────
# The whole thesis of this hook. A glob that matches nothing checks nothing and
# would otherwise report exactly like a glob that matched a clean file. Renaming
# a workflow directory must not silently retire the check.
setup
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "matched no files" "$OUT" "glob matching nothing → finding, not a pass"
teardown

# ── 32. files matched, but none mentions the package ───────────────────────
# Declared coverage that found nothing. Either CI dropped the pin (good, remove
# the key) or the package name is wrong (bad, the check has been inert).
setup
pin_file "repo/.github/workflows/ci.yml" "otherpkg@1.0.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "no pin for 'mypkg'" "$OUT" "files matched but package absent → reports"
teardown

# ── 33. two files disagreeing must both be named ───────────────────────────
# #22 had the pin twice. Reporting only the first would leave a stale site behind
# after a fix that looked complete.
setup
pin_file "repo/.github/workflows/a.yml" "mypkg@6.3.0"
pin_file "repo/.github/workflows/b.yml" "mypkg@6.4.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "6.3.0" "$OUT" "two disagreeing files → names the first version"
assert_has "6.4.0" "$OUT" "  and the second"
teardown

# ── 34. the same pin repeated in one file reports once ─────────────────────
# #22's real shape: one file, two identical `npm install -g pkg@X` lines. Two
# findings for one fix is noise, and noise is what stops a siren being read.
setup
mkdir -p "$HOME/repo/.github/workflows"
printf 'a: npm install -g mypkg@6.4.0\nb: npm install -g mypkg@6.4.0\n' \
  > "$HOME/repo/.github/workflows/ci.yml"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
# Count inside systemMessage only: the hook repeats the same text in
# additionalContext, so counting across the raw JSON doubles every match.
N=$(printf '%s' "$OUT" | python3 -c "
import json,sys
print(json.load(sys.stdin)['systemMessage'].count('6.4.0'))")
[ "$N" = "1" ] && ok "same version twice in one file → one finding" \
               || bad "same version twice in one file → one finding" "1 mention of 6.4.0" "$N mentions"
teardown

# ── 35. a pin AHEAD of the cache is not rot (direction rule holds here too) ─
setup
pin_file "repo/.github/workflows/ci.yml" "mypkg@6.6.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_not "6.6.0" "$OUT" "file pin ahead of cache → no rot finding, no downgrade advice"
teardown

# ── 36. pin_files without pin_npm names no package to look for ─────────────
setup
pin_file "repo/.github/workflows/ci.yml" "mypkg@6.4.0"
config '{"watch":[{"pin_files":["~/repo/.github/workflows/*.yml"]}]}'
OUT=$(run_siren)
assert_has "needs a 'pin_npm'" "$OUT" "pin_files without pin_npm → misconfiguration finding"
teardown

# ── 37. pin_files works with NO plugin key ─────────────────────────────────
# A repo's CI pins are not a plugin's business. Requiring `plugin` here would
# force a bogus key just to reach the check.
setup
pin_file "repo/.github/workflows/ci.yml" "mypkg@6.4.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_not "needs a 'plugin'" "$OUT" "pin_files alone → no spurious plugin-key complaint"
teardown

# ── 38. manifest and files are watched together, reported separately ───────
# One entry can carry both. They are different artifacts needing different
# fixes, so collapsing them into one finding would hide a site.
setup
plugin_with_pin "plug@mkt" "mypkg@6.4.0"
pin_file "repo/.github/workflows/ci.yml" "mypkg@6.3.0"
config '{"watch":[{"plugin":"plug@mkt","pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "manifest pins mypkg@6.4.0" "$OUT" "manifest pin still reported alongside files"
assert_has "6.3.0" "$OUT" "  file pin reported too"
teardown

# ── 39. the file check counts in the denominator ───────────────────────────
setup
pin_file "repo/.github/workflows/ci.yml" "mypkg@6.4.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
# One check ran: the file scan. There is no plugin here, so no manifest scan —
# counting a check that could not run is the denominator padding this hook forbids.
assert_has "across 1 check(s)" "$OUT" "pin_files increments CHECKS_RUN (by exactly one)"
teardown

# ── 40. a fresh cache must not touch the network on the file path either ───
setup
pin_file "repo/.github/workflows/ci.yml" "mypkg@6.4.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
run_siren >/dev/null
npm_called && bad "file pin path → zero network calls" "npm never invoked" "$(cat "$TMP/npm-calls")" \
           || ok "file pin path → zero network calls (hot path stays local)"
teardown

# ── 41. a pin-only entry still labels its finding ──────────────────────────
# No plugin, cli, marketplace or npm key means every label candidate is empty,
# and the finding renders as a bare "- :" naming nothing at all.
setup
pin_file "repo/.github/workflows/ci.yml" "mypkg@6.4.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_not "  - :" "$OUT" "pin-only entry → finding is labelled, not a bare dash"
assert_has "mypkg:" "$OUT" "  falls back to the package name"
teardown

# ── 42. a scoped package name must not be mangled ──────────────────────────
# The real package is @harness-engineering/cli — a leading @ and a slash. A
# regex built by naive concatenation, or a glob-style match, breaks on both.
setup
mkdir -p "$HOME/repo/.github/workflows"
printf 'run: npm install -g @scope/tool@6.4.0\n' > "$HOME/repo/.github/workflows/ci.yml"
config '{"watch":[{"pin_npm":"@scope/tool","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"@scope/tool\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "@scope/tool@6.4.0" "$OUT" "scoped package name survives the scan"
teardown

# ── fixture: a real git repo whose checked-out branch and origin/main differ ─
# No network: origin/main is faked with update-ref, which is exactly what the
# check reads. Identity is passed per-command so the suite never depends on the
# machine's git config.
git_repo() {
  local dir="$HOME/$1"; local wt_pin="$2"; local ref_pin="$3"
  local G=(git -C "$dir" -c user.email=t@t -c user.name=t -c commit.gpgsign=false)
  mkdir -p "$dir/.github/workflows"
  git init -q -b main "$dir"
  printf 'run: npm install -g %s\n' "$ref_pin" > "$dir/.github/workflows/ci.yml"
  "${G[@]}" add -A; "${G[@]}" commit -qm base
  # Pretend this commit is what origin/main points at.
  "${G[@]}" update-ref refs/remotes/origin/main "$("${G[@]}" rev-parse HEAD)"
  if [ "$wt_pin" != "$ref_pin" ]; then
    "${G[@]}" checkout -qb feat/stale
    printf 'run: npm install -g %s\n' "$wt_pin" > "$dir/.github/workflows/ci.yml"
    "${G[@]}" add -A; "${G[@]}" commit -qm stale
  fi
}

# ── 43. a stale checkout must not read as a stale REPO ─────────────────────
# The #25 case. After the fix landed on main the siren kept reporting the old
# pin, because the working dir sat on a branch that predated it. The finding
# named a file and nothing else, so it was indistinguishable from "main is
# broken" — and it would fire for anyone sitting on a feature branch, which is
# most of the time. A siren that cries on a normal working state stops being read.
setup
git_repo "repo" "mypkg@6.4.0" "mypkg@6.5.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "checkout is behind" "$OUT" "stale checkout, fixed ref → framed as a checkout artifact"
assert_has "feat/stale" "$OUT" "  names the branch actually responsible"
assert_not "update the pin" "$OUT" "  does NOT prescribe editing an already-fixed pin"
teardown

# ── 43b. a detached checkout must not be reported as branch 'HEAD' ─────────
# `rev-parse --abbrev-ref HEAD` returns the literal "HEAD" when detached instead
# of failing, so a naive fallback names a branch that does not exist.
setup
git_repo "repo" "mypkg@6.4.0" "mypkg@6.5.0"
git -C "$HOME/repo" checkout -q --detach 2>/dev/null
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_not "branch 'HEAD'" "$OUT" "detached checkout → not named as branch 'HEAD'"
teardown

# ── 44. genuinely stale on BOTH sides is still real rot ────────────────────
# The reframing above must not swallow the case the check exists for.
setup
git_repo "repo" "mypkg@6.4.0" "mypkg@6.4.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "update the pin" "$OUT" "stale on branch AND ref → real rot, still prescribed"
assert_not "checkout is behind" "$OUT" "  not excused as a checkout artifact"
teardown

# ── 45. a file outside any git repo reports exactly as before ──────────────
# No repo means no ref to compare against; the check must degrade to its old
# behaviour rather than going quiet.
setup
pin_file "loose/ci.yml" "mypkg@6.4.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/loose/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "update the pin" "$OUT" "non-git file → unchanged finding"
assert_not "checkout is behind" "$OUT" "  no bogus branch framing"
teardown

# ── 46. an unresolvable comparison ref must not silence the finding ────────
# Cannot-verify is a finding, not a skip: if the ref cannot be read we still know
# the working tree is stale, and that much must survive.
setup
git_repo "repo" "mypkg@6.4.0" "mypkg@6.5.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"],"pin_ref":"origin/nonexistent"}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "6.4.0" "$OUT" "unresolvable ref → still reports the stale worktree pin"
assert_has "could not be read" "$OUT" "  and says the ref could not be read"
teardown

# ── 47. pin_ref overrides the default comparison ref ───────────────────────
setup
git_repo "repo" "mypkg@6.4.0" "mypkg@6.5.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"],"pin_ref":"main"}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "checkout is behind" "$OUT" "explicit pin_ref is honoured"
assert_has "main" "$OUT" "  names the ref it compared against"
teardown

# ── 48. a clean worktree costs no git calls ────────────────────────────────
# The ref comparison runs only when there is already a stale hit to explain.
# Doing it eagerly would put git work on every SessionStart for every watched
# file, which is the latency this hook refuses to add.
setup
git_repo "repo" "mypkg@6.5.0" "mypkg@6.5.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
printf '#!/bin/bash\necho "$@" >> "%s/git-calls"\nexec /usr/bin/git "$@"\n' "$TMP" > "$TMP/bin/git"
chmod +x "$TMP/bin/git"
OUT=$(run_siren)
[ -z "$OUT" ] && ok "clean pin → silent" || bad "clean pin → silent" "empty" "$OUT"
[ -f "$TMP/git-calls" ] && bad "clean pin → no git calls" "git never invoked" "$(cat "$TMP/git-calls")" \
                        || ok "clean pin → zero git calls (ref check is lazy)"
teardown

# ── 49. git missing entirely must degrade, not crash or go silent ──────────
setup
pin_file "repo/.github/workflows/ci.yml" "mypkg@6.4.0"
config '{"watch":[{"pin_npm":"mypkg","pin_files":["~/repo/.github/workflows/*.yml"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
printf '#!/bin/bash\nexit 127\n' > "$TMP/bin/git"; chmod +x "$TMP/bin/git"
OUT=$(run_siren)
assert_has "6.4.0" "$OUT" "git unusable → the pin finding still reports"
teardown

# ── fixtures for #15 ────────────────────────────────────────────────────────
# A marketplace checkout whose git mtimes say "fresh" while the record Claude
# Code actually keeps says otherwise, and an installed-plugin registry that can
# hold several scoped versions at once.
marketplace() {
  local name="$1" days_ago="$2"
  local d="$HOME/.claude/plugins/marketplaces/$name"
  mkdir -p "$d/.git" "$d/.claude-plugin"
  touch "$d/.git/FETCH_HEAD" "$d/.git/HEAD"          # deliberately fresh mtimes
  printf '{"name":"p","version":"%s"}' "${3:-9.9.9}" > "$d/.claude-plugin/plugin.json"
  python3 - "$HOME/.claude/plugins/known_marketplaces.json" "$name" "$days_ago" <<'EOF'
import datetime as d, json, os, sys
p, name, days = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(p)) if os.path.exists(p) else {}
if days != "absent":
    when = d.datetime.now(d.timezone.utc) - d.timedelta(days=float(days))
    cfg[name] = {"lastUpdated": when.strftime("%Y-%m-%dT%H:%M:%S.000Z")}
json.dump(cfg, open(p, "w"))
EOF
}

# installed_plugins.json entries: "scope:version" pairs, so one call can build
# the several-scopes-at-once shape that actually occurred.
installed() {
  local id="$1"; shift
  python3 - "$HOME/.claude/plugins/installed_plugins.json" "$id" "$@" <<'EOF'
import json, os, sys
p, pid, pairs = sys.argv[1], sys.argv[2], sys.argv[3:]
cfg = json.load(open(p)) if os.path.exists(p) else {}
cfg.setdefault("version", 2).__class__
cfg = {"version": 2, "plugins": cfg.get("plugins", {})}
cfg["plugins"][pid] = [
    {"scope": s, "version": v,
     "installPath": "/tmp/%s/%s" % (pid.split("@")[0], v)}
    for s, v in (x.split(":") for x in pairs)
]
json.dump(cfg, open(p, "w"))
EOF
  printf '{"enabledPlugins":{"%s":true}}' "$id" > "$HOME/.claude/settings.json"
}

# ── 50. staleness must come from the record, not from a git mtime ───────────
# The #15 case. `find .git/FETCH_HEAD -mtime` says fresh whenever ANYONE fetched
# — including a human running `git pull` by hand — and when FETCH_HEAD is absent
# the old code fell back to `.git/HEAD`, whose mtime moves on checkout and commit
# and never on fetch. So a checkout that was never refreshed looked fresh
# forever. known_marketplaces.json is what Claude Code actually stamps.
setup
marketplace "mkt" 30
config '{"watch":[{"marketplace":"mkt","stale_days":14}]}'
OUT=$(run_siren)
assert_has "last updated 30d ago" "$OUT" "30d since lastUpdated → stale, despite fresh git mtimes"
teardown

# ── 51. a recently-recorded update is silent ───────────────────────────────
setup
marketplace "mkt" 3
config '{"watch":[{"marketplace":"mkt","stale_days":14}]}'
OUT=$(run_siren)
[ -z "$OUT" ] && ok "3d since lastUpdated → silent" \
              || bad "3d since lastUpdated → silent" "empty output" "$OUT"
teardown

# ── 52. a marketplace with no record at all cannot be verified ─────────────
# Silence here would mean "never updated" and "updated this morning" look the
# same, which is the abstention-as-pass shape.
setup
marketplace "mkt" absent
config '{"watch":[{"marketplace":"mkt","stale_days":14}]}'
OUT=$(run_siren)
assert_has "cannot verify" "$OUT" "no lastUpdated record → cannot-verify finding"
teardown

# ── 53. skew must name the INSTALLED plugin, not the checkout ──────────────
# Three artifacts, three versions: npm CLI 7.1.0, checkout 7.0.0, installed
# 6.4.0. The old check compared against the checkout and reported a 1-release
# skew while a 7-release skew sat behind it, unnamed — and the installed copy is
# the one Claude Code actually loads.
setup
marketplace "mkt" 1 "7.0.0"
installed "p@mkt" "user:6.4.0"
printf '#!/bin/bash\necho "p v7.1.0"\n' > "$TMP/bin/p"; chmod +x "$TMP/bin/p"
config '{"watch":[{"plugin":"p@mkt","marketplace":"mkt","cli":"p","npm_exempt":true}]}'
OUT=$(run_siren)
assert_has "6.4.0" "$OUT" "skew names the INSTALLED version"
assert_not "7.0.0" "$OUT" "  and not the marketplace checkout's version"
teardown

# ── 54. several scoped installs at once — none silently dropped ────────────
# installed_plugins.json is per-scope and held user + two project entries at
# three different versions simultaneously. Reporting only the first hides the
# rest, and the oldest is the one most likely to matter.
setup
marketplace "mkt" 1 "7.0.0"
installed "p@mkt" "user:7.1.0" "project:6.4.0"
printf '#!/bin/bash\necho "p v7.1.0"\n' > "$TMP/bin/p"; chmod +x "$TMP/bin/p"
config '{"watch":[{"plugin":"p@mkt","marketplace":"mkt","cli":"p","npm_exempt":true}]}'
OUT=$(run_siren)
assert_has "6.4.0" "$OUT" "multiple scoped installs → the divergent one is named"
teardown

# ── 55. one version across every scope, matching the CLI, is silent ────────
setup
marketplace "mkt" 1 "7.0.0"
installed "p@mkt" "user:7.1.0" "project:7.1.0"
printf '#!/bin/bash\necho "p v7.1.0"\n' > "$TMP/bin/p"; chmod +x "$TMP/bin/p"
config '{"watch":[{"plugin":"p@mkt","marketplace":"mkt","cli":"p","npm_exempt":true}]}'
OUT=$(run_siren)
[ -z "$OUT" ] && ok "all scopes agree with the CLI → silent" \
              || bad "all scopes agree with the CLI → silent" "empty output" "$OUT"
teardown

# ── 56. the remediation is `update`, not `install` ─────────────────────────
# `claude plugin install <name>` no-ops on an already-installed plugin
# ("already installed") without upgrading it, so a finding that prescribes it
# sends the reader through a command that cannot fix what was reported.
setup
marketplace "mkt" 30
config '{"watch":[{"marketplace":"mkt","stale_days":14}]}'
OUT=$(run_siren)
assert_has "marketplace update" "$OUT" "stale marketplace → prescribes an update command"
teardown

# ── 57. a CLI that banners to stderr must still be read ────────────────────
# Live case: `canary --version` prints "canary v7.2.0" to STDERR, and the check
# captured stdout only. CLI_VER came back "unknown", which silently SKIPS the
# skew comparison — the check reports nothing and looks identical to agreement.
setup
marketplace "mkt" 1 "7.0.0"
installed "p@mkt" "user:6.4.0"
printf '#!/bin/bash\necho "p v7.1.0" >&2\n' > "$TMP/bin/p"; chmod +x "$TMP/bin/p"
config '{"watch":[{"plugin":"p@mkt","marketplace":"mkt","cli":"p","npm_exempt":true}]}'
OUT=$(run_siren)
assert_has "7.1.0" "$OUT" "version on stderr → still parsed"
assert_has "6.4.0" "$OUT" "  and compared against the installed plugin"
teardown

# ── 58. a CLI on PATH with no readable version is cannot-verify ────────────
# Skipping quietly means "versions agree" and "we never found out" render the
# same. The skew check is the thing being abstained from, so say so.
setup
installed "p@mkt" "user:6.4.0"
printf '#!/bin/bash\necho "no version here"\n' > "$TMP/bin/p"; chmod +x "$TMP/bin/p"
config '{"watch":[{"plugin":"p@mkt","cli":"p","npm_exempt":true}]}'
OUT=$(run_siren)
assert_has "cannot verify" "$OUT" "unparseable CLI version → cannot-verify, not silence"
teardown

# ── 59. several scopes at different versions is itself a finding ───────────
# Live: canary@bop-clocktower installed at user 7.2.0 and project 6.4.0 twice.
# Nothing compared the scopes to each other, so a project sitting a major behind
# was invisible whether or not a CLI version existed.
setup
installed "p@mkt" "user:7.2.0" "project:6.4.0"
config '{"watch":[{"plugin":"p@mkt","npm_exempt":true}]}'
OUT=$(run_siren)
assert_has "7.2.0" "$OUT" "scopes disagree → finding names the newer version"
assert_has "6.4.0" "$OUT" "  and the older one"
teardown

# ── 60. one version across all scopes is not a disagreement ───────────────
setup
installed "p@mkt" "user:7.2.0" "project:7.2.0"
config '{"watch":[{"plugin":"p@mkt","npm_exempt":true}]}'
OUT=$(run_siren)
[ -z "$OUT" ] && ok "all scopes on one version → silent" \
              || bad "all scopes on one version → silent" "empty output" "$OUT"
teardown

# ── fixture: a ratchet baseline stamping the instrument it was measured with ──
# canary #1048. A ratchet ceiling is only comparable to a count produced by the
# SAME analyzer, so the baseline records which version measured it. CI pins the
# analyzer to a floating major, so the pin resolves forward on its own and the
# stamp does not follow — at which point the ratchet correctly abstains and reds
# every open PR at once. Ten occurrences before anything watched for it.
stamp_file() {
  local rel="$1" key="$2" ver="$3"
  local p="$HOME/$rel"
  mkdir -p "$(dirname "$p")"
  printf '{"maxFindings":145,"measuredCount":144,"%s":"%s"}\n' "$key" "$ver" > "$p"
}

# ── 61. a stamp behind the resolved pin is a finding ───────────────────────
# THE #1048 case, caught at the cheap moment: before a PR goes red, not by
# whoever happens to have one open.
setup
stamp_file "repo/.harness/entropy-baseline.json" "harnessCli" "6.4.0"
config '{"watch":[{"pin_npm":"mypkg","stamp_key":"harnessCli","stamp_files":["~/repo/.harness/*-baseline.json"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "6.4.0" "$OUT" "stale ratchet stamp → finding names the stamp"
assert_has "6.5.0" "$OUT" "  and the version the pin now resolves to"
assert_has "entropy-baseline.json" "$OUT" "  and the FILE to restamp"
assert_has "abstain" "$OUT" "  and says what happens next, not just that they differ"
teardown

# ── 62. a stamp matching the resolved pin is silent ────────────────────────
setup
stamp_file "repo/.harness/entropy-baseline.json" "harnessCli" "6.5.0"
config '{"watch":[{"pin_npm":"mypkg","stamp_key":"harnessCli","stamp_files":["~/repo/.harness/*-baseline.json"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
[ -z "$OUT" ] && ok "stamp == resolved pin → silent" \
              || bad "stamp == resolved pin → silent" "empty output" "$OUT"
teardown

# ── 63. EVERY stale stamp is named, not just the first ─────────────────────
# The restamp is mechanical but it has to touch BOTH baselines; #1048 records
# the entropy and perf stamps moving together every time. A finding that named
# one file would send someone to do half the job and call it done.
setup
stamp_file "repo/.harness/entropy-baseline.json" "harnessCli" "6.4.0"
stamp_file "repo/.harness/perf-baseline.json"    "harnessCli" "6.4.0"
config '{"watch":[{"pin_npm":"mypkg","stamp_key":"harnessCli","stamp_files":["~/repo/.harness/*-baseline.json"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "entropy-baseline.json" "$OUT" "two stale stamps → names the entropy baseline"
assert_has "perf-baseline.json" "$OUT" "  AND the perf baseline"
teardown

# ── 64. THE ZERO DENOMINATOR: a stamp glob matching no files ───────────────
# Same thesis as case 31. Move the baselines and the check retires itself.
setup
config '{"watch":[{"pin_npm":"mypkg","stamp_key":"harnessCli","stamp_files":["~/repo/.harness/*-baseline.json"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "matched no files" "$OUT" "stamp glob matching nothing → reports itself"
teardown

# ── 65. a matched file that lacks the key is watching nothing ──────────────
# A renamed field is indistinguishable from an up-to-date stamp if absence
# reads as agreement.
setup
stamp_file "repo/.harness/entropy-baseline.json" "someOtherKey" "6.4.0"
config '{"watch":[{"pin_npm":"mypkg","stamp_key":"harnessCli","stamp_files":["~/repo/.harness/*-baseline.json"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "harnessCli" "$OUT" "key absent from every matched file → names the key"
assert_has "watching nothing" "$OUT" "  and says the check is inert"
teardown

# ── 66. stamp_files without stamp_key scans for nothing ────────────────────
setup
stamp_file "repo/.harness/entropy-baseline.json" "harnessCli" "6.4.0"
config '{"watch":[{"pin_npm":"mypkg","stamp_files":["~/repo/.harness/*-baseline.json"]}]}'
cache "{\"mypkg\":{\"latest\":\"6.5.0\",\"checked\":\"$(hours_ago 1)\"}}"
OUT=$(run_siren)
assert_has "stamp_key" "$OUT" "stamp_files without stamp_key → misconfiguration finding"
teardown

# ── 67. stamp_files without pin_npm names no package to resolve ────────────
setup
stamp_file "repo/.harness/entropy-baseline.json" "harnessCli" "6.4.0"
config '{"watch":[{"stamp_key":"harnessCli","stamp_files":["~/repo/.harness/*-baseline.json"]}]}'
OUT=$(run_siren)
assert_has "pin_npm" "$OUT" "stamp_files without pin_npm → misconfiguration finding"
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
