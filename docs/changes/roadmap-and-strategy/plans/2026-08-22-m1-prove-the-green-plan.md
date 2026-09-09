# Plan: M1 — Prove the green

**Date:** 2026-08-22
**Spec:** `docs/changes/roadmap-and-strategy/proposal.md` (§ Implementation order → M1)
**Branch:** `feat/m1-prove-the-green` (off `main` at `35f4b40`)
**Session:** `changes--roadmap-and-strategy--proposal`
**Rigor:** standard
**Tasks:** 19 · **Checkpoints:** 8 · **Time:** ~78 min
**Integration Tier:** large — new CI entry point, new repo-local tool, a reversed
recorded exclusion, a required branch-protection registration, and two root docs.

---

## Goal

The repo's own four gates run on every PR across `ubuntu-latest` and
`macos-latest` without a human remembering, a bare-`$HOME` job proves an
`INSTALL.md` install actually *happened* (exit 0, never the exit-2 abstention)
while naming what it did not verify, and the repo states in tracked files and
tracked issues what it is for and what is left to do.

---

## Observable Truths (Acceptance Criteria)

EARS-framed. Each is checkable by a command, not by judgment.

1. **SC-1** — `STRATEGY.md` and `ROADMAP.md` exist at repo root and
   `harness validate` exits without reporting a missing config.
   *Check:* `test -f STRATEGY.md && test -f ROADMAP.md && harness validate`
2. **SC-2 (M1 scope: two OSes)** — When a pull request is opened, CI shall run
   the four gates on `ubuntu-latest` and `macos-latest`, and the aggregate job
   shall fail if either leg reported anything other than `success` — including
   `skipped` and `cancelled`.
   *Check:* the PR's checks page shows `four gates (ubuntu-latest)`,
   `four gates (macos-latest)`, `bare install (…)` ×2, and `gates-complete`,
   all green; `gates-complete` prints the per-leg result it read.
3. **SC-3** — After carrying out `INSTALL.md` §§1–4 against a scratch `$HOME`,
   the bare-install job shall exit 0 from the drift check; an exit of 2 shall
   fail the job. Where neither `tools/check_drift.py` nor `tools/check-drift.sh`
   exists, the job shall fail rather than report a criterion it never ran.
   *Check:* `./tools/bare-install.sh; echo $?` → `0`; `./tests/test-bare-install.sh`
   pins the exit-2 rejection and the no-artifact case.
4. **SC-4** — The bare-install job shall print the `INSTALL.md` targets it did
   not verify (§5 `settings.json`, §6 `memory/` seeds) on both the pass and the
   fail path.
   *Check:* `./tests/test-bare-install.sh` asserts the disclosure string in both
   directions.
5. **Zero-denominator (repo thesis, extended to CI)** — If any gate matched zero
   files, then the leg shall not report success.
   *Check:* the `denominator` step counts hooks, tools and suites and exits 1 on
   any zero.
6. **Both-ways issue linkage** — Every remaining roadmap item in `ROADMAP.md`
   names a GitHub issue number, and every one of those issues links back to
   `ROADMAP.md` and to the spec.
   *Check:* `grep -c '#[0-9]' ROADMAP.md` equals the roadmap item count.
7. **No regression in the existing gates** — `bash -n`, `shellcheck`,
   `shellcheck -S warning`, both `json.tool` parses and `./tests/run-all.sh`
   stay clean, and `run-all.sh` reports **5** suites, not 4.

Baseline verified before planning: all four gates pass on this machine today
(`tests/run-all.sh` → `4 suite(s) run · every suite flew clean`), `/bin/bash` is
3.2.57 and every shipped script is already 3.2-clean, so the `macos-latest` leg
is expected to be honest rather than accidentally green.

---

## Uncertainties

- **[RESOLVED — decision needed, Task 4]** The spec never says where the
  bare-install logic lives. Inline YAML `run:` blocks are invisible to
  `shellcheck`, untestable locally, and unreachable by `run-all.sh` — the exact
  untested surface this repo refuses everywhere else. This plan assumes
  **`tools/bare-install.sh` + `tests/test-bare-install.sh`**. Flip at Task 4's
  decision checkpoint if you disagree; Tasks 4–9 change shape if you do.
- **[RESOLVED — decision needed, Task 3]** `EXCLUDED.md:14-15` will flatly
  contradict a committed `harness.config.json` the moment Task 1 merges. SC-9
  (M3) governs that rewrite, so M1 must either add a minimal pointer now or
  ship documented drift for the length of M2. Recommendation in Task 3.
- **[ASSUMPTION]** `shellcheck` is preinstalled on `ubuntu-latest` but **not**
  on `macos-latest`. The preflight step installs it via Homebrew there and fails
  the leg if it is still absent afterwards — so if the assumption is wrong in
  either direction, the job says so instead of silently dropping a gate.
- **[ASSUMPTION]** Un-ignoring `.harness/` newly tracks exactly five paths:
  `.harness/.gitignore` and four **zero-byte** `knowledge/extracted/*.jsonl`
  files (verified by simulating the un-ignore against a scratch `.gitignore`).
  `.harness/.gitignore` is tool-owned and regenerated, so what it keeps out
  today it may not keep out tomorrow. Task 2 carries the decision.
- **[ASSUMPTION]** Roadmap granularity is one issue per *item* (13 items:
  M2-1…M2-4, M3-1…M3-4, M4-1…M4-5), not one per milestone. Task 16's decision
  checkpoint confirms before any issue is created.
- **[DEFERRABLE]** Nothing lints the workflow YAML itself (`actionlint`). The
  first PR run is the only proof it parses. Not blocking; noted for M2.
- **[DEFERRABLE]** `harness validate` printed `x No harness.config.json found`
  and still **exited 0**. That is a false-green shape in the tooling, not in
  this repo. Filed as a concern, not fixed here.

---

## File Map

Every file this plan creates or modifies. Nothing outside this list.

```
CREATE  harness.config.json                                     (Task 1)
MODIFY  .gitignore                                              (Task 2)
CREATE  .harness/.gitignore                          [becomes tracked, Task 2]
CREATE  docs/knowledge/decisions/0001-public-cli-in-core-private-plugin-in-overlay.md
                                                                (Task 3)
MODIFY  EXCLUDED.md                          (rows 14–15 pointer only, Task 3)
CREATE  tests/test-bare-install.sh                        (Tasks 4, 6)
CREATE  tools/bare-install.sh                             (Tasks 5, 7)
CREATE  .github/workflows/ci.yml                        (Tasks 8, 9, 10)
CREATE  STRATEGY.md                                            (Task 11)
CREATE  ROADMAP.md                                       (Tasks 12, 17)
MODIFY  CLAUDE.md                                              (Task 13)
MODIFY  README.md                                              (Task 14)
```

