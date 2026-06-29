---
name: goal-wrap
description: Use when work is ready to hand off, continue in a new session, or run autonomously — bundles current state into a /goal prompt with tracked done-when criteria and architecture grounding
permissions:
  filesystem: read
  network: false
metadata:
  openclaw:
    requires:
      bins: []
      env: []
---

# Goal Wrap

## Overview

Bundle current conversation state into a self-contained `/goal` prompt that a fresh session or autonomous runner can execute without context.

**Announce at start:** "I'm using the goal-wrap skill to bundle this work."

**Core outputs:**
1. Architecture grounding — research agents orient to the codebase first
2. Tracked DONE WHEN — each criterion has a proof command; executor updates status
3. `/goal` prompt under 4000 chars, paste-ready for fresh session or `/loop`

**Flags:**
- `--gates` — enable Claude Code's default ask-before-irreversible behavior
- (no flag) — full autonomy: commits, push, merge, deploys, DB changes all pre-approved

---

## Step 0: Detect Available Tools

Check which optional tools are present before starting:

```bash
# Ruflo swarm
HAS_RUFLO=0
command -v ruflo >/dev/null 2>&1 && HAS_RUFLO=1

# GBrain (prior decisions memory)
HAS_GBRAIN=0
command -v gbrain >/dev/null 2>&1 && HAS_GBRAIN=1

# Repowise MCP — attempt get_overview(); if it errors, treat as absent
# HAS_REPOWISE set to 1 in Step 1 if call succeeds
```

Note which are available. Absent tools degrade gracefully — core value is preserved.

---

## Step 1: Architecture Research (grounded, not recalled)

Run research agents in parallel before writing anything. Use best available option per dimension.

### Spawn parallel research agents (in one message)

**Agent A — Codebase structure:**
- If repowise available: `get_overview()` + `get_answer("key entry points, services, data flows, hotspot files")`
- Otherwise: read README first 60 lines + `git log --oneline -15` + `find . -maxdepth 3 \( -name '*.ts' -o -name '*.py' -o -name '*.go' \) | grep -v node_modules | head -30` + detect framework from `package.json`/`pyproject.toml`/`go.mod`

**Agent B — Prior decisions:**
- If gbrain available: `env -u DATABASE_URL gbrain query "<task>"` + `gbrain search "<key terms>"`
- Otherwise: `git log --oneline -20` + `git diff origin/main...HEAD --stat` + `find docs -name '*.md' 2>/dev/null | xargs grep -l 'decision\|ADR\|why' 2>/dev/null | head -5`

**Agent C — Active specs + tasks:**
- `find specs -maxdepth 3 -name 'spec.md' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -3 | cut -d' ' -f2-`
- `git diff origin/main...HEAD --name-only`
- TaskList if available — count + IDs of in-progress items

Synthesize into **ARCH_CONTEXT** (max 600 chars):
```
ARCH:
entry: <key files/routes>
services: <list>
spec: <active spec name>
decisions: <1-2 relevant prior decisions, or "none recalled">
hotspots: <high-churn files, or "unknown">
tasks: <count> (<ids or "see handoff doc">)
tools: repowise=<yes|no> gbrain=<yes|no> ruflo=<yes|no>
```

---

## Step 2: Parse flags + gather context

Parse `$ARGUMENTS`:
- `--gates` present → `AUTONOMY=supervised` (ask before irreversible/high-blast actions)
- No flag → `AUTONOMY=full` (all prod/DB/merge/deploy pre-approved, no prompts)

Detect:
```bash
SPEC_PATH=$(find specs -maxdepth 2 -name 'spec.md' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
PLAN_PATH=$(dirname "$SPEC_PATH")/plan.md
BRANCH=$(git branch --show-current)
REPO=$(basename "$(git rev-parse --show-toplevel)")
```

If no `spec.md` + `plan.md`: ask operator:
> "No spec/plan found — anti-drift baseline cannot be established. (A) create spec first, (B) point to existing reference doc, (C) continue without baseline."

---

## Step 3: Anti-drift SHAs

