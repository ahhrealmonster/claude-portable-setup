# Claude working-setup bundle — portable

A carry-over of the agent working setup from another machine: the shared
agent-agnostic working rules, the Claude-specific mechanics that sit on top of
them, one personal skill, a session-start tooling-rot hook, and a settings
template. Everything here is **generic craft** — no employer, client, private
repo, or internal tooling is referenced. See [EXCLUDED.md](EXCLUDED.md) for what
was deliberately left behind and why.

## How to use it

Copy this directory to the new machine, open Claude Code in it, and say:

> Read README.md and INSTALL.md in this directory and set up this machine.

The agent will do the install. Or run the steps yourself from
[INSTALL.md](INSTALL.md) — five required, one optional, and none of them
overwrite an existing config without asking.

Already have this installed and are updating it? Skip to
[INSTALL.md §7](INSTALL.md#7-re-installing-over-a-setup-that-already-exists) —
"don't overwrite without asking" means the honest answer is often *skip*, and a
skipped file stays behind the bundle silently.

## What's in it

| File | Goes to | What it does |
|---|---|---|
| `home/ai-rules/global.md` | `~/.config/ai-rules/global.md` | The working rules, agent-agnostic — visual-first decisions, denominator checks, TDD, trail markers, PR-review verdicts, repo conventions, standard workflow. Every agent on the machine reads this one file |
| `home/CLAUDE.md` | `~/.claude/CLAUDE.md` | Claude Code-specific mechanics only — the visual level dial, the siren, skill selection, worktree isolation, permission hygiene. Opens by `@import`ing the shared file above |
| `home/skills/visual-decisions/` | `~/.claude/skills/` | Personal skill: render a visual before any non-trivial decision, with a latency/cost level dial |
| `home/hooks/tooling-rot-siren.sh` | `~/.claude/hooks/` | SessionStart hook: catches degraded local tooling (missing/disabled plugin, stale marketplace checkout, CLI-vs-plugin version skew, a plugin manifest pinning a stale npm version) before work starts |
| `home/hooks/rot-watch.example.json` | `~/.claude/hooks/` | Watchlist config for the siren. No config = silent; a `cli` with no `npm` key = partial coverage, and it says so |
| `home/hooks/statusline-context.sh` | `~/.claude/hooks/` | Statusline: live context gauge + this session's weighted token burn, read from the transcript's real usage records |
| `home/hooks/clear-nudge.sh` | `~/.claude/hooks/` | PostToolUse hook: suggests `/clear` only when a commit/PR/merge/push has banked the work **and** context is already expensive |
| `home/settings.template.json` | merge into `~/.claude/settings.json` | Model, effort, theme, notifications, empty-by-design permissions, plugin list, statusline + hook wiring |
| `home/memory/` | `~/.claude/projects/<project>/memory/` | Seed memories: the visual-learner fact, and the two-file rules split (which file is a symlink and which is not) |
| `tools/check-drift.sh` | — | Read-only check that what's deployed still matches what's here. Exit 2 for "nothing installed" is distinct from exit 0 on purpose |
| `tests/` | — | Executable regression tests for the three hooks and the drift check (99 cases). `./tests/run-all.sh` |

## The two ideas worth keeping even if you drop the rest

**Visual before decision.** Prose-only option lists lose the consequences. Every
non-trivial decision gets a picture first — with a level dial so it never adds
latency to small questions. That dial is the part that makes it survive; the
first version without it was abandoned for being slow.

**A zero denominator is an abstention, not a pass.** "0 files checked ✓" is not
green, it's a gate that didn't run. This is a targeted habit for load-bearing
gates, not a mandate to distrust every exit code. The siren hook is the
mechanical version of the same idea, scoped to local tooling health.