Not touched, deliberately: `home/settings.template.json` (ships
`permissions.allow: []` on purpose — never commit an allowlist),
`home/ai-rules/global.md` and `home/CLAUDE.md` (M3 owns the voice rewrite),
`tools/check-drift.sh` and the four existing suites (M2 owns the port).

---

## Skeleton

_Produced per standard rigor (19 tasks ≥ 8). **Approval pending** — see the
sign-off ask accompanying this plan._

1. Harness adoption and the exclusion it reverses (~3 tasks, ~12 min)
2. Bare-install checker, TDD (~4 tasks, ~18 min)
3. CI workflow: gates matrix, bare-install job, honest aggregate (~3 tasks, ~14 min)
4. STRATEGY.md and ROADMAP.md (~2 tasks, ~10 min)
5. Doc-drift repair in CLAUDE.md and README.md (~2 tasks, ~8 min)
6. Prove it on a real PR; issues; branch protection; final sweep (~5 tasks, ~16 min)

**Estimated total:** 19 tasks, ~78 minutes.

---

## Tasks

Wave-DAG inputs: every task declares `id`, `files`, `dependsOn`, and `owns`
where it is the sole writer of a file. Tasks with disjoint `owns` sets and no
`dependsOn` edge between them may run in the same wave.

---

### Task 1: `harness init`, review the generated config, commit it

**id:** `t1-harness-init` | **dependsOn:** none
**files:** `harness.config.json`
**owns:** `harness.config.json`
**[checkpoint:human-verify]**

`harness validate` and `harness check-deps` both currently print
`x No harness.config.json found` — so SC-1's "parses under `harness validate`"
cannot be met until this exists. The config is generated by a tool whose plugin
layer is private (spec D6); this repo is public and its whole thesis about
allowlists is that config files accumulate payload data nobody audits. So the
generated file is **read before it is committed**, not after.

1. Run: `harness init`
2. Print it: `cat harness.config.json`
3. **[checkpoint:human-verify]** Show the file to the human and confirm, line by
   line, that it contains: no absolute machine paths (the memory index records
   that harness commands embed an absolute mise/node path — that pattern must
   not reach a public bundle), no employer/client/marketplace names, no tokens,
   no `permissions`-shaped data. If any appears, stop and ask before editing it
   out — a hand-edited generated file is its own drift risk.
4. Confirm it parses: `python3 -m json.tool harness.config.json > /dev/null`
5. Confirm the tool is satisfied: `harness validate` — must no longer print
   `No harness.config.json found`.
6. Run: `harness check-deps`
7. Commit: `chore(harness): adopt the public harness CLI with a committed config`

---

### Task 2: Un-ignore `.harness/`, amending the reasoning rather than deleting it

**id:** `t2-unignore-harness` | **dependsOn:** `t1-harness-init`
**files:** `.gitignore`, `.harness/.gitignore`
**owns:** `.gitignore`
**Category:** integration
**[checkpoint:decision]**

`.gitignore` lines 1–11 are a comment block giving two reasons for ignoring
`.harness/`: (a) it sat permanently untracked and made `git status` noisy, and
(b) it is "private-org tooling (see EXCLUDED.md)". Reason (b) is what spec D6
overturns — the CLI was public the whole time. Reason (a) is still true and is
what `.harness/.gitignore` handles. **Do not delete the block**; the repo's own
rule is that a rule without its reason gets dropped the first time it is
inconvenient, and issue #6 already closed once on the strength of this text.

1. Read the current block: `sed -n '1,12p' .gitignore`
2. **[checkpoint:decision]** Un-ignoring newly tracks five paths:
   `.harness/.gitignore` plus four **zero-byte** files under
   `.harness/knowledge/extracted/`. Choose:

   |            | A) Track all five                                                      | B) Track `.harness/.gitignore`, ignore `knowledge/extracted/` at repo root |
   | ---------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------- |
   | **Pros**   | Nothing hidden; the tool's own ignore file is the single source         | Zero-byte generated artifacts stay out of history; root ignore is ours      |
   | **Cons**   | Commits four empty generated files that will churn                     | A second place governs `.harness/` contents                                 |
   | **Risk**   | Low (files are empty today — but they are extraction *output*)         | Low                                                                         |
   | **Effort** | Low                                                                     | Low                                                                         |

   **Recommendation:** B (confidence: medium) — `.harness/.gitignore` is
   tool-owned and regenerated, so leaning on it alone to keep extraction output
   out of a public repo is a dependency on a file the tool may rewrite.

3. Replace the `.harness/` line with the amendment, keeping the original prose
   above it. Exact replacement for the last lines of that block:

   ```gitignore
   # (.remember/ needs no entry — it self-ignores with a `*` in its own .gitignore.)
   #
   # AMENDED 2026-08-22 (spec D6, ADR-0001): the second reason above was
   # factually wrong. `@harness-engineering/cli` resolves from npm without auth;
   # only the ~50-command plugin layer is private-marketplace, and that stays in
   # the company overlay. So the directory is no longer ignored wholesale — its
   # own tool-owned .gitignore keeps the runtime artifacts out, which is what
   # reason (a) about `git status` noise actually needed. The public/private
   # split is recorded in docs/knowledge/decisions/0001-*.md rather than being
   # re-litigated here; EXCLUDED.md rows 14-15 split in M3 (SC-9).
   .harness/knowledge/extracted/
   ```

   (Under decision A, drop the final `.harness/knowledge/extracted/` line.)
4. Verify exactly what became tracked — the denominator matters here:
   `git status --porcelain .harness` (expect `?? .harness/.gitignore`, and
   under A also the four `extracted/*.jsonl`).
5. Verify nothing sensitive is inside: `git add -n .harness` then inspect
   each named path.
6. Run: `harness validate`
7. Commit: `chore(harness): un-ignore .harness/, amending the reason it was ignored`

---

### Task 3: ADR-0001 for D6, and a pointer from the rows it contradicts

