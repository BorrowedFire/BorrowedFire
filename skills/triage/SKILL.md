---
name: triage
description: Turn a report or idea into a bounded issue draft with evidence and acceptance criteria. Publish it only when filing is authorized.
---

# Triage

The gap between "someone said something is wrong" and "an agent can autonomously fix it" is a
well-shaped issue. `land` and `maintainer` classify items as **Autonomous** only when they are
clear, bounded, and reproducible — this skill manufactures that state. Every report shaped here
raises the fraction of the queue that needs no owner time.

## What a shaped issue contains

1. **One problem.** A report with three problems becomes three issues, cross-linked.
2. **Repro or evidence.** Numbered steps that fail today, or the exact log/crash/screenshot and
   where it came from. If you cannot reproduce it, say what you tried and mark it `needs-repro` —
   don't fake certainty.
3. **Expected vs actual**, one line each.
4. **Blast radius.** Affected surface/users/platforms; is it getting worse; workaround if any.
5. **Acceptance criteria.** The observable checks that make it done — these become `land`'s
   live-proof plan.
6. **Classification + severity.** Autonomous / needs-owner (denylist touch, product call) per
   `land`'s rules; P0–P3 per `qa-audit`'s scale.
7. **Pointers, honestly labeled.** Suspect files/commits from a quick code look, marked as
   hypotheses — never presented as diagnosis.

## Rules

- **Search before filing:** existing issues (open *and* recently closed) and the brain
  (`recall` — was this decided/reported/fixed before?). Duplicate → link and update the original
  instead.
- Quick code reconnaissance is in scope (find the surface, confirm the repro); **fixing is not**.
  The moment you're editing product code, you've left triage — stop and hand off.
- Keep the reporter's words in a quoted block; shape around them, don't overwrite them.
- Ideas (not defects) get the same shaping — problem, who benefits, acceptance criteria — plus a
  brain capture: `remember` to the project's registry page (or `inbox/` if no project exists yet).
- Drafting and filing are distinct scopes. A pasted report or a request to assess it calls for a
  draft. When filing is requested or already authorized, use the affected repository's issue
  tracker and label conventions. Carry that grant forward without another approval question.

## Flow

1. Ingest the raw material (message, log, crash, complaint, idea).
2. Search for duplicates (repo issues + brain).
3. Reproduce or gather evidence; quick code recon for the affected surface.
4. Write the shaped issue (structure above). If filing is authorized, file it and link related
   issues. Otherwise return the draft without publishing it.
5. Report: issue URL or draft, classification, severity, and — if Autonomous — the one-line handoff
   (`maintainer` can now delegate it, or run `land` directly).

## Related

`maintainer` (routes raw items here; consumes shaped ones) · `land` (implements what triage
shaped) · `qa-audit` (its defect log entries are already shaped) · `remember` (ideas and
decisions worth keeping).
