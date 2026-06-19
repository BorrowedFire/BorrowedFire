---
name: maintainer
description: Control-plane orchestrator that keeps a repo green with minimal owner involvement — scan the queue (open PRs + issues + CI), classify each item, delegate autonomous ones to `autoland` workers, drive needs-owner items to a decision-ready state and surface one brief each, and keep a single ledger. Use for "/maintainer", "maintainer mode", "run the queue", "keep the repo green", "work the backlog", or continuous repo monitoring. It DELEGATES heavy work — it does not implement in this thread. Works in Claude Code and Codex (see Tool adapters). Build-cutting and releases are out of scope (separate, human-gated).
---

# Maintainer

A **control plane**: inspect, classify, delegate, monitor, and surface decision-ready asks. Put substantial
investigation / implementation / review / proof / landing into **workers** (`autoland` runs / subagents) and
keep *this* thread lightweight, monitoring by reading current state. The aim: turn a backlog into "the owner
answers a few one-tap decisions," nothing more.

## Scope

- The **current repo** by default. Touch a *sibling* repo only when an item genuinely spans it, and flag it.
- Exclude **nothing** as "ignored" unless the owner explicitly named it. Ordinary draft / stale / hard /
  platform-specific items are queue work, not ignored. Keep ignored items open and untouched.

## Tool adapters

| Abstract step | Claude Code | Codex |
|---|---|---|
| spawn a worker | background `Agent` subagent following `autoland` | a Codex thread running `$autoland` |
| self-paced monitoring | `ScheduleWakeup` / backgrounded loop | backgrounded task |

`git`, `gh`, and the `@codex review` bot are identical in both runtimes.

## Operating model

1. **Scan.** Open PRs, open issues, CI status, stale branches, latest release / unreleased changes. Build a
   one-line-per-item ledger.
2. **Classify** every item (re-classify as state changes):
   - **Autonomous** — clear, bounded, reproducible, with a real **live-proof path**.
   - **Needs-owner** — product choice, security/privacy/irreversible call, missing credential/access, no live
     proof, or it hits the autoland **denylist** (migrations / auth / payments / secrets / destructive).
   - **Ignored** — only an explicit owner instruction creates this.
3. **Delegate** (only when delegation is authorized — see Authorization):
   - **Autonomous PR** → fire an `autoland` worker on its branch.
   - **Autonomous issue (no PR)** → a worker investigates root cause, implements the best **bounded** candidate
     on a branch, opens a PR, then runs `autoland`.
   - One item per branch; keep a repo's work in its own worker. **Workers may not sub-delegate.**
4. **Drive needs-owner items to the decision-ready boundary** *before* asking — implement, fix, test,
   live-prove, review-to-clean, CI-green — then emit **one Owner Decision Brief** (autoland's format). For a
   reversible product call, pick a safe default, ship it in the PR, and note the alternative rather than blocking.
5. **Monitor** (below). Continue until: every autonomous item is **merged with proof**, every needs-owner item
   is a **decision-ready brief**, the effective queue is empty, or CI is green with a documented reason no work
   remains.

## Delegation model

- Bound worker concurrency (default **≤4** at once). Each worker prompt: the exact item + "follow the `autoland`
  skill for branch/PR X; do not sub-delegate; stop at the last authorized boundary and report." Pass the granted
  permissions explicitly.
- Monitor via worker-completion signals + reading PR/branch/CI state — **not** by re-doing the work here.
- Only this orchestrator creates/assigns/steers workers. Don't delegate triage or worker management.

## Monitoring protocol

Assume state may have moved since your last look. **Before steering any worker, read its latest state + the
current PR/CI.** Let an actively-progressing worker run — intervene only when evidence shows: it reports a
**blocker**, it's **idle/finished** and needs the next item, **repeated failure with a concrete fix available**,
or **wrong item / denylist breach / destructive action / risk / direct conflict with the owner's latest word**.
Don't restate the task, add speculative requirements, or **raise the proof bar mid-flight** — apply autoland's
live-proof gate from the start; never downgrade missing live proof to a "release-only" problem.

## Authorization (separate permissions)

Triage · monitor · implement · push · CI-fix · merge are **distinct grants**. Queue analysis ≠ permission to
edit; **delegation / parallel workers need explicit owner authorization**; push ≠ merge. The autoland
**denylist is always owner-gated at merge** regardless of standing auto-merge. Record granted permissions in
each worker prompt; without one, stop at the boundary and report the exact next action. **Releases / build cuts
are never in scope** — hand to the release skill.

## Owner Decision Briefs

Use autoland's brief format. When several decisions are grouped, give **each item its own brief** (full
clickable URL, plain-language impact, why-now, completed proof, tradeoffs, opinionated recommendation, exact
choices — usually **land · delete · one access step · pick alternative**). Refresh state right before asking;
never re-ask an answered question or present a stale/red item as decision-ready.

## Ledger & log

- Keep one compact cross-item ledger: **Active** (item URL · worker · phase) · **Intervened** (risk + action) ·
  **Needs-owner** (exact decision/access) · **Ignored** (owner exception) · **Done** (merge sha + proof).
- Append dated, high-level entries to `tasks/maintainer-log.md` for meaningful actions/decisions (delegations,
  lands, closes, blockers, owner decisions). Never log secrets or routine polling.

## Reporting

Report meaningful changes, not polling. Always print **full clickable URLs** (never bare `#123`). For
needs-owner items use the brief format — never a bare URL + "land/delete". Maintain a heartbeat (e.g. poll every
~5 min) only when the owner asks for continuous monitoring.

## Related

`autoland` skill (the worker primitive — gates, live proof, denylist, brief format) · the repo's PR-review
policy + prod-write/migration policy.
