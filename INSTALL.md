# Install

For the agent running this: work through §§1–5 below in order, then §6 (optional)
and §7 (re-installs only, but read it before trusting an existing setup). **Never
overwrite an existing file without showing the user a diff and getting a yes** —
this machine may already have a config worth keeping.

Paths below assume the bundle is the current directory.

---

## 1. Global working rules — two files, not one

The rules are split by **audience**, not by topic:

```
~/.config/ai-rules/global.md   ← agent-agnostic. Claude, Gemini, Codex, Copilot
                                  all read this same file.
~/.claude/CLAUDE.md            ← Claude Code only: skills, hooks, settings keys,
                                  tool behavior. Starts with an @import of the
                                  shared file.
```

```bash
mkdir -p ~/.config/ai-rules ~/.claude
```

- If `~/.config/ai-rules/global.md` **does not exist** → copy
  `home/ai-rules/global.md` there.
- If `~/.claude/CLAUDE.md` **does not exist** → copy `home/CLAUDE.md` there.
- If either **does exist** → show the user a diff and ask whether to merge,
  replace, or skip. Do not silently clobber.

Point the other agents at the shared file too — each reads its own filename, so
a symlink is the cheapest way to keep them from drifting apart:

```bash
ln -s ~/.config/ai-rules/global.md ~/.gemini/GEMINI.md   # and AGENTS.md, etc.
```

**Why split at all.** The single-file version drifted: a rule got improved while
answering a Claude question, and the copy the other three agents read stayed
wrong. One file with one owner is the fix. The cost is that every rule now has
to earn its place on one side of the line — anything naming a skill, hook, or
`settings.json` key belongs in `CLAUDE.md`, everything else in `global.md`.

**Verify the import resolved.** `CLAUDE.md` line 6 is
`@~/.config/ai-rules/global.md`; a failed import is silent, and silence here
looks exactly like a machine with no rules. In a new session, ask the agent to
state rule 3 — it should answer **"always do TDD"**, which only exists in the
shared file. If it can't, replace the `~` with the absolute home path and retry.

## 2. The visual-decisions skill

```bash
mkdir -p ~/.claude/skills
cp -R home/skills/visual-decisions ~/.claude/skills/
```

Verify it registers: it should appear in the skill listing as
`visual-decisions` in a new session.

## 3. The tooling-rot siren

```bash
mkdir -p ~/.claude/hooks
cp home/hooks/tooling-rot-siren.sh ~/.claude/hooks/
cp home/hooks/rot-watch.example.json ~/.claude/hooks/
chmod +x ~/.claude/hooks/tooling-rot-siren.sh
```

The hook is **silent until configured** — with no `rot-watch.json` it exits
immediately. That's intended: nothing was asked for, so nothing is claimed.

To turn it on, copy the example to `~/.claude/hooks/rot-watch.json` and list the
plugins/CLIs worth watching on this machine. A watchlist that exists but is
empty **will** report itself — coverage was intended and isn't there.

### What it checks

| Key | Compares | Network |
|---|---|---|
| `plugin` | installed **and** enabled in `settings.json` | no |
| `marketplace` | git checkout age vs `stale_days` | no |
| `cli` | on PATH, and `--version` vs the plugin version | no |
| `npm` | installed version vs the registry's `latest` | **cached only** |
| `npm_exempt` | *declares* that a `cli` is deliberately not npm-checked | no |
| `pin_npm` | a version this **plugin hardcodes in its own manifest** vs the registry's `latest` | **cached only** |
| `pin_files` | the same pin, in **files you name with a glob** — CI workflows, Dockerfiles, scripts | **cached only** |
| `pin_ref` | git ref a stale `pin_files` hit is cross-checked against, to tell a stale *checkout* from a stale *repo* | no (local git) |