**id:** `t3-adr-d6` | **dependsOn:** `t2-unignore-harness`
**files:** `docs/knowledge/decisions/0001-public-cli-in-core-private-plugin-in-overlay.md`, `EXCLUDED.md`
**owns:** `docs/knowledge/decisions/0001-public-cli-in-core-private-plugin-in-overlay.md`
**Category:** integration
**[checkpoint:decision]**

The spec lists D6 as warranting a standalone ADR precisely because it reverses a
recorded exclusion that `CLAUDE.md` protects from re-litigation. Tasks 1 and 2
perform the reversal; without the ADR the next reader restores the old rule.

1. Create `docs/knowledge/decisions/0001-public-cli-in-core-private-plugin-in-overlay.md`
   containing, at minimum:
   - **Status:** accepted, 2026-08-22. **Supersedes in part:** `EXCLUDED.md` rows
     14–15. **Spec:** `docs/changes/roadmap-and-strategy/proposal.md` § D6.
   - **Context:** `EXCLUDED.md:14-15` cut harness and canary as
     private-marketplace tooling and `.gitignore` cited the same reason for
     `.harness/`. Checked against npm: `@harness-engineering/cli@11.3.0` and
     `canary-test-cli@7.0.0` both resolve without auth. The exclusion was
     correct about the plugin layer and wrong about the CLI.
   - **Decision:** public CLIs are committed dev tooling in the core; the
     private plugin layer is the first tenant of the company overlay. Rows 14–15
     are split, not deleted; every other `EXCLUDED.md` row stays byte-identical
     (SC-9).
   - **Consequences:** `harness.config.json` is committed; `.harness/` is no
     longer ignored wholesale; a stranger installing the core needs
     `npm i -g` and no marketplace or SSO (SC-8 proves it).
   - **Why this is not re-litigation:** the cut was based on a factual claim
     that was checked and found wrong — the same shape as this repo's own
     retired `npm_exempt` entry, "uninvestigated coverage debt wearing a
     declared-gap label".
2. **[checkpoint:decision]** `EXCLUDED.md` rows 14–15 now contradict a committed
   config on `main` for the length of M2. Choose:

   |            | A) Add a one-line "superseded in part — see ADR-0001" to rows 14–15 now | B) Leave `EXCLUDED.md` untouched until M3 (SC-9)                |
   | ---------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------- |
   | **Pros**   | No merged doc states something the repo contradicts                      | SC-9 owns the file; one edit, one milestone; zero churn           |
   | **Cons**   | Touches a file M3's SC-9 governs (rows 14–15 are the only movable ones)  | A merged, authoritative doc is wrong for weeks — the exact "stale file reads as current" failure this repo has already had once |
   | **Risk**   | Low — SC-9 already permits rows 14–15 to change                          | Medium                                                            |
   | **Effort** | Low                                                                       | None                                                              |

   **Recommendation:** A (confidence: high) — the pointer is inside the only two
   rows SC-9 allows to move, and the repo's own history is the argument against B.

3. Under A: append to the two affected `EXCLUDED.md` cells (harness commands
   row, canary plugin row) the sentence
   `Superseded in part — the CLI is public; see docs/knowledge/decisions/0001-*.md. Rows split in M3 (SC-9).`
   Change **nothing else** in the file.
4. Verify the rest is byte-identical: `git diff EXCLUDED.md` — expect exactly
   two changed lines.
5. Run: `harness validate`
6. Commit: `docs(decisions): record ADR-0001, public CLI in core / private plugin in overlay`

---

### Task 4: RED — `tests/test-bare-install.sh`, the exit-0-not-2 contract

**id:** `t4-bare-install-red-core` | **dependsOn:** none
**files:** `tests/test-bare-install.sh`
**owns:** `tests/test-bare-install.sh`
**[checkpoint:decision]** (once, before writing — governs Tasks 4–10)

**Decision first.** Where does bare-install logic live?

|            | A) `tools/bare-install.sh` + `tests/test-bare-install.sh`                                  | B) Inline `run:` block in `.github/workflows/ci.yml`      |
| ---------- | -------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| **Pros**   | Runnable locally; covered by `shellcheck`; auto-joins `run-all.sh`'s `test-*.sh` glob; SC-3/SC-4 become *pinned invariants* like every other one in this repo | Nothing new to maintain; fewer files                        |
| **Cons**   | Two new files; the four gates' denominators change                                            | Unlintable, untestable, unrunnable off a runner — the one untested surface in a repo whose thesis is untested surfaces |
| **Risk**   | Low                                                                                            | High — SC-4's "on both paths" is exactly the invariant that shipped as a bug in `check-drift.sh` and needed a test to hold |
| **Effort** | Medium                                                                                         | Low                                                          |

**Recommendation:** A (confidence: high).

Then, following `tests/test-drift.sh` conventions verbatim — `set -u`, `BUNDLE`
derived from `$0`, `ok`/`bad`/`assert_has`/`assert_not`/`assert_rc` helpers, a
themed banner, a tally that exits non-zero — write the file header explaining
*why* (SC-3: an exit of 2 is check-drift's "nothing was installed here"
abstention, so a job that accepted 2 would prove nothing at all), then these
cases:

1. **Fresh scratch root → exit 0.** `assert_rc 0` on
   `bash "$BUNDLE/tools/bare-install.sh"`.
2. **It names its own denominator.** `assert_has "check(s)"` and
   `assert_not "0 check(s)"` in the output.
3. **Exit 2 is a failure, not a pass.** Build a *fake bundle* (`cp -R` the real
   one into `$TMP/fakebundle`), replace `tools/check-drift.sh` with a stub that
   prints nothing and `exit 2`, run `$TMP/fakebundle/tools/bare-install.sh`,
   `assert_rc 1`, and `assert_has "abstention"` — the failure must *say* which
   failure it was, not just be red.
   (The fake-bundle fixture avoids adding a test-only seam to the production
   script; `BUNDLE` derives from `dirname "$0"`, so pointing at a copy is enough.)
4. **It leaves no scratch state behind** — the temp root is removed on the
   success path.

Then:

5. Run: `chmod +x tests/test-bare-install.sh && ./tests/test-bare-install.sh`
   — **observe it fail**, naming `tools/bare-install.sh` as absent. A suite that
   passes before the implementation exists is testing nothing.
6. Run: `shellcheck -S warning tests/test-bare-install.sh`
7. Run: `harness validate`
8. Commit: `test(bare-install): pin the exit-0-not-2 contract before the tool exists`

---

### Task 5: GREEN — `tools/bare-install.sh` carries out INSTALL.md §§1–4

