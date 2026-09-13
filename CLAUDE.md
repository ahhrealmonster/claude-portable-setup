# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

For *what this repo is for* and *what is left*, read [`STRATEGY.md`](STRATEGY.md)
(durable positions) and [`ROADMAP.md`](ROADMAP.md) (items, exit criteria, and the
issue tracking each). This file is the how-to-work-here map; those two are the
why and the what-next.

## What this repo is

A **portable bundle of a Claude Code working setup** — not an application. It has
no build step, no package manager, and no runtime of its own. `home/` is a mirror
of the target machine's `$HOME` layout; installing means copying files out of it
to `~/.claude/`, `~/.config/ai-rules/`, and `~/.claude/projects/<slug>/memory/`.
`INSTALL.md` is the executable spec for that copy — it is written to be *read and
carried out by an agent*, so treat it as the source of truth for install
behavior, not as prose docs.

The shipped artifacts are three bash hooks, one skill, two rules files, a
settings template, and memory seeds. Everything else (`README.md`, `INSTALL.md`,
`EXCLUDED.md`) explains or installs those.

`tools/` is the exception to "everything in this repo is cargo": it holds
repo-local scripts that operate *on* an install rather than shipping into one.
`check-drift.sh` lives there rather than in `home/hooks/` for a concrete reason
— checking drift requires the bundle to diff against, so it can only run from a
clone, which makes deploying it pointless.

## Commands

```bash
./tests/run-all.sh            # every suite (133 cases across 5)
./tests/test-siren.sh         # or one suite at a time
./tests/test-nudge.sh
./tests/test-statusline.sh
./tests/test-drift.sh
./tests/test-bare-install.sh
```

There is no test framework and no single-case filter — a suite is a flat bash
script of `ok`/`bad` assertions. To run one case, comment out the others or add a
temporary early `exit`.

The four gates for this repo. Run them by hand before a PR *and* they run in
CI — `.github/workflows/ci.yml` executes this same list on `ubuntu-latest` and
`macos-latest`. Keep the two in step: the workflow copies these commands
verbatim, and a gate that exists in only one of the two places is how the
documented gates and the enforced gates drift apart.

```bash
bash -n home/hooks/*.sh tools/*.sh tests/*.sh         # syntax
shellcheck home/hooks/*.sh tools/*.sh                # lint — clean at default severity
shellcheck -S warning tests/*.sh                     # suites carry known SC2015 infos
python3 -m json.tool home/settings.template.json     # JSON parses
python3 -m json.tool home/hooks/rot-watch.example.json
python3 -m json.tool harness.config.json
./tests/run-all.sh                                   # test
```

`gates-complete` is the aggregate job and the one to require on `main` — it is
what verifies each leg actually *ran*, so requiring the individual matrix legs
instead would let a skipped leg show as neutral, and would break the moment
`windows-latest` joins in M2. **A workflow without branch protection is
decorative**: until `gates-complete` is a required check, every gate here is
still advisory.

The suites use `[ cond ] && ok ... || bad ...` deliberately (the assertion
helpers are total), which shellcheck flags as SC2015 *info*. Hooks must stay
clean at default severity; suites are gated at `-S warning`.

### Deploy drift — the check nothing else performs

The source of truth is `home/`, but the *running* config is `$HOME`. They
diverge silently the moment a merged change isn't re-installed:

```bash
./tools/check-drift.sh                     # 0 clean · 1 drift · 2 abstention
CHECK_ROOT=/tmp/fixture ./tools/check-drift.sh
```

Run it after merging anything under `home/`, and before trusting a session's
rules. Read-only by contract — it reports, never repairs, because the size of
the gap is the finding and a silent auto-fix erases it.

Exit **2 is not a failure and not a pass**: nothing of the bundle was installed
at the root, so nothing was compared. Keeping it distinct from 0 is what stops a
fresh clone reporting parity it never checked.

Two differences are expected and the tool encodes both: the absolutized line-6
`@import` (per INSTALL.md §1) and the machine-local `rot-watch.json` /
`.rot-npm-cache.json`. The import handling canonicalizes the *target* rather
than skipping the line — `tests/test-drift.sh` pins both halves, because a
blanket line-6 skip would wave through an import rewritten to point elsewhere,
which is the one edit that silently unloads every shared rule.

**Its green is partial, and says so.** The check reaches 4 of the 6 things
INSTALL.md deploys. `settings.json` (§5) and the `memory/` seeds (§6) are
excluded deliberately — the template ships `permissions.allow: []` while the
live file carries entries grown from real prompts, and memory seeds are seeds
that accumulate — so diffing either would be red on every correct machine. The
exclusion is right; an unqualified "in sync" implying total coverage was not,
so both uncovered targets are named on every non-abstaining run, pass *and*
fail. Printing the caveat only on green would imply a red run's findings were
exhaustive.

