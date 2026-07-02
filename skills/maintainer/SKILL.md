---
name: maintainer
description: Fleet-aware control-plane orchestrator that keeps repos green with minimal owner involvement — read the brain's project registry, scan each repo's queue (open PRs + issues + CI), classify every item, delegate autonomous ones to `land` workers, drive needs-owner items to decision-ready briefs, and keep a single ledger. Use for "/maintainer", "maintainer mode", "run the queue", "keep the repo green", "work the backlog", "run the fleet", or continuous monitoring. It DELEGATES heavy work — it does not implement in this thread. Routing: dependency-update PRs → `deps`; raw bug reports/ideas needing shaping → `triage`; NOT for landing one PR yourself (`land`), deploys (`ship`), or store builds (`store-release`).
---

# Maintainer

A **control plane**: inspect, classify, delegate, monitor, and surface decision-ready asks. Put
substantial investigation / implementation / review / proof / landing into **workers** (`land`
runs / subagents) and keep *this* thread lightweight, monitoring by reading current state. The
aim: turn a backlog into "the owner answers a few one-tap decisions," nothing more.

## Scope & the registry

- **Registry = the brain's `projects/` directory** (see `remember`'s `references/brain-schema.md`
  §Project registry). Each page's frontmatter sets that repo's rules: `autonomy`
  (full/gated/read-only), `review_bot`, `denylist_extra`, `status`. Fleet mode works the active
  registry; single-repo mode (no brain, or the owner scoped the run) works the current repo with
  conservative defaults (`autonomy: gated`, `review_bot: codex`).
- Registry rules are **read, never improvised** — a repo without a registry page gets the
  conservative defaults and a note in the report suggesting `bootstrap` to register it.
- Exclude **nothing** as "ignored" unless the owner explicitly named it. Ordinary draft / stale /
  hard / platform-specific items are queue work, not ignored.

## Capability preflight (run before anything)

Adapt to what this harness can actually reach — never assume:

1. `gh auth status` succeeds → **full mode** (delegation, PR ops, `@codex review` polling).
2. Else GitHub MCP tools available (`get_me` works) → **MCP mode**: reads, PRs, comments via MCP;
   workers must run where `gh` exists, or items become decision-ready briefs.
3. Neither → **read-only mode**: classify + brief only; delegate nothing; say so in the report.

## Tier routing (fleet cost discipline)

Classification, verdicts, and owner briefs are **judgment-tier** work (this thread). Mechanical
volume work (first-pass implementation, bulk edits, summarization) belongs on the **local/volume
tier** when the fleet has one. Endpoints, caps, and the paid-task whitelist are instance config —
the brain's `config/fleet.md` — never hardcoded in skills. No fleet config → run everything in the
current harness and note it.

## Operating model

1. **Scan.** Per active registry repo: open PRs, open issues, CI status, stale branches, latest
   release / unreleased changes. Build a one-line-per-item ledger.
2. **Prioritize** (work the queue in this order):
   1. Red CI on a default branch (broken main blocks everything else).
   2. PRs nearest merge (review-clean, needs one push).
   3. Oldest autonomous issues.
   4. Needs-owner prep (drive to decision-ready).
3. **Classify** every item (re-classify as state changes):
   - **Autonomous** — clear, bounded, reproducible, with a real **live-proof path**, and the
     registry allows it (`autonomy: full|gated`).
   - **Needs-owner** — product choice, security/privacy/irreversible call, missing
     credential/access, no live proof, `autonomy: read-only`, or it hits the denylist
     (`land`'s `references/denylist.md` + the page's `denylist_extra`).
   - **Ignored** — only an explicit owner instruction creates this.
4. **Claim before delegating** (fleet-safe): append to the project page's `## Queue` —
   `- claimed <item-url> by maintainer [<harness>@<host>] <ISO timestamp>` — commit, push per the
   brain sync protocol. Push rejected → pull, re-read claims, **skip items claimed by others**.
   Claims older than 24h are stale and may be re-claimed. One maintainer at a time is the norm;
   the claim protocol is the safety net, not an invitation to run several.