**id:** `t5-bare-install-green-core` | **dependsOn:** `t4-bare-install-red-core`
**files:** `tools/bare-install.sh`
**owns:** `tools/bare-install.sh`

Header comment must state the incident/reason, per house style: *this is SC-3;
`check-drift.sh` reserves exit 2 for "nothing of this bundle is installed here",
and a CI job that treated 2 as green would report an install it never performed.*

1. Create `tools/bare-install.sh`, `#!/bin/bash`, `set -u`, with:
   - `BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"`
   - `ROOT="${1:-$(mktemp -d)}"`, `OWNED_TMP` flag, cleanup trap that removes
     the root only when this script created it.
   - The install, mirroring `INSTALL.md` §§1–4 (a scratch `$HOME` is empty, so
     §1's "never overwrite without asking" cannot trigger):

     ```bash
     mkdir -p "$ROOT/.config/ai-rules" "$ROOT/.claude/hooks" "$ROOT/.claude/skills"
     cp "$BUNDLE/home/CLAUDE.md"          "$ROOT/.claude/CLAUDE.md"          # §1
     cp "$BUNDLE/home/ai-rules/global.md" "$ROOT/.config/ai-rules/global.md" # §1
     cp -R "$BUNDLE/home/skills/visual-decisions" "$ROOT/.claude/skills/"    # §2
     # Glob, not a hardcoded list: check-drift compares the hooks directory in
     # BOTH directions, so a file added to home/hooks/ and missed here would
     # surface as "missing" rather than passing quietly. The glob keeps this
     # script from becoming a second file list that can go stale (§3, §4).
     cp "$BUNDLE"/home/hooks/*            "$ROOT/.claude/hooks/"
     chmod +x "$ROOT"/.claude/hooks/*.sh
     ```

   - Deliberately **not** installed: `settings.json` (§5) and `memory/` seeds
     (§6). That omission is what Task 7 has to disclose.
   - Run the drift check with `CHECK_ROOT="$ROOT"`, capture output and `rc`,
     echo the output, then:

     ```bash
     case "$rc" in
       0) printf '⌂ bare install verified — drift check exited 0\n' ;;
       2) printf '✘ ABSTENTION (exit 2): nothing of the bundle was found under %s,\n' "$ROOT"
          printf '  so nothing was compared. SC-3 requires exit 0; an exit of 2 proves nothing.\n'
          STATUS=1 ;;
       *) printf '✘ drift check exited %s\n' "$rc"; STATUS=1 ;;
     esac
     ```

   (Hardcode `bash "$BUNDLE/tools/check-drift.sh"` for now — Task 7 replaces it
   with the resolver. Do not write Task 7's code here; the RED suite for it does
   not exist yet.)
2. Run: `chmod +x tools/bare-install.sh && ./tests/test-bare-install.sh`
   — **observe all four cases pass**.
3. Run: `shellcheck tools/bare-install.sh` (default severity — hooks and tools
   must be clean at default; only suites are gated at `-S warning`).
4. Run: `bash -n home/hooks/*.sh tools/*.sh tests/*.sh`
5. Run: `./tests/run-all.sh` — must now report **5** suites, all clean.
6. Run: `harness validate`
7. Commit: `feat(ci): prove a bare INSTALL.md install landed, exit 0 not 2`

---

### Task 6: RED — SC-4 disclosure on both paths, and the M2-rename survival case

**id:** `t6-bare-install-red-disclosure` | **dependsOn:** `t5-bare-install-green-core`
**files:** `tests/test-bare-install.sh`

Same file as Task 4, so this is sequential rather than parallel. These are the
two cases the spec singles out, and both are load-bearing.

1. Append to `tests/test-bare-install.sh`:
   - **Case 5 — uncovered targets named on the PASS path.**
     `assert_has "not verified"` (and `assert_has "settings.json"`,
     `assert_has "memory/"`) in the output of a successful run.
   - **Case 6 — and on the FAIL path.** Using the exit-2 fake bundle from
     case 3, `assert_has "not verified"` again. Comment the why verbatim from
     the repo's existing reasoning: disclosing only on green implies a red run's
     findings were exhaustive.
   - **Case 7 — `check_drift.py` is preferred when present.** Fake bundle
     containing *both* a `tools/check_drift.py` stub (prints a marker, exit 0)
     and the real `tools/check-drift.sh`; assert the marker appears. This is
     what makes SC-3 survive the M2 rename instead of silently going unrun.
   - **Case 8 — `check-drift.sh` is used when only it exists.** Fake bundle with
     the `.py` removed; assert exit 0 and no marker.
   - **Case 9 — neither artifact exists → hard failure.** Fake bundle with both
     removed; `assert_rc 1` and `assert_has "no drift artifact"`. A missing
     checker must fail loudly; a criterion that cannot run is not a criterion
     that passed.
   - **Case 10 — the disclosure survives case 9 too.** `assert_has "not verified"`.
2. Run: `./tests/test-bare-install.sh` — **observe cases 5–10 fail** (the
   disclosure and the resolver do not exist yet).
3. Run: `shellcheck -S warning tests/test-bare-install.sh`
4. Run: `harness validate`
5. Commit: `test(bare-install): pin SC-4 disclosure on both paths and the drift-artifact resolver`

---

### Task 7: GREEN — disclosure on both paths, and the drift-artifact resolver

**id:** `t7-bare-install-green-disclosure` | **dependsOn:** `t6-bare-install-red-disclosure`
**files:** `tools/bare-install.sh`

1. Add `print_uncovered()` to `tools/bare-install.sh`, called on **every**
   non-early-exit path — mirroring `check-drift.sh`'s own `print_uncovered`:

   ```bash
   # This job installs INSTALL.md §§1-4 and verifies §§1-4. It does not touch
   # §5 (settings.json is a merge target, not a copy target) or §6 (memory
   # seeds accumulate). Naming them on the fail path too is the point: printing
   # the caveat only on green would imply a red run's findings were exhaustive.
   print_uncovered() {
     printf '  not verified: settings.json (INSTALL.md §5), memory/ seeds (§6)\n'
     printf '  — this job proves 4 of the 6 things INSTALL.md deploys\n'
   }
   ```

2. Replace the hardcoded drift invocation with the resolver:

   ```bash
   # SC-3 must survive M2's bash-to-Python rename. A job hardcoding the old
   # filename would find nothing after the rename and — depending on how it was
   # written — either fail confusingly or skip the criterion silently. Prefer
   # the Python artifact once it exists; fail hard when neither does.
   if   [ -f "$BUNDLE/tools/check_drift.py"  ]; then DRIFT=(python3 "$BUNDLE/tools/check_drift.py")
   elif [ -f "$BUNDLE/tools/check-drift.sh"  ]; then DRIFT=(bash    "$BUNDLE/tools/check-drift.sh")
   else
     printf '✘ no drift artifact — neither tools/check_drift.py nor tools/check-drift.sh\n'
     printf '  exists, so SC-3 did not run. That is an abstention, not a pass.\n'
     print_uncovered
     exit 1
   fi
   ```

3. Run: `./tests/test-bare-install.sh` — **observe all ten cases pass**.
4. Run: `shellcheck tools/bare-install.sh`
5. Run: `./tests/run-all.sh`
6. Run: `harness validate`
7. Commit: `feat(ci): disclose unverified INSTALL.md targets on both paths, resolve the drift artifact`

---

### Task 8: CI workflow — the four-gates matrix, with a denominator step

**id:** `t8-ci-gates` | **dependsOn:** `t1-harness-init`
**files:** `.github/workflows/ci.yml`
**owns:** `.github/workflows/ci.yml`
**Category:** integration

The repo has no CI today. Gate commands are copied verbatim from `CLAUDE.md`'s
"Commands" section — this workflow must not invent a different set.

1. Create `.github/workflows/ci.yml`:

   ```yaml
   # The repo's four gates, run by something other than a human's memory.
   #
   # Its thesis is that a gate nobody ran is not a pass, so this workflow is
   # written against its own failure mode: a leg that never ran, a glob that
   # matched nothing, a missing shellcheck quietly reducing four gates to three.
   name: gates

   on:
     pull_request:
     push:
       branches: [main]

   permissions:
     contents: read

   jobs:
     gates:
       name: four gates (${{ matrix.os }})
       strategy:
         fail-fast: false   # a cancelled sibling must not hide a leg's result
         matrix:
           os: [ubuntu-latest, macos-latest]   # windows-latest joins in M2
       runs-on: ${{ matrix.os }}
       steps:
         - uses: actions/checkout@v4

         - name: preflight — cannot verify is a finding, not a skip
           run: |
             set -eu
             if ! command -v shellcheck >/dev/null 2>&1; then
               if [ "$RUNNER_OS" = "macOS" ]; then brew install shellcheck; fi
             fi
             command -v shellcheck >/dev/null || {
               echo "::error::shellcheck absent on $RUNNER_OS — the lint gate cannot run"; exit 1; }
             command -v python3 >/dev/null || {
               echo "::error::python3 absent — the JSON gate cannot run"; exit 1; }
             shellcheck --version; python3 --version; bash --version | head -1

         - name: denominator — every gate must have something to check
           run: |
             set -eu
             h=$(ls home/hooks/*.sh   2>/dev/null | wc -l | tr -d ' ')
             t=$(ls tools/*.sh        2>/dev/null | wc -l | tr -d ' ')
             s=$(ls tests/test-*.sh   2>/dev/null | wc -l | tr -d ' ')
             echo "hooks=$h tools=$t suites=$s"
             for n in "$h" "$t" "$s"; do
               [ "$n" -gt 0 ] || { echo "::error::a gate matched zero files — abstention, not a pass"; exit 1; }
             done

         - name: gate 1 — syntax
           run: bash -n home/hooks/*.sh tools/*.sh tests/*.sh

         - name: gate 2 — shellcheck, default severity
           run: shellcheck home/hooks/*.sh tools/*.sh

         - name: gate 2b — suites at -S warning (known SC2015 infos)
           run: shellcheck -S warning tests/*.sh

         - name: gate 3 — JSON parses
           run: |
             set -eu
             python3 -m json.tool home/settings.template.json      > /dev/null
             python3 -m json.tool home/hooks/rot-watch.example.json > /dev/null
             python3 -m json.tool harness.config.json               > /dev/null

         - name: gate 4 — tests
           run: ./tests/run-all.sh
   ```

2. Verify the YAML parses locally without adding a dependency:
   `python3 -c "import sys,json;print('yaml not in stdlib — parse check deferred to the PR run')"`
   — i.e. accept the deferral explicitly rather than pretending it was checked.
   (Recorded as a deferrable uncertainty above.)
3. Run: `harness validate`
4. Commit: `ci(gates): run the four gates on ubuntu and macos`

---

### Task 9: CI workflow — the `bare_install` job

**id:** `t9-ci-bare-install` | **dependsOn:** `t8-ci-gates`, `t7-bare-install-green-disclosure`
**files:** `.github/workflows/ci.yml`
**Category:** integration

1. Append to `jobs:` in `.github/workflows/ci.yml`:

   ```yaml
     # Job id is bare_install, NOT bare-install. GitHub expression syntax reads
     # `needs.bare-install.result` as a subtraction, so a hyphen here makes the
     # aggregate job below silently evaluate the wrong thing — a false green in
     # the very job that exists to prevent false greens.
     bare_install:
       name: bare install (${{ matrix.os }})
       strategy:
         fail-fast: false
         matrix:
           os: [ubuntu-latest, macos-latest]
       runs-on: ${{ matrix.os }}
       steps:
         - uses: actions/checkout@v4
         - name: carry out INSTALL.md into a scratch HOME and prove it landed
           # SC-3: exit 0, never the exit-2 abstention.
           # SC-4: the script names what it did not verify, pass or fail.
           run: ./tools/bare-install.sh
   ```

2. Run: `./tools/bare-install.sh; echo "exit=$?"` locally — expect `exit=0` and
   the `not verified:` disclosure in the output.
3. Run: `harness validate`
4. Commit: `ci(bare-install): prove an INSTALL.md install lands on a bare HOME`

---

### Task 10: CI workflow — `gates-complete`, where a skipped leg is not a pass

**id:** `t10-ci-aggregate` | **dependsOn:** `t9-ci-bare-install`
**files:** `.github/workflows/ci.yml`
**Category:** integration

This is the job branch protection will require (Task 18). It exists because a
required check that never ran shows as neutral, and a matrix that expands to
zero legs reports `skipped` — both of which read as "not red" to a human
glancing at a PR.

1. Append to `jobs:`:

   ```yaml
     gates-complete:
       name: gates-complete
       # always() so a skipped or cancelled dependency still reaches this job.
       # Without it, this job would itself be skipped — and a skipped required
       # check is exactly the abstention-wearing-a-pass shape it exists to catch.
       if: always()
       needs: [gates, bare_install]
       runs-on: ubuntu-latest
       steps:
         - name: a skipped leg is not a pass
           env:
             GATES: ${{ needs.gates.result }}
             BARE:  ${{ needs.bare_install.result }}
           run: |
             set -u
             rc=0
             for pair in "gates:$GATES" "bare_install:$BARE"; do
               name=${pair%%:*}; res=${pair#*:}
               case "$res" in
                 success) printf '  ok       %s\n' "$name" ;;
                 skipped) printf '::error::%s was SKIPPED — zero legs ran. Abstention, not a pass.\n' "$name"; rc=1 ;;
                 '')      printf '::error::%s reported no result at all.\n' "$name"; rc=1 ;;
                 *)       printf '::error::%s reported %s.\n' "$name" "$res"; rc=1 ;;
               esac
             done
             printf '  matrix legs required: ubuntu-latest, macos-latest (windows-latest lands in M2)\n'
             exit "$rc"
   ```

2. Run: `harness validate`
3. Commit: `ci(gates-complete): fail the aggregate when any leg did not actually run`

---

### Task 11: `STRATEGY.md` at repo root

**id:** `t11-strategy` | **dependsOn:** none
**files:** `STRATEGY.md`
**owns:** `STRATEGY.md`
**Category:** integration

Durable content only — anything that churns belongs in `ROADMAP.md` (spec D4).
Source everything from the spec; do not invent new positions.

1. Create `STRATEGY.md` with:
   - **What this is** — a public reference implementation of an agent working
     setup (D1). Success test: *a stranger clones it and it works on their machine.*
   - **Who it serves** — the stranger first; the author and a company via
     overlays, never a fork.
   - **What it refuses to do** — the spec's Non-goals verbatim in substance: not
     an application, no private-marketplace artifact in the core, never commit
     an allowlist, no auto-repair, not a published plugin yet.
   - **The core-plus-overlay diagram**, copied from the spec's Technical design,
     with the precedence rule `machine > company > profile > core` and the
     layer contracts.
   - **The invariants table** from the spec, each with its one-line reason.
   - **Pointers:** `ROADMAP.md` for what is left, `docs/knowledge/decisions/`
     for the ADRs, `CLAUDE.md` for how to work in the repo.
2. Run: `harness validate`
3. Commit: `docs(strategy): state what the repo is, who it serves, what it refuses`

---

### Task 12: `ROADMAP.md` at repo root, with item IDs and an empty issue column

**id:** `t12-roadmap` | **dependsOn:** `t11-strategy`
**files:** `ROADMAP.md`
**owns:** `ROADMAP.md`
**Category:** integration

Issue numbers do not exist yet, so the column ships as `—` and Task 17 backfills
it. Writing `M1 done ✓` with no backing issue is the status claim D4 rejects.

1. Create `ROADMAP.md` with one row per item, IDs matching the spec's own
   (`M4-1`…`M4-5` are the spec's; `M2-*` and `M3-*` are assigned here to the
   spec's bullets one-for-one):

   | ID | Item | Exit criterion | Issue |
   |---|---|---|---|
   | M1-1 | CI matrix, four gates, two OSes | SC-2 (two OSes) | — |
   | M1-2 | `bare-install` job | SC-3, SC-4 | — |
   | M1-3 | harness adopted; `.harness/` un-ignored | — | — |
   | M1-4 | `STRATEGY.md` + `ROADMAP.md` | SC-1 | — |
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

   Plus: a header noting M1 rows are closed by this branch's PR, and a line
   stating that a row is only "done" when its issue is closed by a merged
   commit (rule: no commit, no green status).
2. Verify the item count: `grep -c '^| M[0-9]' ROADMAP.md` → 18.
3. Run: `harness validate`
4. Commit: `docs(roadmap): enumerate every remaining item with an ID and exit criterion`

---

### Task 13: `CLAUDE.md` — repair the doc drift this branch creates

**id:** `t13-claude-md` | **dependsOn:** `t7-bare-install-green-disclosure`, `t10-ci-aggregate`, `t12-roadmap`
**files:** `CLAUDE.md`
**owns:** `CLAUDE.md`
**Category:** integration

`CLAUDE.md` is the canonical knowledge map and it currently says things this
branch makes false. Rule 8 (doc-drift check) applies before the PR, not after.

1. In the **Commands** block: `./tests/run-all.sh # every suite (99 cases across
   4)` → the real numbers. Get them from the actual run:
   `./tests/run-all.sh 2>&1 | tail -5` and the per-suite tallies. Add
   `./tests/test-bare-install.sh` to the per-suite list.
2. In the **four gates** block: add the note that these now also run in CI on
   `ubuntu-latest` and `macos-latest` via `.github/workflows/ci.yml`, and that
   `gates-complete` is the required check — a workflow without branch
   protection is decorative.
3. Add `harness.config.json` to the gate-3 JSON parse list shown in that block,
   matching the workflow.
4. Add a subsection after "Deploy drift" describing `tools/bare-install.sh`:
   what it proves (SC-3), why exit 2 fails it, and what it explicitly does not
   verify (SC-4).
5. Add two rows to **Load-bearing invariants**:
   - `bare-install treats exit 2 as failure` | `tools/bare-install.sh` | exit 2
     is check-drift's "nothing was installed here" abstention; a job accepting
     it would report an install it never performed.
   - `The aggregate job fails on skipped, not only on failure` |
     `.github/workflows/ci.yml` | a required check that never ran reads as
     not-red; the job id must stay `bare_install` because
     `needs.bare-install.result` parses as subtraction.
6. Add a line to the top pointing at `STRATEGY.md` and `ROADMAP.md`.
7. Run: `harness validate`
8. Commit: `docs(claude): record the CI gates, the bare-install proof, and its invariants`

---

### Task 14: `README.md` — the "What's in it" table and the two new root docs

**id:** `t14-readme` | **dependsOn:** `t12-roadmap`, `t10-ci-aggregate`
**files:** `README.md`
**owns:** `README.md`
**Category:** integration

1. Add rows to the "What's in it" table (`Goes to` column = `—` for both):
   - `tools/bare-install.sh` — carries out `INSTALL.md` §§1–4 into a scratch
     `$HOME` and proves the install landed: exit 0, never the exit-2
     abstention. Names the two targets it does not verify, pass or fail.
   - `.github/workflows/ci.yml` — the four gates on `ubuntu-latest` and
     `macos-latest`, plus an aggregate job that fails when a leg was skipped
     rather than run.
2. Update the `tests/` row: 5 suites, real case count.
3. Add a short "Where it's going" paragraph linking `STRATEGY.md` and
   `ROADMAP.md`.
4. Run: `harness validate`
5. Commit: `docs(readme): list the CI workflow, the bare-install proof, and the new root docs`

---

### Task 15: Push the branch, open the PR, and check the denominator on the green

**id:** `t15-open-pr` | **dependsOn:** `t13-claude-md`, `t14-readme`, `t3-adr-d6`, `t2-unignore-harness`
**files:** none
**[checkpoint:human-action]**

The workflow has never executed. Until it does, SC-2 is a claim about a YAML
file. This is also the first moment `actionlint`'s absence could bite.

1. Run the four gates locally on the *final* state, not a pre-fix run:
   ```
   bash -n home/hooks/*.sh tools/*.sh tests/*.sh
   shellcheck home/hooks/*.sh tools/*.sh
   shellcheck -S warning tests/*.sh
   python3 -m json.tool home/settings.template.json      > /dev/null
   python3 -m json.tool home/hooks/rot-watch.example.json > /dev/null
   python3 -m json.tool harness.config.json               > /dev/null
   ./tests/run-all.sh
   ```
2. **[checkpoint:human-action]** Ask the human to authorize the push (nothing in
   this plan pushes without it). Then:
   `git push -u origin feat/m1-prove-the-green`
3. Open the PR: `gh pr create --fill --base main` with a body that lists SC-1
   through SC-4 and how each is checked, and links the spec and this plan.
4. **[checkpoint:human-verify]** Watch the run and confirm the *denominator*,
   not just the colour: `gh pr checks --watch`. Confirm all five checks appear
   — `four gates (ubuntu-latest)`, `four gates (macos-latest)`,
   `bare install (ubuntu-latest)`, `bare install (macos-latest)`,
   `gates-complete` — and that none is `skipped` or `neutral`. Then read the
   logs and confirm: the `denominator` step printed non-zero counts on both
   legs; the bare-install job printed `not verified:`; `gates-complete` printed
   `ok gates` and `ok bare_install`.
5. If a leg fails, fix and re-run — do not narrow "passing" to the legs that
   went green (rule 5).

---

### Task 16: Open one tracked issue per remaining roadmap item

**id:** `t16-issues` | **dependsOn:** `t12-roadmap`, `t15-open-pr`
**files:** none
**[checkpoint:decision]** **[checkpoint:human-action]**

This creates real, public, permanent artifacts in
`ahhrealmonster/claude-portable-setup`. It is never a silent automated step.

1. **[checkpoint:decision]** Confirm granularity before creating anything:

   |            | A) 13 item-level issues (M2-1…M4-5)                        | B) 3 milestone issues with checklists           | C) 13 issues grouped by 3 GitHub Milestones            |
   | ---------- | ------------------------------------------------------------ | ------------------------------------------------- | -------------------------------------------------------- |
   | **Pros**   | Matches the spec's wording ("one per remaining roadmap item") | Three issues to track                             | Item-level tracking plus milestone rollup and progress % |
   | **Cons**   | 13 issues on a small repo                                     | A checklist item is not a closeable, linkable unit | Slight extra setup                                        |
   | **Risk**   | Low                                                            | Medium — reintroduces "done ✓ in a markdown file"  | Low                                                       |
   | **Effort** | Medium                                                         | Low                                                | Medium                                                    |

   **Recommendation:** C (confidence: medium) — item-level closes are what make
   a ROADMAP row's "done" reachable from a commit, and milestones give the
   rollup B was after.