`pin_npm` covers a blind spot the others share: they all inspect what the
machine *installed*. A plugin can hardcode `some-pkg@1.2.3` inside an
`mcpServers` command line and keep spawning 1.2.3 forever while your own CLI
floats to `latest` — with every other check green, because every other check is
looking somewhere else. The pin lives in an args array rather than a named
field, so the check scans the manifest text for `<package>@<version>`.

It needs a `plugin` key to find the manifest (via the recorded `installPath`),
and it reports rather than skips in all three ways it can come up empty: no such
plugin, no readable manifest, or no pin matching that package name. A `pin_npm`
watching nothing is declared coverage that was never delivered.

`pin_files` covers the *other* place a version gets written by hand, which the
manifest scan structurally cannot reach: an ordinary repo file.

```json
{
  "pin_npm": "@harness-engineering/cli",
  "pin_files": ["~/Github/my-repo/.github/workflows/*.yml"]
}
```

`~` expands to `$HOME`. Each distinct file-and-version pair is reported once, so
a package pinned twice at the same version in one file is one finding rather than
two — but two files pinned at *different* versions are two findings, because
fixing one would otherwise leave the other looking handled.

Two ways it can come up empty, both reported:

- **The glob matched no files.** Rename a workflow directory and the check
  retires itself; without this it would look exactly like a glob that matched a
  clean file. This is the zero denominator in its purest form.
- **Files matched, but none mentions the package.** Either the pin was removed
  (drop the key) or the package name is wrong (the check has been inert).

`pin_files` needs a `pin_npm` naming what to look for, but it does **not** need a
`plugin` key — a repo's CI pins are nobody's plugin.

#### It reads the working tree, so it cross-checks the ref

The glob hits the filesystem, which means it sees **whatever branch is checked
out** — not the repo's settled state. Sit on a feature branch that predates a pin
fix and the file really does still say the old version.

Reporting that as-is was wrong in a specific way: the finding named a file and
nothing else, so "main is stale" and "you are on an old branch" looked identical,
and the second fires for anyone mid-feature — which is most of the time.

So on a hit, and **only** on a hit, the check asks git which case it is:

- **The ref is stale too** → real rot. `update the pin`, as before.
- **The ref already pins something current** → your checkout is behind, not the
  repo. The finding says so, names the branch, and explicitly does *not* tell you
  to edit a file that is already correct on `main`.
- **The ref will not resolve** → the finding still reports the stale pin and adds
  that it could not tell which case this is. Cannot-verify is a finding, not a
  skip.

`pin_ref` picks the ref; the default tries `origin/HEAD`, then `origin/main`,
then `main`. Every call is local and read-only — no network, and nothing runs at
all unless something was already found, so a clean machine pays nothing.

The first three compare local things to each other, so a machine can be
perfectly self-consistent and still be a year behind the registry. `npm` closes
that gap — but it never blocks SessionStart. It reads
`~/.claude/hooks/.rot-npm-cache.json`; when that is absent or older than
`npm_ttl_hours` (default 24) it dispatches a **detached** refresh for the next
session. Consequences worth knowing:

- The first session after adding an `npm` key reports `cannot verify (no cached
  data yet)`. The session after that reports real drift. That is the honest
  sequence, not a bug.
- Offline degrades to *stale data, explicitly labelled with its age* — never to
  silence. A blocking `npm view` would instead hit the 10s hook timeout and be
  killed mid-run, printing nothing, which is indistinguishable from all-clear.

### Partial coverage is a finding too

The checks above report on what they were pointed at. None of them can notice
being pointed at *nothing* — so an entry with a `cli` and no `npm` key skips the
drift check silently, and a half-covered watchlist reports identically to a
fully covered one.

This siren's own config shipped that way: two watched CLIs, one `npm` key. Drift
detection covered 1 of 2 and said nothing about the other. So the siren now
flags any `cli` with no `npm` package named:

```
partial coverage — CLI 'foo' is watched but no 'npm' key names a package,
so published-version drift is NOT checked for it.
```

If the CLI genuinely isn't published to npm, declare it:

```json
{ "cli": "foo", "npm_exempt": true }
```

