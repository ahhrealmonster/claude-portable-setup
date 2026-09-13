---
name: claude-portable-setup
last_updated: 2026-08-23
version: 1
---

# Strategy

A **public reference implementation of an agent working setup** — the rules,
hooks, and install spec one person actually runs, published so a stranger can run
them too.

Durable positions only. Anything that changes as work lands belongs in
[`ROADMAP.md`](ROADMAP.md), not here.

---

## Target problem

The repo has twelve merged PRs, four regression suites, 99 test cases, and no
statement of what it is for. Every artifact was justified against a local
argument and none against a whole. That held while there was exactly one
consumer. It stopped holding when three constraints arrived together:

1. The audience is **strangers**, not only the author.
2. A targeted consumer is on **Windows**, which nine `#!/bin/bash` artifacts do
   not serve (`home/hooks/*.sh`, `tools/check-drift.sh`, `tests/*.sh`).
3. The author needs a **company overlay**, which `EXCLUDED.md` forbids by
   construction today.

Each is individually answerable. Together they imply an architecture, and the
absence of that architecture — not any single missing feature — is the problem.

## Our approach

One public core, with everything situational layered on top of it. Never a fork.

```
  ┌─ CORE (public, this repo, CI-proven on 3 OSes) ────────────┐
  │  ai-rules/global.md    neutral principles, each with why   │
  │  hooks/                siren · statusline · nudge          │
  │  skills/               visual-decisions                    │
  │  settings.template     no allowlist, no private plugins    │
  │  harness.config.json   public CLI config, committed        │
  └────────────────────────┬───────────────────────────────────┘
                           │  precedence: machine > company > profile > core
     ┌─────────────────────┼─────────────────────┬─────────────────────┐
     ▼                     ▼                     ▼                     ▼
  PROFILE              COMPANY               MACHINE              (absent)
  profile.md           company/               rot-watch.json       core alone
  visual learner       private marketplace    permissions.local    is valid and
  machine count        client conventions     node/mise paths      complete
  visual level         .canary/company.json   exec-bit facts       ← the stranger
```

**Precedence: `machine > company > profile > core`.** Nothing in a lower layer
may depend on a higher layer existing.

### Layer contracts

- **Core** — knows nothing about any overlay, and must be fully functional with
  every overlay absent. A CI job that installs the core into a bare `$HOME` is
  what proves this rather than asserts it.
- **Profile** — per-person calibration. Facts about a human, not rules.
- **Company** — per-org extension. Gitignored here, or a sibling private repo.
  `EXCLUDED.md` becomes its specification.
- **Machine** — per-machine facts that must never be inherited: the rot
  watchlist, the permission allowlist, absolute toolchain paths.

### Why overlays and not a fork

A private fork of a public repo diverges silently, and this repo's own history is
the argument: `home/CLAUDE.md` sat seven hours ahead of its deployed copy after
PRs #3 and #7 and nothing surfaced it, because a stale file loads and parses
exactly like a current one. A fork is that same failure with a longer fuse. An
overlay cannot drift from the core, because it never contains a copy of it.

## Who it's for

| Reader | What they get | How |
|---|---|---|
| **A stranger** — first, always | The whole core, working, with nothing of anyone else's in it | Clone and follow `INSTALL.md` |
| **The author** | Personal calibration — visual level, machine count | A profile overlay |
| **A company** | Client conventions, private marketplace tooling | A company overlay, gitignored here or a sibling private repo |

Where a convenience helps only the author but assumes something about their
machine, **the stranger wins** and the author's version moves to an overlay.

## Key metrics

The headline test is one sentence, and every other decision inherits it:

> **A stranger clones it and it works on their machine.**

It is not a slogan while it is measured. The signals that make it falsifiable:

| Signal | Passing looks like |
|---|---|
| Bare-`$HOME` install | The core installs into a `$HOME` with no overlay present and exits **0**, not the drift check's `2` abstention |
| OS coverage | The four gates pass on every OS the repo claims, with no leg silently skipped |
| Private dependencies | Two `npm i -g` calls reach everything; no marketplace, no SSO, no login wall |
| Deploy drift | `./tools/check-drift.sh` reports parity with a **non-zero** denominator it prints |
| Status honesty | Every roadmap claim resolves to a commit and a tracked issue |

## Tracks

Four durable tracks. Their status, item IDs, and issue links live in
[`ROADMAP.md`](ROADMAP.md) — deliberately not here, so this file does not churn.

| Track | The question it closes |
|---|---|
| **Prove the green** | Are this repo's own gates un-skippable, and does the core install standalone? |
| **One core, three OSes** | Does the core serve a consumer whose machine is not the author's? |
| **Core plus overlay** | Can one bundle serve a stranger, its author, and a company without a fork? |
| **Keep it honest** | What catches the drift, the stale claim, and the orphaned process once people depend on this? |

Ordering is load-bearing rather than preference: "One core, three OSes" rewrites
~1,185 lines of tested shell, so doing it above a human-remembered gate would
change the safety net and the thing it protects in the same window. "Prove the
green" therefore comes first.

## Not working on

- **Not an application.** No build step, no package manager, no runtime of its own.
- **No private-marketplace artifact in the core.** What was cut, and why, is
  recorded in `EXCLUDED.md` rather than re-litigated.
- **Never commit an allowlist.** `settings.template.json` ships
  `permissions.allow: []` on purpose — this repo moves setups between laptops,
  which is precisely the leak vector.
- **No auto-repair, anywhere.** The size of a gap is the finding; a silent fix
  erases the evidence of how far a machine had drifted.
- **Not a published plugin — yet.** That decision gets earned with evidence from
  real adoption, not assumed.
- **No new hooks or skills** until the core is proven on every OS it claims.

## Invariants

Each already has a shipped bug behind it. That is why these are invariants and
not preferences.

| Invariant | Why it holds |
|---|---|
| A zero denominator is an abstention, not a pass | A gate that matched zero items didn't pass, it didn't run — extended now to CI itself, where a skipped matrix leg is not a green tick |
| Silence is earned by declaring a gap, never by omitting a key | An omitted key and a full watchlist look identical; a declared exemption is auditable |
| The core installs with no private dependency | Two `npm i -g` calls, no marketplace, no SSO — or the stranger's clone stops at a login wall |
| Overlays layer, never fork | The core stays unaware of overlays, so it cannot drift from them |
| A check reports, never repairs | The size of the gap is the finding; auto-repair destroys it |
| Every artifact states the incident that produced it | A rule without its reason gets dropped the first time it is inconvenient |

## Where to go next

| For | Read |
|---|---|
| What is left, and which issue tracks it | [`ROADMAP.md`](ROADMAP.md) |
| Why a decision went the way it did | `docs/knowledge/decisions/` |
| How to work in this repo | [`CLAUDE.md`](CLAUDE.md) |
| How to install it | [`INSTALL.md`](INSTALL.md) |