2. **[checkpoint:human-action]** Get an explicit yes before the first
   `gh issue create`. Then, under C:
   `gh api repos/ahhrealmonster/claude-portable-setup/milestones -f title='M2 — One core, three OSes'` (and M3, M4).
3. For each of the 13 items, create the issue with a body that links **both
   ways**: the roadmap row ID, `ROADMAP.md`, the spec section, and the exit
   criterion. Example for M2-1:
   ```
   gh issue create \
     --title "M2-1 — Build tools/parity-check before the Python port begins" \
     --milestone "M2 — One core, three OSes" \
     --label enhancement \
     --body "Roadmap item **M2-1** (see \`ROADMAP.md\`).

   Spec: \`docs/changes/roadmap-and-strategy/proposal.md\` § Implementation order → M2.
   Exit criterion: **SC-5** — zero unexplained divergence between the bash
   baseline and the Python candidate for every ported artifact, running in CI on
   all three OSes with no private dependency, and **failing when zero artifacts
   were compared** (an empty comparison is an abstention, not parity).

   Ordering constraint: this must land *before* any hook is ported — parity is
   proven against the bash baseline while it is still the only implementation."
   ```
4. **Carried in from t1 (added 2026-08-23):** open one further issue, outside the
   13 roadmap items and outside any milestone, for an unreconciled denominator
   found while adopting the CLI. `harness check-deps` reports
   `Analyzed 13 module(s) across 3 layer(s)` against **10** real files in
   `home/hooks/`, `tools/`, and `tests/` — the `--json` output exposes only
   `modulesAnalyzed`, never the list, so the extra three cannot be identified
   from outside the tool. It over-counts rather than under-counts, so it is not
   a false green and did not block t1; but a gate whose denominator cannot be
   reconciled is exactly what this repo refuses to wave through, and an
   unexplained count is a finding under the "cannot verify is a finding" rule.
   Title it so the count is in the title, and note that a *later* drop below 10
   would be the dangerous direction.