Silence is **earned by declaring the gap**, never granted by omitting the key —
otherwise the quiet state is the unconfigured one, which is the whole failure
mode this hook exists to prevent.

### Testing it

The repo ships executable tests — run them all against the working copy:

```bash
./tests/run-all.sh          # every suite
./tests/test-siren.sh       # or one at a time
```

| Suite | Cases | Covers |
|---|---|---|
| `test-siren.sh` | 22 | abstention path, field-shift regressions, npm drift, partial coverage, the no-network-on-the-hot-path contract |
| `test-nudge.sh` | 19 | intent-vs-evidence, compound-command failures, both firing conditions, sidechain isolation |
| `test-statusline.sh` | 17 | last-record-not-sum, billing weights, colour thresholds, truncated-line survival |
| `test-drift.sh` | 41 | expected-vs-real difference on the `@import` line, missing/orphaned files, machine-local exclusions, the abstention exit code, the exec-bit check, the read-only contract (see §7) |
| `test-bare-install.sh` | 34 | exit 0 not the exit-2 abstention, the tool's own denominator, disclosure on both paths, the drift-artifact resolver, a caller-supplied root surviving both paths |

Every bug that has escaped these hooks has a case there. `run-all.sh` treats
**zero matched suites as a failure**, not a pass — a runner that globs, matches
nothing, and exits 0 is the same false green the hooks themselves watch for.

The probes below are different and still worth running once: they exercise the
**deployed** copy at `~/.claude/hooks/`, catching install-time problems (wrong
path, missing exec bit, stale copy) that a test against the repo cannot see.
**Both are required** — the empty-watchlist probe alone has a zero denominator:
it only exercises the "nothing to check" path and never once parses a real watch
entry, which is exactly how two parsing bugs shipped in this hook.

**Probe 1 — the abstention path:**

```bash
printf '{"watch":[]}' > /tmp/rot-empty.json && \
  CONFIG=/tmp/rot-empty.json bash -c 'cp /tmp/rot-empty.json ~/.claude/hooks/rot-watch.json; ~/.claude/hooks/tooling-rot-siren.sh; rm ~/.claude/hooks/rot-watch.json'
```

Expect JSON on stdout containing `TOOLING-ROT SIREN — empty watchlist`. If you
get nothing, the hook is not working — fix that before trusting it.

**Probe 2 — the parsing path.** Three entries, each omitting a different key,
plus one CLI that cannot exist:

```bash
printf '{"watch":[{"plugin":"ghost@nowhere","marketplace":"nowhere","cli":"nope-1"},{"marketplace":"nowhere","cli":"nope-2"},{"cli":"nope-3"}]}' \
  > ~/.claude/hooks/rot-watch.json
~/.claude/hooks/tooling-rot-siren.sh; rm ~/.claude/hooks/rot-watch.json
```

Expect **`across 6 check(s)`** and a `CLI 'nope-N' not on PATH` finding for all
three of `nope-1`, `nope-2`, `nope-3`. Two specific failures to watch for:

- **Fewer than 6 checks, or a missing `nope-3`** — entries are being dropped.
  Something in the loop body is consuming the watchlist on stdin (an MCP stdio
  server that ignores `--version` will do this). The loop must read on FD 3.
- **Findings naming the wrong field** (e.g. a marketplace check against
  `nope-2`, or `CLI '14' not on PATH`) — fields are shifting left because the
  delimiter is IFS whitespace. It must be `\x1f`, not a tab.

A watched "CLI" that is actually an MCP stdio server is the common trigger for
the first failure — probe 2 is what catches it.

**Probe 3 — the deployed copy can refresh its own npm cache.** The refresh runs
detached with its output closed, so a failure here is invisible by construction:

```bash
bash ~/.claude/hooks/tooling-rot-siren.sh --refresh-npm-cache npm
cat ~/.claude/hooks/.rot-npm-cache.json
```

