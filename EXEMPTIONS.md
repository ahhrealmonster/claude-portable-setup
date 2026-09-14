# Declared exemptions

Gates this repo does **not** run, each with the reason it does not, and the
condition that would make the exemption expire.

This file exists because of the rule the whole bundle is built around: a check
that verified nothing is an abstention, not a pass, and silence has to be
*earned by declaring the gap* rather than granted by omitting it. An undeclared
exemption is indistinguishable from nobody having looked.

Each entry is guarded by an executable test where that is possible, because a
declaration can outlive its reason. Prose asserting a premise that quietly
became false is the same false-green shape the exemption is granted against.

---

## `harness check-docs` — documentation coverage

**Status:** exempt · granted by [#17](https://github.com/ahhrealmonster/claude-portable-setup/issues/17)
**Guarded by:** `tests/test-docs-exemption.sh`

`harness check-docs` reports:

```
x Documentation coverage: undetermined (0 files scanned)

ABSTAINED: 0 source files scanned — coverage undetermined, not a pass.
```

**Why it abstains.** `checkDocCoverage` discovers source with the glob
`**/*.{ts,js,tsx,jsx,mjs,cjs}`. This bundle is bash hooks, JSON config and
Markdown — it contains no file the scanner recognises as source. The denominator
is zero because there is genuinely nothing to measure, not because the scan is
misconfigured.

**Why `rootDir` will not fix it.** The abstention message points at
`config.rootDir`, and that is good advice for a repo whose source sits somewhere
unexpected. It does not apply here: no value of `rootDir` can make a `.sh` file
match a `{ts,js,tsx,jsx,mjs,cjs}` glob. Setting one would relocate the scan
without changing its result.

**What is NOT claimed.** This is an exemption from *automated coverage
measurement only*. It is not a claim that the bundle is well documented, and it
does not exempt any change from the documentation expectations in `CLAUDE.md` —
those are reviewed by humans, as they always were.

**Expires when** this repo gains any tracked `.ts`, `.js`, `.tsx`, `.jsx`,
`.mjs` or `.cjs` file. At that moment `check-docs` can report a real
denominator, the reasoning above stops holding, and
`tests/test-docs-exemption.sh` fails with instructions to wire `check-docs` into
CI and delete this entry. The guard deliberately ignores `.harness/`, which is
tool runtime state rather than this repo's source.

---

## `required-review` — LLM review tier

**Status:** degraded, *not* exempt · tracked by [#17](https://github.com/ahhrealmonster/claude-portable-setup/issues/17)

Listed here for honesty, not to excuse it. `harness review-ci` runs its
heuristic floor on every PR but skips its LLM tier, because no
`ANTHROPIC_API_KEY` secret is configured on the repo:

```
FLOOR-ONLY — LLM tier did not run (secret ANTHROPIC_API_KEY not set);
N heuristic finding(s), 0 blocking. This green is not a review.
```

The check stays green, and the workflow annotates every run with that sentence
so a floor-only pass can never be mistaken for a reviewed one. That labelling is
a mitigation, not a fix — the gate is not currently doing the job its name
implies.

**To fix it**, add the secret:

```bash
gh secret set ANTHROPIC_API_KEY --repo ahhrealmonster/claude-portable-setup
```

The LLM tier activates on the next PR with no workflow change; the pins in
`.github/workflows/required-review.yml` already carry a validated CLI version.
Fork PRs will continue to run floor-only by design — the workflow triggers on
`pull_request`, never `pull_request_target`, so an outside branch is never handed
the org's keys.