5. Record the created numbers: `gh issue list --limit 30 --state open`
6. No commit — this task produces no files.

---

### Task 17: Backfill the issue numbers into `ROADMAP.md`

**id:** `t17-roadmap-backfill` | **dependsOn:** `t16-issues`
**files:** `ROADMAP.md`
**[checkpoint:human-verify]**

1. Replace each `—` in the Issue column with `#N` for the matching item.
2. Verify the linkage count both ways:
   - `grep -c '#[0-9]' ROADMAP.md` → 13
   - For each issue: `gh issue view N --json body -q .body | grep -c ROADMAP.md` → ≥1
3. **[checkpoint:human-verify]** Show the finished table and the issue list side
   by side; confirm no roadmap row is orphaned and no issue is unreferenced.
4. Run: `harness validate`
5. Commit: `docs(roadmap): link every remaining item to its tracked issue`

---

### Task 18: Require the CI checks on `main`

**id:** `t18-branch-protection` | **dependsOn:** `t15-open-pr`
**files:** none
**Category:** integration
**[checkpoint:human-action]**

A workflow without branch protection is decorative — the spec lists this as a
required registration and it cannot be done from a workflow file.

1. **[checkpoint:human-action]** The human enables branch protection on `main`
   (Settings → Branches → Add rule), or authorizes the API call:
   ```
   echo '{"required_status_checks":{"strict":true,"contexts":["gates-complete"]},
          "enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null}' \
   | gh api -X PUT repos/ahhrealmonster/claude-portable-setup/branches/main/protection \
       -H "Accept: application/vnd.github+json" --input -
   ```
   The body goes in as JSON, not as `-f` pairs. `-f` sends every value as a
   *string*, and this endpoint requires real booleans and nulls — the `-f`
   form returns `422 "true" is not a boolean` and changes nothing. Corrected
   after it failed exactly that way on 2026-09-09.

   Use the **canonical owner name**. `ahhrealmonstr` was renamed to
   `ahhrealmonster` and the old name has since been deleted. GitHub follows
   renames on GET, so reads against a stale name keep working and look healthy;
   a PUT returns `307 Moved Permanently`, which `gh api` will not follow for
   write methods, so the write silently lands nowhere. That is the failure
   shape this repo exists to name, arriving through the URL.
   Require **`gates-complete` only**, not the individual legs: it is the job
   that verifies each leg actually ran, and requiring a matrix leg by name
   breaks the moment `windows-latest` joins in M2. Requiring the legs *instead*
   of the aggregate would also mean a skipped leg shows as neutral rather than
   failing.
