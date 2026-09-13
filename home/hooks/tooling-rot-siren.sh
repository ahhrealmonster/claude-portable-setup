#!/bin/bash
# SessionStart tooling-rot siren.
#
# Yells about degraded local tooling BEFORE any work starts. On findings it
# injects a loud warning into session context AND shows the user a systemMessage.
#
# The hot path is local-only and <1s — it never waits on the network. The npm
# registry check reads a CACHE file written by a detached background refresh,
# so a slow or absent network can delay freshness but can never delay (or, via
# the hook timeout, silently kill) SessionStart. That distinction is the whole
# design: a siren that hangs is a siren that reports nothing, which is
# indistinguishable from a siren that reports all-clear.
#
# Born of an incident where a test toolchain ran silently broken for ~7 weeks
# while every surface reported green.
#
# Denominator honesty: if a watchlist EXISTS but covers nothing (empty or
# unparseable), that is reported — you intended coverage and have none. If no
# watchlist exists at all, this exits silently: you never asked it to watch
# anything, and a siren that fires every session is a siren that stops being
# read. See "check the denominator" in ~/.claude/CLAUDE.md.
#
# Config: ~/.claude/hooks/rot-watch.json   (see rot-watch.example.json)
set -u

CLAUDE_DIR="$HOME/.claude"
CONFIG="$CLAUDE_DIR/hooks/rot-watch.json"
CACHE="$CLAUDE_DIR/hooks/.rot-npm-cache.json"
FINDINGS=()
NEED_REFRESH=()
CHECKS_RUN=0

# ------------------------------------------------------- background refresh --
# Re-entrant mode: the hot path re-invokes this script detached to refresh the
# npm cache, so the network call happens in a process nobody is waiting on.
# Writes are atomic (os.replace) because a session may read the cache at any
# moment — a half-written cache would read as corrupt and fire a false finding.
if [ "${1:-}" = "--refresh-npm-cache" ]; then
  shift
  # `for PKG in "$@"` over an empty list exits 0 having done nothing, so a
  # mistyped invocation used to look like a successful refresh. In a hook whose
  # entire purpose is refusing silent success, that is the bug.
  if [ "$#" -eq 0 ]; then
    printf 'usage: %s --refresh-npm-cache <npm-package> [<npm-package>...]\n' \
      "$(basename "$0")" >&2
    exit 2
  fi
  for PKG in "$@"; do
    VER=$(npm view "$PKG" version 2>/dev/null </dev/null | tr -d '[:space:]')
    [ -n "$VER" ] || continue
    python3 - "$CACHE" "$PKG" "$VER" <<'EOF'
import json, sys, os, datetime as d
path, pkg, ver = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    cache = json.load(open(path))
    if not isinstance(cache, dict):
        cache = {}
except Exception:
    cache = {}          # absent or corrupt: rebuild rather than abort
cache[pkg] = {
    "latest": ver,
    "checked": d.datetime.now(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
tmp = path + ".tmp.%d" % os.getpid()
with open(tmp, "w") as fh:
    json.dump(cache, fh, indent=2)
os.replace(tmp, path)
EOF
  done
  exit 0
fi

# version_cmp <local> <latest> → -1 (local behind) | 0 (same) | 1 (local ahead)
#                               | __NC__ (not comparable: either side unparseable)
#
# Compares dot-separated numeric components, longest wins on a tie-break of
# equal prefixes (6.4 < 6.4.1). A pre-release/build suffix (-rc.1, +build) is
# dropped before comparison, so 6.5.0-rc.1 compares as 6.5.0 — deliberately
# coarse: this decides whether to NAG, not what to install, and treating an rc
# as its release keeps the siren quiet for someone deliberately running one.
#
# Anything that does not parse returns __NC__ so the caller can fall back to a
# plain inequality rather than guessing a direction.
version_cmp() {
  python3 - "$1" "$2" <<'EOF'
import re, sys

def parse(v):
    v = v.strip().lstrip("vV").split("+")[0].split("-")[0]
    if not v or not re.fullmatch(r"\d+(\.\d+)*", v):
        return None
    return [int(p) for p in v.split(".")]

a, b = parse(sys.argv[1]), parse(sys.argv[2])
if a is None or b is None:
    print("__NC__")
else:
    n = max(len(a), len(b))
    a += [0] * (n - len(a))
    b += [0] * (n - len(b))
    print(-1 if a < b else (1 if a > b else 0))
EOF
}

emit() {
  # emit <systemMessage-body>
  python3 - "$1" <<'EOF'
import json, sys
msg = sys.argv[1]
print(json.dumps({
    "systemMessage": msg,
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": (
            "HEADLINE ALERT (tooling-rot siren): local tooling is degraded or unverified. "
            "Per the 'distrust green until vetted' rule, surface this to the user in your "
            "FIRST message and treat it as outranking new work.\n" + msg
        ),
    },
}))
EOF
}