Expect a `npm` entry with a `latest` and a fresh `checked` timestamp. Nothing
written means the deployed hook cannot refresh, and every later npm finding will
be based on data frozen at install time.

## 4. Context instruments

Two hooks that make context cost visible and act on it. They are independent of
the siren and of each other; install either alone.

```bash
cp home/hooks/statusline-context.sh home/hooks/clear-nudge.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/statusline-context.sh ~/.claude/hooks/clear-nudge.sh
```

Both are wired in `home/settings.template.json` (section 5) — `statusLine` for
the first, a `PostToolUse` matcher on `Bash` for the second.

**Why they exist.** Context is re-read on every turn, so cost scales with
*(context size × turns)*. With no instrument, a session drifts from a ~90k
baseline to 260k+ and every trivial reply costs ~26k weighted tokens before it
produces a word. The built-in corner indicator is passive enough that it gets
noticed several tasks too late.

### `statusline-context.sh` — the gauge

Renders `repo · ▓▓▓▓▓░░░░░ 52% 104k · burn 1.2M · Opus 5` on every turn. The
context figure is read from the **last non-sidechain usage record** in the
transcript — the number the API actually billed, not an estimate. Colour is the
signal: green under 60%, amber past 60, red past 80.

`burn` is the session total, weighted by billing class
(output ×5, cache-write ×1.25, cache-read ×0.1, input ×1). Subagent turns count
toward burn but never move the gauge — they spend real tokens, but they were
never in the main thread's window.

### `clear-nudge.sh` — the boundary nudge

Suggests `/clear` at the one moment it is free: right after a commit, PR, merge,
or push has **banked** the work, *and* context is already past 100k. Both
conditions or it stays quiet.

That second condition is the load-bearing one. A nudge that fires on every
threshold crossing regardless of what you're mid-way through becomes wallpaper —
which is exactly how the passive indicator stopped being read.

It requires **evidence, not intent**: the tool's own output must show the
boundary happened. This shipped a false positive keying on the command string
alone, and announced a commit that never occurred — a grep, an echo, a doc
example, and a test fixture all contain `git commit`. It also discards the whole
call if any part errored, because compound commands (`a; b; c`) report a single
exit status, so a failed push chained with a succeeding command arrives looking
successful. `tests/test-nudge.sh` pins both cases.

## 5. Settings

`home/settings.template.json` is a **template, not a drop-in** — it carries
`_comment` keys for readability that should be stripped, and its plugin list
should be reconciled with whatever is already installed here.

- If `~/.claude/settings.json` does not exist → strip the `_comment` keys and
  write it.
- If it exists → merge key by key, showing the user what changes. Preserve any
  existing `permissions.allow` entries; do not import an allowlist from
  elsewhere (see EXCLUDED.md for why).

Then install the plugins listed under `enabledPlugins`:

```bash
claude plugin install <plugin-id>
```

All of them are from the public `claude-plugins-official` marketplace. Only the
entries set to `true` need installing — the `false` ones are kept in the file on
purpose, recording which plugins were evaluated and switched **off** so the
decision survives rather than being silently re-made on the next machine.

Install what's actually useful here rather than all of them reflexively. Every
enabled plugin spends context on skill listings whether or not you ever use it;
trimming this map from 27 enabled to the current set recovered ~30k tokens of
listing per session. That is the same problem `skillOverrides` exists to solve,
one level up — and re-enabling one is a single flag, so bias toward off.

## 6. Memory seed (optional)

The memory directory is per-project and named after the project path, so it
can't be copied blind. Once a project directory exists at
`~/.claude/projects/<slug>/memory/`, copy `home/memory/*` into it.

Two seeds ship:

- `visual-learner.md` — mostly redundant with shared rule 1, so skipping it is
  fine; the agent re-derives it from `~/.config/ai-rules/global.md`.
