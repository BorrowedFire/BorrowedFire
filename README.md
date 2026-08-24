# Borrowed Fire

A personal agent **memory + development orchestration system**: one set of markdown skills that
works identically across Claude Code, Codex, Qwen Code, and OpenClaw, backed by **Prometheus** — a
private, git-authoritative markdown brain (in the lineage of
[gbrain](https://github.com/garrytan/gbrain)) shared by every machine and harness you run.
Borrowed Fire is the system; Prometheus, the one who borrowed the fire, is its memory.

- **Memory** compounds: every agent captures decisions, people, meetings, and hard-won lessons
  into the brain; every agent reads them back before it works. `reflect` runs automatically at
  substantive checkpoints, and one always-on host performs a bounded nightly consolidation pass.
- **Development** is orchestrated: a control-plane skill works the queue across all registered
  repos, delegating to a review-gated landing loop, with humans only answering decision-ready
  briefs.
- **Fleet-aware**: skills declare judgment-tier vs volume-tier work, so paid frontier tokens go to
  review/planning while local models do the bulk — your endpoints and caps live in your private
  brain, never in this public repo.

## Quick start

```sh
git clone https://github.com/BorrowedFire/BorrowedFire.git
cd BorrowedFire
./install.sh                 # detects ~/.claude, ~/.codex, ~/.qwen; add --openclaw-workspace <path>
```

The installer symlinks the skills into each harness, maintains a manifest so re-runs, renames, and
uninstalls are safe, and writes the shared doctrine block into each harness's context file. Then
create your private brain — named **Prometheus**, the one who borrowed the fire — from
[`prometheus-template/`](prometheus-template/README.md) and re-run
`./install.sh --brain ~/prometheus`.

Legacy note: if you installed older skill names by hand (takeoff, autoland, orbit,
repo-quality-audit), run `./install.sh --adopt` once to retire them safely (they're backed up, not
deleted).

## The skills

### Memory (Prometheus, the brain)

| Skill | What it does |
|---|---|
| [reflect](skills/reflect/SKILL.md) | Automatic learning pass: extract verified durable deltas from completed work, dedupe, connect them to prevention, and capture through Prometheus; includes a safe scheduled fleet mode. |
| [remember](skills/remember/SKILL.md) | Capture decisions, people, meetings, lessons, ideas into the brain — typed pages, wikilink graph, fleet-safe git sync. Owns the [schema](skills/remember/references/brain-schema.md). |
| [recall](skills/recall/SKILL.md) | Answer from the brain with page citations and honest gaps; preflight lessons before any repo work. |
| [digest](skills/digest/SKILL.md) | The dream cycle: promote inbox, ingest outboxes, dedupe entities, repair the graph, distill lessons, refresh the index. Locked, safe to schedule. |

### Development

| Skill | What it does |
|---|---|
| [land](skills/land/SKILL.md) | Drive ONE PR through adversarial + Codex review, auto-fix, live proof, merge-when-clean. The worker primitive. |
| [maintainer](skills/maintainer/SKILL.md) | Fleet control plane: read the brain's project registry, classify every queue item, delegate to `land` workers, surface decision-ready briefs. |
| [ship](skills/ship/SKILL.md) | Happy-path closeout: commit, push, merge, deploy, verify production. |
| [rollback](skills/rollback/SKILL.md) | Undo a bad merge/deploy, verify recovery live, capture the postmortem. |
| [store-release](skills/store-release/SKILL.md) | App Store / Play release trains — owner-gated submission, staged rollouts. |
| [changelog](skills/changelog/SKILL.md) | Factual release notes and changelogs from merged history. |
| [deps](skills/deps/SKILL.md) | Risk-batched dependency and security updates, landed through `land`. |
| [triage](skills/triage/SKILL.md) | Shape raw reports and ideas into bounded, reproducible, autonomous-ready issues. |
| [bootstrap](skills/bootstrap/SKILL.md) | Wire a new repo/app/idea into the system and register it in the brain. |
| [qa-audit](skills/qa-audit/SKILL.md) | Bounded QA loop: feature inventory, test matrix, defects, safe fixes, confidence report. |
| [signal](skills/signal/SKILL.md) | Marketing front door: route customer-facing copy through the Corey Haines Marketing Skills. |
| [technical-writing](skills/technical-writing/SKILL.md) | The four-layer standard for engineering prose: Diataxis modes, Google developer style, ASD-STE100 instruction rules, Global English syntax. |
| [unslop](skills/unslop/SKILL.md) | The slop-pattern catalog. Cuts AI tells from any prose before it ships; every other skill cites it by name. |
| [session-closeout](skills/session-closeout/SKILL.md) | Five-line honesty audit of requested, completed, missing, unasked, and unverified work. |

### How they fit together

```
idea/report ──triage──▶ shaped issue ─┐
                                      ├─ maintainer ──▶ land workers ──▶ merged + proven
brain projects/ registry ─────────────┘        │
                                               ▼
                          ship ──▶ deployed ──▶ verified ──(bad?)──▶ rollback
                                               │
                          store-release ◀──────┘ (mobile)   changelog / signal (words)

completed work ──▶ reflect (verify + dedupe) ──▶ remember ──▶ digest ──▶ recall
```

The shared rules every agent follows — brain sync protocol, capture triggers, safety rails, tier
routing — live in [`doctrine/DOCTRINE.md`](doctrine/DOCTRINE.md), installed into every harness's
context file. The high-risk denylist (always owner-gated) is defined once in
[`skills/land/references/denylist.md`](skills/land/references/denylist.md).

For genuinely unattended improvement, install the nightly controller on exactly one always-on
OpenClaw host after installing its workspace skills:

```sh
./install.sh --copy --brain /absolute/path/to/prometheus --openclaw-workspace /absolute/path/to/openclaw-workspace
./tools/install-prometheus-cycle.sh --notify-channel <channel> --notify-to <owner-route>
```

It declares one idempotent job at 03:35 America/New_York by default, does not pin a provider/model,
binds the OpenClaw `main` agent unless overridden with `--agent`, requires a concrete owner route,
verifies the complete learning stack is visible to that exact agent, migrates the declaration when
the agent changes, resolves and pins that agent's effective channel account across the probe, job,
and failure alert (using the runtime default when scoped or multiple inbound bindings are
ambiguous), clears stale one-shot deletion state, and enables only after a live route probe on each
explicit installer convergence plus scheduler-level failure-alert verification. The probe is a
disabled, transient command job that is force-run through the OpenClaw Gateway, requires a completed
`delivered` run record, and is removed before the learning job is enabled. This proves the route in
the scheduler's real privacy and credential context. Redacted OpenClaw configuration cannot safely
identify credential-only changes, so the installer never substitutes a cached route hash for that
live check. The nightly job remains silent on routine success or a no-op. See
[`skills/reflect/references/cycle-contract.md`](skills/reflect/references/cycle-contract.md).

## Repo layout

```
skills/            18 SKILL.md skills (+ agents/openai.yaml metadata, references/)
doctrine/          the managed context block install.sh distributes
prometheus-template/  starting tree for your private brain repo
install.sh         manifest-owned cross-harness installer
tools/skill-lint.sh   lint (also install.sh's local preflight)
tests/             local installer sandbox matrix + brain-protocol live proof
```

Skills are plain markdown — readable by any agent that can read files, portable to any harness
that supports the SKILL.md convention.

## Projects

- [Inventory Manager](https://github.com/BorrowedFire/Inventory-Manager): Apple-style macOS
  inventory workspace for local hardware tracking, deployments, stockrooms, budgets, backups, and
  Sparkle updates.