# ---------------------------------------------------------------- no config --
# Nothing was ever asked for, so nothing is claimed. Silent by design — the
# alternative is an alert on every session, which trains you to ignore it.
[ -f "$CONFIG" ] || exit 0

# ------------------------------------------------------------ read watchlist --
# Each watch entry may set any subset of:
#   plugin          plugin id, e.g. "mytool@my-marketplace"  (installed + enabled)
#   marketplace     marketplace dir name under plugins/marketplaces (git freshness)
#   cli             command name on PATH  (presence, and version vs plugin)
#   stale_days      freshness threshold for the marketplace checkout (default 14)
#   npm             npm package name; cached registry latest vs installed version
#   npm_ttl_hours   how old the cached registry answer may get (default 24)
#   npm_exempt      true = this cli is deliberately not npm-checked (see check 6)
#   pin_npm         npm package a hardcoded version is watched for (check 5)
#   pin_files       extra file globs to scan for that pin, beyond the plugin
#                   manifest — CI workflows, Dockerfiles, anything tracking a
#                   version by hand. ~ expands to $HOME. (check 5)
WATCH=$(python3 - "$CONFIG" <<'EOF'
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception as e:
    print("__PARSE_ERROR__%s" % e)
    sys.exit(0)
for w in cfg.get("watch", []):
    # \x1f (unit separator), NOT tab: tab is IFS whitespace, so bash's `read`
    # collapses runs of it and strips leading ones — which silently shifts every
    # field left whenever an entry omits a key. A non-whitespace delimiter makes
    # empty fields survive intact.
    print("\x1f".join([
        w.get("plugin", ""), w.get("marketplace", ""),
        w.get("cli", ""), str(w.get("stale_days", 14)),
        w.get("npm", ""), str(w.get("npm_ttl_hours", 24)),
        "true" if w.get("npm_exempt") else "false",
        w.get("pin_npm", ""),
        "\x1e".join(w.get("pin_files") or []),
    ]))
EOF
)