2. Verify it took, rather than assuming:
   `gh api repos/ahhrealmonster/claude-portable-setup/branches/main/protection -q '.required_status_checks.contexts'`
   → must list `gates-complete`. An empty list here is the zero denominator.
3. **[checkpoint:human-verify]** Confirm on the open PR that `gates-complete` is
   now labelled **Required**.

---

### Task 19: Final sweep — trace every exit criterion to evidence, then merge

**id:** `t19-final-sweep` | **dependsOn:** `t17-roadmap-backfill`, `t18-branch-protection`
**files:** none
**[checkpoint:human-verify]**

1. Re-run all four gates on the final state (not the pre-fix run) plus
   `harness validate` and `harness check-deps`.
2. Trace each M1 exit criterion to its evidence and state it explicitly:
   - **SC-1** — `test -f STRATEGY.md && test -f ROADMAP.md`; `harness validate`
     clean.
   - **SC-2 (two OSes)** — link the PR run showing four legs plus
     `gates-complete`, none skipped; `gates-complete` is Required on `main`.
   - **SC-3** — link the `bare install` job logs on both OSes showing exit 0;
     cite `tests/test-bare-install.sh` cases 3 and 9 as the pins that make an
     exit of 2 and a missing artifact fail.
   - **SC-4** — the `not verified:` block in both the pass log and the
     fail-path test case.