- `shared-agent-rules-symlink.md` — **not** redundant. It records which of the
  two rules files is a real file and which is symlinked into Gemini/Codex/
  Copilot. Nothing in the rules themselves says this, and getting it backwards
  means a write to `~/.claude/CLAUDE.md` silently overwrites the shared file for
  all four agents. Worth seeding on any machine where you'll edit the rules.

---

## 7. Re-installing over a setup that already exists

Everything above is written for a machine with nothing on it. The second install
onto the *same* machine has the opposite failure mode: step 1 tells you not to
overwrite an existing file without asking, so the honest answer to that prompt is
often "skip" — and the skipped file then stays behind the bundle forever.

That is not hypothetical. `home/CLAUDE.md` once sat 7 hours ahead of the
deployed `~/.claude/CLAUDE.md`: the live rules were missing an entire section
describing two hooks that *were* installed and running, and still named
private-marketplace skills the bundle exists to have removed. Nothing surfaced
it, because a stale rules file loads, parses, and reads as authoritative exactly
like a current one.

So before trusting an existing install — and after merging anything under
`home/` — check the bundle against what is actually deployed:

```bash
./tools/check-drift.sh              # checks $HOME
CHECK_ROOT=/some/other/home ./tools/check-drift.sh
```

Exit codes are the contract, and the third one is the point:

| Exit | Means |
|---|---|
| `0` | every compared file matched, and it tells you how many it compared |
| `1` | drift, a missing file, or an **orphan** — something still installed that the bundle no longer ships, which keeps running every session |
| `2` | **abstention** — nothing of this bundle is installed here, so nothing was compared. Deliberately not `0`: a fresh clone must never report parity it never checked |

It is **read-only by contract**. It reports; it never repairs — quietly fixing
what it found would destroy the evidence of how far behind the machine had
drifted, and the size of that gap is the finding.

Two differences are expected rather than findings, and the tool already knows
both:

- **Line 6 of `CLAUDE.md`** may carry an absolutized `@/Users/<you>/...` import
  (see §1) instead of the `~` form the bundle ships. The tool canonicalizes the
  import *target* — it is not a blanket skip of that line, because an import
  rewritten to point somewhere else is the one edit that silently unloads every
  shared rule.
- **`rot-watch.json` and `.rot-npm-cache.json` are machine-local** — the repo
  ships only `.example.json`, and the cache is generated by the siren.

Anything else is drift: re-copy the file, then re-apply the absolutized import
if you use it.

`~/.claude/settings.json` is deliberately **not** in that list: it is a merge
target, not a copy target, so it is expected to diverge from the template. Check
it by hand against §5 instead.

---

## Verify

- [ ] A new session lists `visual-decisions` among available skills
- [ ] The agent can state rule 3 as "always do TDD" — proves the `@import` of
      `~/.config/ai-rules/global.md` resolved rather than failing silently
- [ ] The siren smoke-test above printed the empty-watchlist finding
- [ ] `./tests/run-all.sh` reports 5 suites, all clean
- [ ] The statusline renders a bar, a percentage, and a `burn` figure on a new
      session — a *blank* statusline means the hook died, and blank is
      indistinguishable from 0%
- [ ] Every watched `cli` in `rot-watch.json` either names an `npm` package or
      declares `"npm_exempt": true` — otherwise the siren is reporting on a
      watchlist it only half-checks
- [ ] `./tools/check-drift.sh` exits **0**, not 2 — on a re-install this is the
      item most likely to fail, and the one nothing else will tell you about. An
      exit of 2 on a machine you believe you installed to means the copies never
      landed where the tool looks
- [ ] Read the `not compared:` line that check prints — `settings.json` (§5) and
      the `memory/` seeds (§6) are outside its reach by design, so the two items
      below are checked by *you*, not by it. Its green covers 4 of the 6 things
      this file deploys
- [ ] `~/.claude/settings.json` parses (`python3 -m json.tool ~/.claude/settings.json`)
- [ ] No `_comment` keys survived into the live settings file
- [ ] The agent renders a visual before the next decision it puts to you —
      that's the real acceptance test for this whole bundle