case "$WATCH" in
  __PARSE_ERROR__*)
    emit "TOOLING-ROT SIREN — config unreadable.
  $CONFIG failed to parse: ${WATCH#__PARSE_ERROR__}
  ZERO checks ran. Cannot-verify is a finding, not a skip."
    exit 0
    ;;
esac

if [ -z "$WATCH" ]; then
  # A config that exists but watches nothing is the case worth flagging:
  # coverage was intended and isn't there.
  emit "TOOLING-ROT SIREN — empty watchlist.
  $CONFIG parsed but lists nothing to watch, so ZERO checks ran.
  Either populate it or delete it (no config = intentionally silent)."
  exit 0
fi

# ----------------------------------------------------------------- the checks --
# Read on FD 3, not stdin: children spawned in the loop body inherit stdin and
# can consume it. Keeping the watchlist on its own descriptor makes the loop
# structurally immune to that, regardless of what a watched command does.
while IFS=$'\x1f' read -r -u 3 PLUGIN MKT_NAME CLI STALE_DAYS NPM_PKG NPM_TTL NPM_EXEMPT PIN_NPM PIN_FILES; do
  [ -z "$PLUGIN$MKT_NAME$CLI$NPM_PKG$PIN_NPM$PIN_FILES" ] && continue
  # PIN_NPM last in the chain: an entry that watches only pinned files has no
  # plugin, cli, marketplace or npm key, and an empty label renders as a bare
  # "- :" that names nothing.
  LABEL="${PLUGIN:-${CLI:-${MKT_NAME:-${NPM_PKG:-$PIN_NPM}}}}"
  MKT="$CLAUDE_DIR/plugins/marketplaces/$MKT_NAME"
  PLUGIN_VER="unknown"
  CLI_VER="unknown"   # hoisted: the npm check below needs it even if no cli key

  # 1. Plugin installed AND enabled. (A past failure: flat files bypassed the
  #    plugin system entirely, so nothing tracked versions at all.)
  if [ -n "$PLUGIN" ]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    if ! grep -q "\"$PLUGIN\"" "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null; then
      FINDINGS+=("$LABEL: plugin NOT installed (claude plugin install $PLUGIN)")
    elif ! python3 -c "
import json,sys
d=json.load(open('$CLAUDE_DIR/settings.json'))
sys.exit(0 if d.get('enabledPlugins',{}).get('$PLUGIN') else 1)" 2>/dev/null; then
      FINDINGS+=("$LABEL: plugin installed but NOT enabled in settings.json")
    fi
  fi

  # 2. Marketplace checkout freshness. A stale checkout drifts silently.
  if [ -n "$MKT_NAME" ]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    if [ -d "$MKT/.git" ]; then
      LAST_FETCH="$MKT/.git/FETCH_HEAD"
      [ -f "$LAST_FETCH" ] || LAST_FETCH="$MKT/.git/HEAD"
      if [ -n "$(find "$LAST_FETCH" -mtime +"${STALE_DAYS:-14}" 2>/dev/null)" ]; then
        FINDINGS+=("$LABEL: marketplace checkout not refreshed in >${STALE_DAYS:-14} days (claude plugin marketplace update $MKT_NAME)")
      fi
      PLUGIN_VER=$(python3 -c "
import json;print(json.load(open('$MKT/.claude-plugin/plugin.json'))['version'])" 2>/dev/null || echo "unknown")
    else
      FINDINGS+=("$LABEL: marketplace checkout missing at $MKT")
    fi
  fi

  # 3. CLI presence, and CLI-vs-plugin version skew. The CLI and the plugin
  #    that drives it must move together or the plugin calls a stale surface.
  if [ -n "$CLI" ]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    if command -v "$CLI" >/dev/null 2>&1; then
      # Strip ANSI: many CLIs print a decorated banner for --version.
      # </dev/null is mandatory: some watched "CLIs" are MCP stdio servers that
      # do not recognize --version and instead start up and read stdin to EOF.
      # Without this they drain the watchlist and every later entry is silently
      # skipped — a truncated denominator inside the denominator checker.
      CLI_VER=$("$CLI" --version 2>/dev/null </dev/null | sed $'s/\x1b\\[[0-9;]*m//g' \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      CLI_VER=${CLI_VER:-unknown}
      if [ "$PLUGIN_VER" != "unknown" ] && [ "$CLI_VER" != "unknown" ] \
         && [ "$CLI_VER" != "$PLUGIN_VER" ]; then
        FINDINGS+=("$LABEL: version skew — CLI $CLI_VER vs plugin $PLUGIN_VER; sync them")
      fi
    else
      FINDINGS+=("$LABEL: CLI '$CLI' not on PATH")
    fi
  fi

  # 4. Published-version drift. The checks above all compare local things to
  #    each other, so a machine can be perfectly self-consistent and a year
  #    behind the registry — which is exactly how a stale CLI goes unnoticed.
  #    Read-only against a cache; the refresh is dispatched after the loop.
  if [ -n "$NPM_PKG" ]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    CACHED=$(python3 - "$CACHE" "$NPM_PKG" <<'EOF'
import json, sys, datetime as d
try:
    entry = json.load(open(sys.argv[1]))[sys.argv[2]]
    checked = d.datetime.strptime(entry["checked"], "%Y-%m-%dT%H:%M:%SZ") \
               .replace(tzinfo=d.timezone.utc)
    age_h = (d.datetime.now(d.timezone.utc) - checked).total_seconds() / 3600
    print("%s\x1f%.1f" % (entry["latest"], age_h))
except Exception:
    print("__NONE__")   # absent, corrupt, or unparseable == no data, not zero drift
EOF
)
    LOCAL_VER="$CLI_VER"
    [ "$LOCAL_VER" = "unknown" ] && LOCAL_VER="$PLUGIN_VER"

    if [ "$CACHED" = "__NONE__" ]; then
      # Cannot-verify is a finding, not a skip. Said once, then the refresh
      # dispatched below means the next session has real data.
      FINDINGS+=("$LABEL: npm latest for '$NPM_PKG' — cannot verify (no cached data yet; refresh dispatched)")
      NEED_REFRESH+=("$NPM_PKG")
    else
      IFS=$'\x1f' read -r NPM_LATEST CACHE_AGE <<< "$CACHED"
      IS_STALE=$(python3 -c "print(1 if $CACHE_AGE > ${NPM_TTL:-24} else 0)" 2>/dev/null || echo 0)
      [ "$IS_STALE" = "1" ] && NEED_REFRESH+=("$NPM_PKG")
      AGE_NOTE=""
      [ "$IS_STALE" = "1" ] && AGE_NOTE=" (cache ${CACHE_AGE}h old — stale, refresh dispatched)"

      # Direction matters. This was a bare `!=`, so ANY difference read as
      # "upstream published something newer" — including local being AHEAD,
      # which is the normal state for up to a full TTL after an upgrade. The
      # siren then named the OLDER version and told the user to install it,
      # reverting a good upgrade. See `version_cmp`: -1 behind, 0 same, 1 ahead,
      # __NC__ when either side will not parse.
      VER_CMP=$(version_cmp "$LOCAL_VER" "$NPM_LATEST")

      if [ "$LOCAL_VER" = "unknown" ]; then
        FINDINGS+=("$LABEL: npm latest is $NPM_LATEST but local version — cannot verify (no cli or marketplace version to compare)$AGE_NOTE")
      elif [ "$VER_CMP" = "1" ]; then
        # Local is NEWER than the cached registry answer. That is not rot — it
        # is proof the CACHE is wrong, which outranks a fresh TTL, so refresh
        # regardless of the clock and stay quiet. Reporting here would be a
        # false finding on healthy tooling, and the remediation would be a
        # downgrade.
        case " ${NEED_REFRESH[*]:-} " in
          *" $NPM_PKG "*) : ;;
          *) NEED_REFRESH+=("$NPM_PKG") ;;
        esac
      elif [ "$VER_CMP" = "-1" ] || { [ "$VER_CMP" = "__NC__" ] && [ "$LOCAL_VER" != "$NPM_LATEST" ]; }; then
        # Behind, or unparseable-and-different. Unparseable falls back to the
        # old inequality on purpose: a version this script cannot parse must
        # still be REPORTED, never silently treated as equal, or a parse gap
        # becomes a false green.
        FINDINGS+=("$LABEL: newer release published — local $LOCAL_VER vs npm latest $NPM_LATEST (npm i -g $NPM_PKG@$NPM_LATEST)$AGE_NOTE")
      elif [ "$IS_STALE" = "1" ]; then
        # Versions agree, but on data old enough that agreement proves little.
        FINDINGS+=("$LABEL: npm check is stale — cache ${CACHE_AGE}h old, cannot confirm $LOCAL_VER is still current (refresh dispatched)")
      fi
    fi
  fi

  # 5. Hardcoded-version skew. Checks 1-4 look at what the machine INSTALLED;
  #    none of them reads a version something has written down by hand. A pin
  #    keeps its value forever while everything around it floats to latest, and
  #    every other check stays green because every other check is looking
  #    somewhere else.
  #
  #    Two places carry such a pin, and they need separate scans because they are
  #    found in completely different ways:
  #      5a  a PLUGIN MANIFEST, reached through the plugin's recorded installPath
  #      5b  ordinary FILES named by a glob — CI workflows, Dockerfiles, scripts
  #
  #    The registry answer is resolved once here and shared, so an entry watching
  #    both does not read the cache twice or dispatch two refreshes.
  PIN_LATEST="__NONE__"
  PIN_NOTE=""
  if [ -n "$PIN_NPM" ]; then
    PIN_CACHED=$(python3 - "$CACHE" "$PIN_NPM" <<'EOF'
import json, sys, datetime as d
try:
    entry = json.load(open(sys.argv[1]))[sys.argv[2]]
    checked = d.datetime.strptime(entry["checked"], "%Y-%m-%dT%H:%M:%SZ") \
               .replace(tzinfo=d.timezone.utc)
    age_h = (d.datetime.now(d.timezone.utc) - checked).total_seconds() / 3600
    print("%s\x1f%.1f" % (entry["latest"], age_h))
except Exception:
    print("__NONE__")
EOF
)
    if [ "$PIN_CACHED" != "__NONE__" ]; then
      IFS=$'\x1f' read -r PIN_LATEST PIN_AGE <<< "$PIN_CACHED"
      PIN_STALE=$(python3 -c "print(1 if $PIN_AGE > ${NPM_TTL:-24} else 0)" 2>/dev/null || echo 0)
      if [ "$PIN_STALE" = "1" ]; then
        NEED_REFRESH+=("$PIN_NPM")
        PIN_NOTE=" (cache ${PIN_AGE}h old — stale, refresh dispatched)"
      fi
    fi
  fi

  # 5a. The pin inside a plugin's own manifest. Not hypothetical: harness-claude
  #     pins @harness-engineering/cli at an exact version in its mcpServers args
  #     while this machine's mise pin tracks `latest`. They agree on install day
  #     and diverge silently on the next release.
  #
  #     The pin is buried in an args array, not a top-level field, so this scans
  #     the manifest TEXT for `<pkg>@<version>` rather than reading a known key.
  #
  #     Skipped without complaint when pin_files is set: watching repo files and
  #     no plugin is a legitimate configuration, and demanding a bogus `plugin`
  #     key to reach the check would be a misconfiguration of our own making.
  if [ -n "$PIN_NPM" ] && { [ -n "$PLUGIN" ] || [ -z "$PIN_FILES" ]; }; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    if [ -z "$PLUGIN" ]; then
      FINDINGS+=("$LABEL: pin_npm '$PIN_NPM' needs a 'plugin' key to locate the manifest (or a 'pin_files' glob); pin NOT checked")
    else
      PIN_VER=$(python3 - "$CLAUDE_DIR/plugins/installed_plugins.json" "$PLUGIN" "$PIN_NPM" <<'EOF'
import json, re, sys
reg, pid, pkg = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    entries = json.load(open(reg))["plugins"][pid]
except Exception:
    print("__NOPLUGIN__"); raise SystemExit
# Prefer the user-scope install: that is the one a SessionStart hook sees.
entries = sorted(entries, key=lambda e: e.get("scope") != "user")
for e in entries:
    path = e.get("installPath", "")
    for name in (".claude-plugin/plugin.json", "plugin.json"):
        try:
            text = open("%s/%s" % (path, name)).read()
        except Exception:
            continue
        # Scan raw text: the pin lives inside an args array, not a known key.
        m = re.search(re.escape(pkg) + r"@(\d[A-Za-z0-9.\-+]*)", text)
        print(m.group(1) if m else "__NOPIN__")
        raise SystemExit
print("__NOMANIFEST__")
EOF
)
      case "$PIN_VER" in
        __NOPLUGIN__)
          FINDINGS+=("$LABEL: pin for '$PIN_NPM' — cannot verify (plugin '$PLUGIN' not in installed_plugins.json)") ;;
        __NOMANIFEST__)
          FINDINGS+=("$LABEL: pin for '$PIN_NPM' — cannot verify (no readable plugin manifest at the recorded installPath)") ;;
        __NOPIN__)
          # Declared coverage that matched nothing. Either the plugin dropped the
          # pin (good — remove the key) or the package name is wrong (bad — the
          # check has been silently inert). Both need a human; neither is a pass.
          FINDINGS+=("$LABEL: no pin for '$PIN_NPM' found in the plugin manifest — pin_npm is watching nothing; drop the key or fix the package name") ;;
        *)
          if [ "$PIN_LATEST" = "__NONE__" ]; then
            FINDINGS+=("$LABEL: pin '$PIN_NPM@$PIN_VER' — cannot verify (no cached registry data yet; refresh dispatched)")
            NEED_REFRESH+=("$PIN_NPM")
          else
            # Direction matters, as in check 4: a pin AHEAD of the cached answer
            # proves the CACHE is wrong, not the plugin. Reporting it would
            # prescribe a downgrade.
            PIN_CMP=$(version_cmp "$PIN_VER" "$PIN_LATEST")
            if [ "$PIN_CMP" = "-1" ] || { [ "$PIN_CMP" = "__NC__" ] && [ "$PIN_VER" != "$PIN_LATEST" ]; }; then
              FINDINGS+=("$LABEL: plugin manifest pins $PIN_NPM@$PIN_VER but npm latest is $PIN_LATEST — the plugin will keep spawning the pinned version; update the plugin or repin it$PIN_NOTE")
            elif [ -n "$PIN_NOTE" ]; then
              FINDINGS+=("$LABEL: pin check is stale — cache too old to confirm $PIN_NPM@$PIN_VER is still current (refresh dispatched)")
            fi
          fi ;;
      esac
    fi
  fi

  # 5b. The same pin, in files the plugin machinery cannot see. A version tracked
  #     by hand in a CI workflow, a Dockerfile, or a install script is the same
  #     rot as a manifest pin, and nothing above reaches it: check 5a finds the
  #     manifest through the plugin's installPath, so a repo file is structurally
  #     invisible to it.
  #
  #     Found by reviewing #16: required-review.yml pinned the harness CLI at
  #     12.6.0 in two places while the plugin manifest, the local install, and the
  #     registry were all on 12.7.0 — and the pin's own adjacent comment declared
  #     the invariant it was breaking (#22).
  if [ -n "$PIN_FILES" ]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    if [ -z "$PIN_NPM" ]; then
      FINDINGS+=("$LABEL: pin_files is set but needs a 'pin_npm' key naming the package to look for; nothing was scanned")
    else
      # Emits one "version\x1fpath" line per DISTINCT (path, version) pair, so a
      # package pinned twice at the same version in one file is one finding, not
      # two — two findings for one edit is the noise that stops a siren being read.
      PIN_HITS=$(python3 - "$PIN_NPM" "$PIN_FILES" <<'EOF'
import glob, os, re, sys
pkg, spec = sys.argv[1], sys.argv[2]
pat = re.compile(re.escape(pkg) + r"@(\d[A-Za-z0-9.\-+]*)")
matched, seen, out = False, set(), []
for g in spec.split("\x1e"):
    if not g:
        continue
    for path in sorted(glob.glob(os.path.expanduser(g))):
        if not os.path.isfile(path):
            continue
        matched = True
        try:
            text = open(path, errors="replace").read()
        except Exception:
            continue
        for ver in pat.findall(text):
            key = (path, ver)
            if key not in seen:
                seen.add(key)
                out.append("%s\x1f%s" % (ver, path))
if not matched:
    print("__NOMATCH__")          # a glob matching nothing checked nothing
elif not out:
    print("__NOPIN__")            # files read, package absent from all of them
else:
    print("\n".join(out))
EOF
)
      case "$PIN_HITS" in
        __NOMATCH__)
          # The zero denominator, in the shape this hook was written for: rename a
          # workflow directory and the check retires itself with no sign it did.
          FINDINGS+=("$LABEL: pin_files matched no files, so the '$PIN_NPM' pin was NOT checked — fix the glob or drop the key") ;;
        __NOPIN__)
          FINDINGS+=("$LABEL: no pin for '$PIN_NPM' found in any file matched by pin_files — the key is watching nothing; drop it or fix the package name") ;;
        *)
          if [ "$PIN_LATEST" = "__NONE__" ]; then
            FINDINGS+=("$LABEL: pins for '$PIN_NPM' found in files but — cannot verify (no cached registry data yet; refresh dispatched)")
            NEED_REFRESH+=("$PIN_NPM")
          else
            # `~` as a literal, via a variable: a backslash-escaped tilde in a
            # ${var/#pat/repl} replacement stays a backslash, and an unquoted one
            # would expand right back to $HOME.
            TILDE='~'
            while IFS=$'\x1f' read -r FV FP; do
              [ -z "$FV" ] && continue
              # Same direction rule as 4 and 5a: a pin AHEAD of the cached answer
              # means the cache is stale, not that the file rotted.
              FCMP=$(version_cmp "$FV" "$PIN_LATEST")
              if [ "$FCMP" = "-1" ] || { [ "$FCMP" = "__NC__" ] && [ "$FV" != "$PIN_LATEST" ]; }; then
                FINDINGS+=("$LABEL: ${FP/#$HOME/$TILDE} pins $PIN_NPM@$FV but npm latest is $PIN_LATEST — update the pin (re-validate against it, never bump blind)$PIN_NOTE")
              fi
            done <<< "$PIN_HITS"
          fi ;;
      esac
    fi
  fi

  # 6. Coverage honesty about the watchlist ITSELF. Checks 1-5 report on what
  #    they were pointed at; none of them can notice being pointed at nothing.
  #    A `cli` with no `npm` key silently skips check 4 for that entry, so a
  #    half-covered watchlist reports exactly like a fully covered one.
  #
  #    Not hypothetical: this siren's own config watched two CLIs and named an
  #    npm package for one. Drift detection covered 1 of 2 and said nothing
  #    about the other — the omission read as coverage. That is the same
  #    false-green shape as "0 tests failed" out of zero tests, reproduced
  #    inside the tool built to catch it.
  #
  #    Deliberately NOT counted in CHECKS_RUN: the complaint is that no check
  #    ran, so counting it would pad the denominator this hook exists to keep
  #    honest. And silence must be EARNED by declaring npm_exempt, never
  #    granted by omission — otherwise the quiet state is the unconfigured one.
  if [ -n "$CLI" ] && [ -z "$NPM_PKG" ] && [ "$NPM_EXEMPT" != "true" ]; then
    FINDINGS+=("$LABEL: partial coverage — CLI '$CLI' is watched but no 'npm' key names a package, so published-version drift is NOT checked for it. Add \"npm\": \"<package>\", or \"npm_exempt\": true if it is not published to npm.")
  fi
done 3<<< "$WATCH"

# ------------------------------------------------------- dispatch the refresh --
# Detached and fully redirected: nohup + background + closed stdio means the
# hook returns now and the network call outlives it. Never `wait`.
if [ "${#NEED_REFRESH[@]}" -gt 0 ] && command -v npm >/dev/null 2>&1; then
  # Re-invoke through `bash`, not `"$0"` directly: if the file is deployed
  # without its exec bit the direct form dies with EACCES into /dev/null and
  # the cache never refreshes again — a silent failure inside the thing built
  # to catch silent failures. `bash` makes the refresh independent of file mode.
  nohup bash "$0" --refresh-npm-cache "${NEED_REFRESH[@]}" >/dev/null 2>&1 </dev/null &
  disown 2>/dev/null || true
fi

# --------------------------------------------------------------------- report --
if [ "${#FINDINGS[@]}" -eq 0 ]; then
  # Healthy AND non-empty denominator: this is the one case worth staying quiet for.
  exit 0
fi

LINES=""
for f in "${FINDINGS[@]}"; do LINES="$LINES
  - $f"; done
emit "TOOLING-ROT SIREN — ${#FINDINGS[@]} finding(s) across $CHECKS_RUN check(s):$LINES"
exit 0
