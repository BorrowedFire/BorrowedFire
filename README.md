# Borrowed Fire

A personal agent **memory + development orchestration system**: one set of markdown skills that
works identically across Claude Code, Codex, Qwen Code, and OpenClaw, backed by **Prometheus** — a
private, git-authoritative markdown brain (in the lineage of
[gbrain](https://github.com/garrytan/gbrain)) shared by every machine and harness you run.
Borrowed Fire is the system; Prometheus, the one who borrowed the fire, is its memory.

- **Memory** compounds: every agent captures decisions, people, meetings, and hard-won lessons
  into the brain; every agent reads them back before it works.
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

every skill ──▶ remember (lessons, decisions) ──▶ digest (consolidate) ──▶ recall (next run knows)
```

The shared rules every agent follows — brain sync protocol, capture triggers, safety rails, tier
routing — live in [`doctrine/DOCTRINE.md`](doctrine/DOCTRINE.md), installed into every harness's
context file. The high-risk denylist (always owner-gated) is defined once in
[`skills/land/references/denylist.md`](skills/land/references/denylist.md).

## Repo layout

```
skills/            15 SKILL.md skills (+ agents/openai.yaml metadata, references/)
doctrine/          the managed context block install.sh distributes
prometheus-template/  starting tree for your private brain repo
install.sh         manifest-owned cross-harness installer
tools/skill-lint.sh   lint (also install.sh's preflight; runs in CI)
tests/             installer sandbox matrix + brain-protocol live proof (run in CI)
```

## Local model routing

`tools/bf-route` is the controller-side entry point for the optional local fleet. It reads model
endpoints from the private Prometheus `config/fleet.md`, classifies work with deterministic risk
rules, and runs local implementation in an isolated exact-commit snapshot. The default experiment
routes routine work to `local-volume`, deeper work to `local-quality`, and paid judgment to Codex
only when explicitly permitted. Claude is not part of this experimental route.
Replace the local-tier and router-setting placeholders in the private fleet configuration
before the first run.
Legacy `local-volume` / `local-large` rows that contain only an endpoint remain supported: the
router uses conservative timeout defaults and requires that each legacy endpoint expose exactly
one model from `/v1/models`. To migrate an existing brain, add a `Controller SSH host` row under
the `## Router settings` heading, using the SSH host or alias for that worker; model names and
timeout rows do not need to be added. If only one local tier is configured, it serves both local
routing roles. Repositories with Git submodules are rejected from local routing because their
gitlink alone cannot produce an exact, self-contained snapshot.

```sh
bf-route decide --task "Update these documentation headings"
bf-route run --repo . --task "Fix the bounded parser bug"
bf-route run --repo . --task "Fix the bounded parser bug" --apply
bf-route run --repo . --task "Perform the final independent review" --mode advice --allow-paid
```

Local jobs return patch and final-message artifacts under
`~/.local/state/borrowedfire-route/`. `--apply` refuses a dirty or moved checkout. Paid escalation
requires `--allow-paid`, a matching private paid-task whitelist entry (owner-gated work is handled
as an explicit escalation), and room under the private escalation cap. The worker never receives
GitHub credentials or the Docker socket.

An authorized worker is bootstrapped explicitly rather than by the ordinary harness installer:

```sh
tools/install-local-agent-worker --host <ssh-host>
```

The agent container has a read-only root filesystem and runs as the worker user. Its internal
Docker network can reach the selected local model container but has no internet route.

Skills are plain markdown — readable by any agent that can read files, portable to any harness
that supports the SKILL.md convention.

## Projects

- [Inventory Manager](https://github.com/BorrowedFire/Inventory-Manager): Apple-style macOS
  inventory workspace for local hardware tracking, deployments, stockrooms, budgets, backups, and
  Sparkle updates.
