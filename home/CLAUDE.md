# Claude Code — machine rules

The shared, agent-agnostic working rules live in one file used by every agent on
this machine (Claude, Gemini, Codex, Copilot). Read them first:

@~/.config/ai-rules/global.md

Everything below is **Claude Code specific** — it names skills, hooks, settings
files, and tool behavior that only exist here. Edit shared rules in
`~/.config/ai-rules/global.md`; edit Claude-only mechanics here.

---

## Visual first — the mechanics

Shared rule 1 states the *policy* (visual before any non-trivial decision, level
defaults to `standard`). The `visual-decisions` skill at
`~/.claude/skills/visual-decisions/SKILL.md` holds the *implementation*: which
tool to reach for at each level, the level dial, and the rendering rules.

| Level | What renders |
|---|---|
| `quick` | `AskUserQuestion` previews + plain-chat visuals only (markdown tables, ASCII sketches). Never load a widget tool. |
| `standard` *(default)* | Previews and plain-chat visuals for most decisions; an inline widget **only** for high-stakes structural calls. Max ~1 widget per decision. |
| `rich` | Widgets liberally, `Artifact` for mocks worth revisiting. |

Switch with "visuals: quick" / "go rich" — honor it for the rest of the session.
Auto-escalate one level for genuinely high-stakes calls; never auto-linger.

## Tooling-rot siren

`~/.claude/hooks/tooling-rot-siren.sh` runs at SessionStart and is the mechanical
half of shared rule 2 (denominator check). It watches for degraded local tooling
— a plugin installed but not enabled, a stale marketplace checkout, CLI-vs-plugin
version skew, a plugin manifest pinning a stale npm version — before any work
starts.

- Config: `~/.claude/hooks/rot-watch.json` (template: `rot-watch.example.json`).
- **No config = silent by design.** Nothing was asked for, so nothing is claimed.
- **A watchlist that exists but is empty reports itself** — coverage was intended
  and isn't there. That is the rule-2 behavior, not a bug.
- **A watched `cli` with no `npm` key reports itself too** — the drift check
  silently skips it, so a half-covered watchlist would otherwise look identical
  to a full one. Declare `"npm_exempt": true` if the CLI genuinely isn't
  published; silence is earned by declaring the gap, never by omitting the key.
- **A plugin that hardcodes a version in its own manifest is watched with
  `pin_npm`.** Every other check reads what the machine installed, so an exact
  pin buried in an `mcpServers` args array diverges from a floating local CLI
  with all four other checks green. `pin_npm` needs a `plugin` key to locate the
  manifest, and reports when it matches nothing rather than passing quietly.
- **A version hardcoded in a repo file is watched with `pin_files`.** Same rot,
  different hiding place: `pin_npm` reaches a plugin manifest through its
  `installPath` and so cannot see a CI workflow. Point a glob at the files
  (`~` expands). A glob matching zero files is a finding — otherwise renaming a
  directory retires the check silently, which is the zero denominator again.

If the siren fires, surface it in the first message of the session and treat it
as outranking new work — then **put it to the user as an `AskUserQuestion`
yes/no before starting anything else** (shared rule 2). A siren reported as a
bullet in a status message gets read and stepped over; only a blocking ask
actually gets answered. Options should be *fix now* / *defer*, with the cost of
deferring stated in the option description.

- **Scope the ask before asking.** Check how the tool is pinned where it
  matters. A `@N` major-range pin (`@harness-engineering/cli@10`) floats to the
  newest `N.x`, so CI is already on the new release and only the local install
  is stale — that is a one-line `npm i -g`, not a pin migration. An exact pin is
  the case that needs the full version-tracking ceremony. Reporting the heavy
  version of a light finding is its own kind of noise.
- **Re-run the siren after fixing** and say that it cleared. Confirm the
  watchlist is non-empty when it goes quiet — under this hook's own rules,
  silence and "no config" look identical, so unverified silence isn't a pass.

## Context instruments

Two hooks make context cost visible, because cost scales with *(context size ×
turns)* and the built-in indicator is passive enough to be noticed several tasks
too late.

- `~/.claude/hooks/statusline-context.sh` — statusline gauge and session burn,
  derived from real usage records rather than an estimate. **A blank statusline
  means the hook died**, and blank looks exactly like 0%; treat it as a finding.
- `~/.claude/hooks/clear-nudge.sh` — PostToolUse on `Bash`. Suggests `/clear`
  only when a commit/PR/merge/push has banked the work *and* context is already
  past 100k. When it fires, offer `/clear` in one short line if the next request
  starts genuinely new work — and say nothing if the same thread is continuing.
  Nagging is what retired the passive indicator.

All three hooks have executable regression tests in the bundle repo
(`./tests/run-all.sh`). Every bug that has escaped one has a case there.

## Skill selection

- **Prefer the specific skill over the general one** whenever both apply. A skill
  that encodes this machine's actual methodology or names the exact tool in play
  beats a generic one every time; name those skills explicitly here once they're
  installed, so the preference survives a session that never reads their
  descriptions closely.
- A lean skill listing is what makes the right skill get picked — that is what
  `skillOverrides` in `settings.json` exists to protect. Turn off duplicates and
  anything that fires unwanted, rather than hoping the listing sorts itself out.
- Personal skills go in `~/.claude/skills/`; see shared rule 10 for how to size a
  new skill by blast radius.

## Concurrency

Shared rule (Repo Conventions → Concurrency & worktrees) covers the git side.
Claude-specific: spawned agents that mutate files should run with
`isolation: "worktree"`.

## Permission hygiene

- **Never write files with a Bash heredoc** (`cat > f <<'EOF' … EOF`) — use the
  Write/Edit tools. The permission layer splits a compound Bash call into
  per-line sub-commands, so a heredoc body becomes one approval prompt *per line
  of file content*, and approving them writes each line into `permissions.allow`
  as a permanent rule. On the machine these rules came from, that mechanism
  accumulated 77 junk entries — JSON fragments, `Bash({)`, `Bash(JSONEOF)` — plus
  client payload values that had no business in a config file. Same reasoning for
  multi-line `printf`/`echo` file writes.
- **Allowlist entries should be wildcard verbs, not one-shot invocations.**
  `Bash(npm run:*)` earns its place; a fully-specified one-off command never
  matches twice and just buries the real rules. The wildcard syntax is `:*` — a
  trailing ` *` does not match.
- **Nothing that pushes or rewrites remotes goes in the allowlist** —
  `git push`, `git remote set-url`, and publish commands should keep prompting.
- **Treat the allowlist as data that leaks.** It's a config file nobody thinks to
  audit, so pasted payloads sit there indefinitely. This machine keeps its
  allowlist in `~/.claude/settings.local.json`; grow it from real prompts here,
  never inherit one from another machine.