```bash
SPEC_SHA=$(git log -1 --format=%h -- "$SPEC_PATH" 2>/dev/null || echo "uncommitted")
PLAN_SHA=$(git log -1 --format=%h -- "$PLAN_PATH" 2>/dev/null || echo "uncommitted")

# Auto-commit if dirty — feature branch only, never ask
if [ "$SPEC_SHA" = "uncommitted" ] || ! git diff --quiet -- "$SPEC_PATH" 2>/dev/null; then
  CURRENT=$(git branch --show-current)
  if [ "$CURRENT" = "main" ] || [ "$CURRENT" = "master" ]; then
    echo "STOP: on $CURRENT — branch first, then re-run /goal-wrap"
    exit 1
  fi
  git add "$(dirname "$SPEC_PATH")" && \
    git commit -q -m "docs(spec): baseline for goal-wrap"
  SPEC_SHA=$(git log -1 --format=%h -- "$SPEC_PATH")
  PLAN_SHA=$(git log -1 --format=%h -- "$PLAN_PATH")
fi
```

---

## Step 4: Build tracked DONE WHEN criteria

Extract acceptance criteria from `spec.md`. Each item: `STATUS | DESCRIPTION | proof: BASH_COMMAND`.

**Status machine (executor updates these):**
- `[ ] pending` → `[→] in_progress` → `[✓] verified` (proof ran + exit 0 + output captured)
- `[✗] blocked` — proof failed or prereq missing

**Proof command rules:**
- Must exit 0 when criterion is proven true
- Must be runnable non-interactively from repo root
- Must NOT be "I verified X" — always a real command

**Template:**
```
DONE WHEN:
[ ] pending | <outcome 1 from spec>             | proof: <bash cmd>
[ ] pending | <outcome 2 from spec>             | proof: <bash cmd>
[ ] pending | All e2e tests pass                | proof: <e2e cmd for this repo>
[ ] pending | All unit + integration tests pass | proof: <unit cmd for this repo>
[ ] pending | No spec/plan drift               | proof: git diff <SPEC_SHA>..HEAD -- <SPEC_PATH> <PLAN_PATH> | wc -l | grep -qx 0
[ ] pending | No open in-progress tasks        | proof: <task count check or "manual verify">
```

Goal clears ONLY when ALL items show `[✓]`. Executor never self-reports done without proof exit 0.

---

## Step 5: Invoke prompt-master for goal body

Call `Skill(prompt-master)` with:

```
Draft a /goal-runnable prompt under 2800 chars for autonomous execution. Context:
- Repo: <name>, Branch: <branch>
- AUTONOMY: <full|supervised>
- Spec: <SPEC_PATH> @ <SPEC_SHA>
- Plan: <PLAN_PATH> @ <PLAN_SHA>
- Objective: <task description>
- Architecture: <ARCH_CONTEXT>
- Available tools: repowise=<yes|no> gbrain=<yes|no> ruflo=<yes|no>
- Constraints:
  * AUTONOMY=<mode>: [full = all prod/DB/merge pre-approved, no prompts] [supervised = ask before irreversible]
  * Parallel Agent calls for 2+ independent tasks; Ruflo swarm_init if ruflo available for 3+
  * Use repowise for codebase Q if available; else grep+git
  * Use gbrain for prior decisions if available; else scan docs/adr/
  * Full tests must pass before any DONE WHEN → [✓]
  * Run proof command; capture exit+output before updating status
  * Anti-drift: trace every action to spec @ <SPEC_SHA>. Drift = STOP
  * Checkpoint after each DONE WHEN change: {item, status, proof_output, blockers, next}
Output ONLY prompt body. No wrapper, no fence. Target 2000-2800 chars.
```

Compress if over 2800 (max 2 retries).

---

## Step 6: Assemble /goal body

```
PROJECT: <repo>
BRANCH: <branch>  AUTONOMY: <full|supervised>
SPEC: <SPEC_PATH> @ <SPEC_SHA>  [anti-drift baseline]
PLAN: <PLAN_PATH> @ <PLAN_SHA>  [anti-drift baseline]

<ARCH_CONTEXT>

<prompt-master output>

HANDOFF DOC: <path from Step 7>

DONE WHEN (run proof cmd → capture exit+output → update status):
<DONE WHEN list>

AGENTS: parallel Agent calls for independent work; Ruflo swarm_init if available (3+ tasks)
RESEARCH: repowise if available; else grep+git for codebase Q
MEMORY: gbrain if available; else scan docs/adr/ for prior decisions
```

Verify total ≤4000 chars: `printf '%s' "$GOAL_BODY" | wc -c`

Final form: `/goal "<GOAL_BODY>"` ready to paste.

---

## Step 7: Handoff doc

Call `Skill(handoff)` if available. Otherwise write to `$TMPDIR/goal-handoff-$(date +%s).md`:

