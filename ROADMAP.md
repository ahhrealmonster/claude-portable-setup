# Roadmap

What is left, by item, with the exit criterion that closes it and the issue
that tracks it. The durable positions this serves live in
[`STRATEGY.md`](STRATEGY.md); the decisions behind the shape are in
[`docs/changes/roadmap-and-strategy/proposal.md`](docs/changes/roadmap-and-strategy/proposal.md).

**A row is "done" only when its issue is closed by a merged commit.** No commit,
no green status. A `✓` typed into this table is exactly the status claim the
repo refuses to make, so the table carries IDs and issue links and nothing
else — the state lives in the tracker, where a closed issue points at the
commit that closed it.

The M1 rows are closed by the PR that introduces this file (#16). Issue numbers
for M2–M4 are backfilled once the issues exist; until then the column reads `—`,
which means *untracked*, not *done*.

| ID | Item | Exit criterion | Issue |
|---|---|---|---|
| M1-1 | CI matrix, four gates, two OSes | SC-2 (two OSes) | #16 |
| M1-2 | `bare-install` job | SC-3, SC-4 | #16 |
| M1-3 | harness adopted; `.harness/` un-ignored | — | #16 |
| M1-4 | `STRATEGY.md` + `ROADMAP.md` | SC-1 | #16 |
| M1-5 | One tracked issue per remaining item | — | — |
| M2-1 | Build `tools/parity-check` **first**, against the bash baseline | SC-5 | — |
| M2-2 | Port three hooks + `check-drift` to pure Python, comments verbatim | — | — |
| M2-3 | `windows-latest` joins the matrix | SC-2 (three OSes) | — |
| M2-4 | Exec-bit check declares its NTFS skip | SC-6 | — |
| M3-1 | `global.md` rewritten to neutral voice | SC-7 | — |
| M3-2 | `profile.example.md` introduced | — | — |
| M3-3 | `EXCLUDED.md` re-scoped; rows 14–15 split | SC-9 | — |
| M3-4 | Company overlay contract, `INSTALL.md` step, third drift target | SC-8 | — |
| M4-1 | Reverse drift: `home/` ← `$HOME` | SC-10 | — |
| M4-2 | Versioned releases | — | — |
| M4-3 | Orphaned-process detection (scope TBD in M4) | — | — |
| M4-4 | Adoption document | — | — |
| M4-5 | Decide whether the siren graduates into a plugin | — | — |

## Tracked outside the milestones

Findings that are not roadmap items but must not be stepped over (rule 5):

| Issue | What |
|---|---|
| #17 | `required-review` runs floor-only without an `ANTHROPIC_API_KEY` secret; the check must say so rather than read as a full review |
| #18 | `required-review.yml` CLI pin vs the version the local watchlist tracks |

## Ordering

M1 before M2 is load-bearing, not preference: M2 rewrites ~1,185 lines of
tested shell, and doing that above a human-remembered gate would change the
safety net and the thing it protects in the same window. See
[`STRATEGY.md` § Tracks](STRATEGY.md#tracks).
