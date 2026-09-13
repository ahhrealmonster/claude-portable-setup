# claude-portable-setup Knowledge Map

## Project Overview

A portable bundle of a Claude Code working setup — **not an application**. It has
no build step, no package manager, and no runtime of its own. `home/` mirrors the
target machine's `$HOME`; installing means copying files out of it. The shipped
artifacts are three bash hooks, one skill, two rules files, a settings template,
and memory seeds.

Harness adoption level: `load-bearing-minimum`.

## Documentation

| File | What it holds |
|---|---|
| [`CLAUDE.md`](./CLAUDE.md) | **The detailed knowledge map** — repo thesis, load-bearing invariants, gate commands, editing conventions. Read it first. |
| [`INSTALL.md`](./INSTALL.md) | The executable install spec, written to be carried out by an agent. |
| [`EXCLUDED.md`](./EXCLUDED.md) | What was deliberately left out of the bundle, and why. |
| [`README.md`](./README.md) | What the bundle contains, for a human browsing it. |
| [`STRATEGY.md`](./STRATEGY.md) | What this repo is, who it serves, and what it refuses to become. |
| [`docs/changes/`](./docs/changes) | Per-change specs and implementation plans. |

The paths above are real links on purpose. The `AGENTS.md` validator checks every
link target and reports how many it checked — a map with no links passes that
check with a denominator of zero, which is the failure this repo exists to name.

`CLAUDE.md` carries the depth here rather than deferring to this file, because
its audience is the agent editing the bundle. This map exists to route the other
agents that read `AGENTS.md` by convention.

## Repository Structure

There is no `src/`. The three layers named in [`harness.config.json`](./harness.config.json) are:

| Layer | Path | What it is |
|---|---|---|
| `hooks` | [`home/hooks/`](./home/hooks) | Shipped bash hooks — deployed to `~/.claude/hooks/`, run with no clone present |
| `tools` | [`tools/`](./tools) | Repo-local scripts that operate *on* an install; never deployed |
| `tests` | [`tests/`](./tests) | Flat bash suites of `ok`/`bad` assertions; no framework |

Bash files here are standalone — nothing `source`s anything else, so the layer
rules encode invocation and deployment reality rather than import graphs.

## Development Workflow

Four gates before "done" or a PR. There is no build or typecheck step to run —
the bundle has no compiler and no package manager — so the gates map onto what
this repo actually has:

```bash
bash -n home/hooks/*.sh tools/*.sh tests/*.sh   # syntax
shellcheck home/hooks/*.sh tools/*.sh           # lint, default severity
shellcheck -S warning tests/*.sh                # suites carry known SC2015 infos
python3 -m json.tool home/settings.template.json && \
python3 -m json.tool home/hooks/rot-watch.example.json && \
python3 -m json.tool harness.config.json        # JSON parses
./tests/run-all.sh                              # test
```

CI runs all four on ubuntu and macos ([`.github/workflows/ci.yml`](./.github/workflows/ci.yml)),
plus a bare-install job that carries out `INSTALL.md` into a scratch `$HOME` via
[`tools/bare-install.sh`](./tools/bare-install.sh) and proves it landed. A
`gates-complete` job fails the aggregate when a leg was skipped rather than run.

[`tools/check-drift.sh`](./tools/check-drift.sh) is the check nothing else
performs: it diffs `home/` against the live `$HOME` install. Run it after
merging anything under `home/`. Exit **2 is neither pass nor fail** — nothing
was installed, so nothing was compared.

Hooks must stay clean at shellcheck's default severity; suites are gated at
`-S warning`. Never `--no-verify`.

## Architecture

There is no `docs/architecture.md`. The architectural commitments live in
`CLAUDE.md` under "The idea the whole repo encodes" and "Load-bearing invariants",
each row of which is a shipped bug pinned by a test.

The one-line version: **a zero denominator is an abstention, not a pass.**