3. Doc-drift and testing-gap check (rule 8), asked explicitly rather than
   assumed: what does this branch make wrong that Tasks 13–14 missed, and what
   behaviour did it add that nothing tests? Record the answers; file an issue
   for anything unresolved rather than stepping over it (rule 5).
4. **[checkpoint:human-verify]** Present the trace; get sign-off to merge.
5. Merge once green. Then close the M1 issues (if any were created) and run
   `./tools/check-drift.sh` on this machine — nothing under `home/` changed in
   M1, so it should be unchanged, but the habit is the point.

---

## Dependency Graph

```
t1 ──┬─ t2 ── t3 ────────────────────────────────┐
     └─ t8 ── t9 ── t10 ──┬────────────┐          │
                          │            │          │
t4 ── t5 ── t6 ── t7 ─────┘            │          │
                                       │          │
t11 ── t12 ──┬── t13 ──────────────────┴──┬── t15 ─┴── t16 ── t17 ──┐
             └── t14 ────────────────────┘        └── t18 ─────────┴── t19
```

Parallel waves (disjoint `owns`, no edge):

| Wave | Tasks | Note |
|---|---|---|
| 1 | `t1`, `t4`, `t11` | config, test suite, strategy doc — three separate files |
| 2 | `t2`, `t5`, `t8`, `t12` | `t8` needs `t1` for the `harness.config.json` parse gate |
| 3 | `t3`, `t6`, `t9` | |
| 4 | `t7`, `t10` | |
| 5 | `t13`, `t14` | |
| 6 | `t15` | human-action; serialises everything after it |
| 7 | `t16`, `t18` | |
| 8 | `t17` | |
| 9 | `t19` | |

`.github/workflows/ci.yml` is written by `t8`, `t9`, `t10` in that order — one
file, three sequential edits, never parallel.

---

## Checkpoints

| Task | Type | What it gates |
|---|---|---|
| 1 | `[checkpoint:human-verify]` | Generated `harness.config.json` reviewed before a public commit |
| 2 | `[checkpoint:decision]` | Whether `.harness/knowledge/extracted/` stays ignored |
| 3 | `[checkpoint:decision]` | Whether `EXCLUDED.md` rows 14–15 get a pointer now or in M3 |
| 4 | `[checkpoint:decision]` | `tools/bare-install.sh` vs inline YAML — governs Tasks 4–10 |
| 15 | `[checkpoint:human-action]` + `[checkpoint:human-verify]` | Push authorization; first real CI run, denominator checked |
| 16 | `[checkpoint:decision]` + `[checkpoint:human-action]` | Issue granularity; authorization to create public issues |
| 18 | `[checkpoint:human-action]` + `[checkpoint:human-verify]` | Branch protection on `main`, verified rather than assumed |
| 19 | `[checkpoint:human-verify]` | SC trace and merge sign-off |

---

## Out of Scope for M1

Named so the boundary is explicit rather than implied:
`windows-latest` (M2-3), the Python port (M2-2), `tools/parity-check` (M2-1),
the NTFS exec-bit skip (M2-4), the `global.md` voice rewrite (M3-1),
`profile.example.md` (M3-2), the full `EXCLUDED.md` re-scope (M3-3), the overlay
contract (M3-4), reverse drift (M4-1), and the D5 ADR (belongs with M2).