It also compares **mode, not just content**: a deployed `*.sh` without `+x`
never runs, and Claude Code reports nothing when a hook fails to execute — the
session silently loses that hook's coverage. A byte-identical hook with the
wrong permissions is content-clean and functionally absent, which every check
passed before this one existed.

**This has already happened once.** `home/CLAUDE.md` sat 7h ahead of the
deployed copy after PRs #3 and #7: the live rules were missing the entire
context-instruments section and still named private-marketplace skills that
`EXCLUDED.md` had stripped. Nothing surfaced it, because a stale rules file
loads, parses, and reads as authoritative exactly like a current one.

### Bare install — proving a stranger's clone works

`check-drift.sh` compares an install that already exists. Nothing proved the
*act* of installing still works, and every suite here runs against a synthetic
root the test itself populated — so all of them would pass on a bundle whose
install spec had quietly stopped working.

```bash
./tools/bare-install.sh            # scratch root, cleaned up
./tools/bare-install.sh /tmp/probe # your root, left in place
```

It carries out `INSTALL.md` §§1–4 into a scratch `$HOME`, then runs the drift
check against *that* root and demands **exit 0 specifically**. Exit 2 is the
trap: it is check-drift's "nothing of the bundle is installed here, so nothing
was compared" abstention, and a job accepting any non-1 status would go green on
an install that copied zero files. The report would be indistinguishable from a
real pass.

Like the drift check, **its green is partial and says so**: it installs and
verifies §§1–4 and never touches `settings.json` (§5) or the `memory/` seeds
(§6), so it names those two on every path — pass *and* fail.

The suite runs every invocation with `HOME` pointed at an empty scratch
directory. That is not tidiness: `check-drift.sh` falls back to `$HOME` when
`CHECK_ROOT` is unset, so deleting the one line that sets it made the whole
suite pass 23/23 while verifying the author's real, in-sync install instead of
the scratch one. A suite that passes on any machine that has already run
`INSTALL.md` is precisely the false green this repo exists to name.

## The idea the whole repo encodes

**A zero denominator is an abstention, not a pass.** Every artifact here is a
variation on it, and changes that quietly weaken it are the main regression risk:

- `run-all.sh` treats zero matched suites as a hard **failure** — a runner that
  globs, matches nothing, and exits 0 is the exact false green the hooks watch for.
- `tooling-rot-siren.sh` is silent with **no** watchlist (nothing was asked for)
  but reports loudly on an **empty** one (coverage was intended and is absent),
  and flags a watched `cli` with no `npm` key as *partial coverage*. Silence is
  earned by declaring a gap (`"npm_exempt": true`), never by omitting a key.
- A blank statusline, an unfired nudge, and a hook killed by timeout all look
  identical to "all clear" — which is why each hook has an explicit degraded
  output rather than a quiet path.
- `check-drift.sh` spends a whole third exit code on "nothing was installed
  here", counts deployed **files** rather than directories (an empty
  `~/.claude/hooks/` is not an install), and prints its comparison count even on
  a clean run.

When editing a hook, ask what its *silent* state is indistinguishable from.

## Load-bearing invariants (each one is a shipped bug)

These are pinned by tests; breaking them is how the escaped defects escaped.