```markdown
# Goal Handoff: <task>
Branch: <branch> | Date: <YYYY-MM-DD>
Spec: <path> @ <SHA>
Plan: <path> @ <SHA>
Recent commits:
<git log -5 --oneline output>
Open tasks: <count/ids>
ADRs touched: <paths>
Architecture: <ARCH_CONTEXT>
Outstanding decisions: <list or "none">
```

Inject handoff path into GOAL_BODY.

---

## Step 8: E2E check

```bash
HAS_E2E=0
{ [ -f playwright.config.ts ] || [ -f playwright.config.js ] || \
  [ -f cypress.config.ts ] || [ -f cypress.config.js ] || \
  grep -q '"test:e2e"' package.json 2>/dev/null || \
  [ -d e2e ] || [ -d tests/e2e ] || [ -d web/e2e ]; } && HAS_E2E=1
```

If absent: ask operator — (A) add e2e setup as part of goal work, (B) replace e2e gate with manual verification in DONE WHEN, (C) abort.

---

## Step 9: Surface bundle

```
=== /goal-wrap bundle ready ===
AUTONOMY: <full — all prod/DB/merge pre-approved | supervised — ask before irreversible>
TOOLS: repowise=<yes|no>  gbrain=<yes|no>  ruflo=<yes|no>
RESEARCH: ✓ parallel agents completed (degraded where tools absent)

GOAL PROMPT (<NNNN>/4000 chars):
──────────────────────────────────────
/goal "<GOAL_BODY>"
──────────────────────────────────────

HANDOFF DOC: <path>

ANTI-DRIFT BASELINE:
  spec: <path> @ <SHA>
  plan: <path> @ <SHA>

DONE WHEN (<N> items, all pending):
  [ ] <criterion 1>  (proof: <cmd>)
  [ ] <criterion 2>  (proof: <cmd>)
  [ ] All e2e tests pass  (proof: <cmd>)
  [ ] All unit+integration tests pass  (proof: <cmd>)
  [ ] No spec/plan drift  (proof: git diff ...)

ARCHITECTURE GROUNDING:
  <ARCH_CONTEXT>

E2E STATUS: <ok | gap-flagged>

NEXT:
  Paste /goal in fresh session → executor runs proof cmds, updates DONE WHEN
  OR: /loop 30m /goal "..." for autonomous run
  OR: /schedule for deferred execution
```

---

## Hard Rules

- Goal body ≤4000 chars. Budgets: ARCH_CONTEXT 600 · DONE WHEN 400 · prompt body 2800 · headers 200.
- DONE WHEN items MUST have proof commands. Flag any missing; do not emit goal until fixed.
- AUTONOMY=full is default. `--gates` is the only opt-in to confirmation prompts.
- Research agents (Step 1) MUST run before prompt-master. Degrade gracefully; never skip entirely.
- Anti-drift SHA = committed state. Auto-commit on feature branch; STOP on main/master.
- Never include secrets. Redact API keys, passwords, PII in both goal and handoff.

## Degradation Table

| Tool | Present | Absent |
|---|---|---|
| **Ruflo** | `swarm_init` + `agent_spawn` for 3+ parallel tasks | Parallel Agent tool calls in same message |
| **Repowise** | `get_overview` + `get_answer` + `get_risk` | README + `git log` + `find`/`grep` for entry points |
| **GBrain** | `gbrain query/search` for prior decisions | Scan `docs/adr/` + `git log` messages |
| **prompt-master** | `Skill(prompt-master)` | Hand-craft prompt body directly |
| **handoff skill** | `Skill(handoff)` | Write minimal handoff to `$TMPDIR` |

## Common Mistakes

**Skipping research (Step 1)**
- Problem: goal prompt blind to actual codebase state
- Fix: always run research agents first, even in degraded mode

**DONE WHEN without proof commands**
- Problem: executor has no way to verify completion
- Fix: every criterion needs a runnable bash proof command

**Ignoring AUTONOMY flag**
- Problem: executor asks for confirmation despite AUTONOMY=full
- Fix: executor reads AUTONOMY from goal header and honors it verbatim

**Marking [✓] without running proof**
- Problem: false completion, unverified state
- Fix: run proof cmd, capture output, check exit 0 — then update status

## Integration

**Pairs with:**
- `subagent-driven-development` — use after all tasks queued; goal-wrap bundles for handoff
- `executing-plans` — goal-wrap can wrap the executing-plans goal for autonomous resumption
- `using-git-worktrees` — goal-wrap respects worktree context in GOAL_BODY

**Called before:**
- `/loop` — paste goal into loop for autonomous iteration
- `/schedule` — schedule goal for deferred execution
- Machine switch / session end