5. **Delegate** (only when delegation is authorized — see Authorization):
   - **Autonomous PR** → fire a `land` worker on its branch.
   - **Autonomous issue (no PR)** → a worker investigates root cause, implements the best
     **bounded** candidate on a branch, opens a PR, then runs `land`.
   - **Dependency-update PRs** → route through `deps`. **Raw/unshaped reports** → `triage` first.
   - One item per branch; keep a repo's work in its own worker. **Workers may not sub-delegate.**
6. **Drive needs-owner items to the decision-ready boundary** *before* asking — implement, fix,
   test, live-prove, review-to-clean, CI-green — then emit **one Owner Decision Brief** (land's
   format). For a reversible product call, pick a safe default, ship it in the PR, and note the
   alternative rather than blocking.
7. **Monitor** (below). Continue until: every autonomous item is **merged with proof**, every
   needs-owner item is a **decision-ready brief**, the effective queue is empty, or CI is green
   with a documented reason no work remains. Release claims for anything you stop working.

## Delegation model

- Bound worker concurrency (default **≤4** at once). Each worker prompt: the exact item + "follow
  the `land` skill for branch/PR X; do not sub-delegate; stop at the last authorized boundary and
  report." Pass the granted permissions explicitly.
- Monitor via worker-completion signals + reading PR/branch/CI state — **not** by re-doing the
  work here.
- Only this orchestrator creates/assigns/steers workers. Don't delegate triage or worker
  management.

## Monitoring protocol

Assume state may have moved since your last look. **Before steering any worker, read its latest
state + the current PR/CI.** Let an actively-progressing worker run — intervene only when evidence
shows: it reports a **blocker**, it's **idle/finished** and needs the next item, **repeated
failure with a concrete fix available**, or **wrong item / denylist breach / destructive action /
risk / direct conflict with the owner's latest word**. Don't restate the task, add speculative
requirements, or **raise the proof bar mid-flight** — apply land's live-proof gate from the start;
never downgrade missing live proof to a "release-only" problem.

## Authorization (separate permissions)

Triage · monitor · implement · push · CI-fix · merge are **distinct grants**. Queue analysis ≠
permission to edit; **delegation / parallel workers need explicit owner authorization**; push ≠
merge. The denylist is **always owner-gated at merge** regardless of standing auto-merge. Record
granted permissions in each worker prompt; without one, stop at the boundary and report the exact
next action. **Deploys and releases/build cuts are never in scope** — `ship` / `store-release`.

## Owner Decision Briefs

Use land's brief format. When several decisions are grouped, give **each item its own brief**
(full clickable URL, plain-language impact, why-now, completed proof, tradeoffs, opinionated
recommendation, exact choices — usually **land · delete · one access step · pick alternative**).
Refresh state right before asking; never re-ask an answered question or present a stale/red item
as decision-ready.

## Ledger & log

- Keep one compact cross-item ledger **in the running report** (this thread): **Active** (item URL
  · worker · phase) · **Intervened** (risk + action) · **Needs-owner** (exact decision/access) ·
  **Ignored** (owner exception) · **Done** (merge sha + proof).
- Durable trail: append dated log lines to each project's registry page (`## Log`) for meaningful
  actions (delegations, lands, closes, blockers, owner decisions), per the brain sync protocol.
  Never log secrets or routine polling.

## Reporting

Report meaningful changes, not polling. Always print **full clickable URLs** (never bare `#123`).
For needs-owner items use the brief format — never a bare URL + "land/delete". Maintain a
heartbeat (e.g. poll every ~5 min) only when the owner asks for continuous monitoring.

## Related

`land` (the worker primitive — gates, live proof, denylist, brief format) · `deps` / `triage`
(routed specialists) · `remember`/`recall` (registry + lessons) · `bootstrap` (registering new
repos).