| Invariant | Where | Why |
|---|---|---|
| Watchlist fields joined with `\x1f`, never tab | `tooling-rot-siren.sh:110,141` | Tab is IFS whitespace, so `read` collapses empty fields and every value shifts left — findings then name the wrong CLI |
| The watch loop reads on **FD 3** (`read -u 3`) | `tooling-rot-siren.sh:141` | A subprocess in the loop body (an MCP stdio server that ignores `--version`) will otherwise eat the watchlist off stdin and silently drop entries |
| The hot path makes **no** network call | `tooling-rot-siren.sh` | A blocking `npm view` hits the 10s hook timeout and is killed mid-run, printing nothing. npm drift reads a cache refreshed by a detached re-invocation (`--refresh-npm-cache`); cache writes are atomic |
| Nudge requires **evidence, not intent** | `clear-nudge.sh` | Keying on the command string announced commits that never happened — a grep, an echo, a doc example and a test fixture all contain `git commit`. It also discards the call if any part errored, because `a; b; c` reports one exit status |
| Statusline uses the **last** usage record, not a sum | `statusline-context.sh` | Sidechain (subagent) turns spend real tokens but were never in the main window: they count toward `burn`, never toward the gauge |
| Hooks derive every path from `$HOME` | all three | Suites run each case against a synthetic `$HOME`; a hardcoded path makes the test touch the real `~/.claude` |
| The `@import` check canonicalizes the **target**, not the line | `check-drift.sh` | Skipping line 6 wholesale would pass an import rewritten to point elsewhere — the one edit that unloads every shared rule while the file still looks correct |
| The drift check never writes | `check-drift.sh` | Auto-repair would destroy the evidence of how far behind the machine had drifted, which is the actual finding |
| The uncovered targets print on **both** the pass and fail paths | `check-drift.sh` | `settings.json` and `memory/` are never compared; a bare "in sync" claims coverage the check does not have, and disclosing only on green would imply a red run's findings were exhaustive |
| Deployed `*.sh` are checked for `+x`, scoped to `.sh` | `check-drift.sh` | A hook without the exec bit never runs and Claude Code says nothing, so it is indistinguishable from a hook that ran clean. Scoped because `rot-watch.example.json` ships 0644 on purpose and demanding `+x` on data files would make a correct install permanently red |
| `bare-install` treats exit **2** as a failure | `tools/bare-install.sh` | Exit 2 is check-drift's "nothing was installed here" abstention. A job accepting any non-1 status would certify an install that copied zero files, and the report would look exactly like a real pass |
| The bare-install suite pins `HOME` to an empty directory | `tests/test-bare-install.sh` | `check-drift.sh` falls back to `$HOME` when `CHECK_ROOT` is unset, so dropping the one line that sets it left the suite passing 23/23 against the author's real install. Mutation-tested: with `HOME` empty the same edit fails 6 cases |
| The tool states its **own** file count, never the checker's | `tools/bare-install.sh` | A denominator borrowed from check-drift's "N check(s)" disappears the moment the checker is stubbed or silent, leaving a run that installed nothing and said nothing |
| The aggregate job fails on **skipped**, not only on failure | `.github/workflows/ci.yml` | A required check that never ran shows as neutral and a zero-leg matrix shows as skipped; both read as not-red. `if: always()` is load-bearing, and the job id must stay `bare_install` because `needs.bare-install.result` parses as a subtraction |
| The review gate says when it ran floor-only | `.github/workflows/required-review.yml` | Without an API key `review-ci` exits 0 with `ranLlmTier: false` — a green tick that reviewed nothing. The key stays optional; the check is not allowed to claim a review it did not perform (#17) |

## Conventions specific to this repo

- **`home/CLAUDE.md` is not this file.** It is the artifact deployed to
  `~/.claude/CLAUDE.md` on the target machine — Claude-only mechanics, opening
  with an `@import` of `home/ai-rules/global.md`. The split is by *audience*:
  anything naming a skill, hook, or `settings.json` key belongs in
  `home/CLAUDE.md`; everything else in `home/ai-rules/global.md`, which four
  agents read. On an installed machine the shared file is typically symlinked
  into Gemini/Codex/Copilot, so a careless write to `~/.claude/CLAUDE.md` can
  clobber the rules for all of them. And because nested `CLAUDE.md` files are
  picked up from directories being worked in, `home/CLAUDE.md` may load as
  *instructions* while you edit the bundle. It is cargo, not guidance — its
  "prefer skill X", "never heredoc" rules describe a target machine. Read it as
  text to be edited, not obeyed.
- **Comment the *why*, at length.** Every hook and suite opens with a header
  explaining the incident that produced it. A rule without its reason gets
  dropped the first time it is inconvenient — that is deliberate house style
  here, not verbosity to trim.
- **Themed test output is intentional** (`▲ every suite flew clean`). Keep it.
- **Nothing employer-, client-, or private-marketplace-specific ships.**
  `EXCLUDED.md` records what was left behind and why; add to it rather than
  re-litigating a cut.
- **Never commit an allowlist.** `.claude/settings.local.json` is gitignored and
  `settings.template.json` ships `permissions.allow: []` on purpose — this repo
  moves setups between laptops, which is precisely the leak vector.
- **`enabledPlugins: false` entries are kept on purpose** — they record which
  plugins were evaluated and switched off, so the decision survives the next
  machine. Don't prune them.

## Testing changes to a hook

Repo tests exercise `home/hooks/*.sh` directly. They cannot catch install-time
problems — wrong path, missing exec bit, a stale deployed copy — so after
changing a hook, also run the three manual probes in `INSTALL.md` §3 against
`~/.claude/hooks/`. Probe 2 (the parsing path) is the one that matters: probe 1
alone has a zero denominator, since it only ever exercises the
nothing-to-check branch.
