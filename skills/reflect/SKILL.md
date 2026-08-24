---
name: reflect
description: Turn completed work into durable, verified improvement in Prometheus. Use when the user says "/reflect", "reflect on this", or "capture what we learned". Otherwise run automatically at the end of every substantive task or meaningful checkpoint—implementation, diagnosis, review, merge, release, rollback, planning decision, or owner correction—and in scheduled fleet-maintenance mode. Extract reusable lessons, decisions, owner preferences, and exact-current project-status changes; deduplicate against the brain; persist them through `remember`; and let `digest` consolidate recurring patterns. No-op when nothing durable changed. NOT for speculative conclusions, routine success logs, secrets, autonomous product-repo edits, or self-modifying skills without normal review.
---

# Reflect

Make completed work improve the next run. This is Prometheus's automatic learning pass: inspect
what was actually established, retain only durable signal, connect it to prevention, and write it
through the existing memory protocol. A clean no-op is a successful result.

`remember` remains the write authority, `digest` remains the only restructurer, and
`remember/references/brain-schema.md` remains the schema authority. Read
`references/cycle-contract.md` when running in scheduled fleet mode or configuring automation.

## Non-negotiable boundaries

- **Run without a user prompt** after a substantive task reaches a stable checkpoint and before
  the final honesty audit. Skip trivial questions, formatting-only work, and sessions with no
  established result.
- **Evidence before memory.** Current source, tests, review findings, production proof, or an
  explicit owner decision may establish a fact. A guess, stale handoff, historical artifact,
  unverified model claim, or unresolved possibility may not.
- **Signal over exhaust.** Do not log routine commands, every changed file, generic advice,
  successful happy paths with no reusable insight, or a duplicate already captured.
- **No silent authority expansion.** Learning may write the private brain. It may not modify a
  product repo, deployment, account, store, credential, skill, doctrine, or scheduler unless that
  change is already authorized by the active task. The sole fleet-mode exception is removing one
  exact local-only `.brain-outbox/<file>` after its content is committed and pushed to Prometheus;
  never remove the directory, another outbox item, or an item whose push is pending. Otherwise
  record a bounded follow-up.
- **No autonomous self-rewrite.** A recurring pattern may justify a proposed skill/doctrine/test
  change, but that change follows the normal branch, review, and landing workflow.
- **Never store secrets or private brain content in a product repo.** If Prometheus is unavailable,
  use `remember`'s repo-local degradation/outbox path only when the active task already authorized
  writes to that exact repository. Otherwise keep the pending capture in output only, report that
  it was not persisted, and do not create or modify a product-repo outbox.

## Session mode

Run this sequence once at each meaningful terminal checkpoint:

1. **Pin the outcome.** State the exact task checkpoint and the evidence that makes it current.
   Separate completed, rejected, deferred, blocked, and unverified claims.
2. **Build a candidate delta.** Consider only:
   - a decision and its reason;
   - a surprising failure, root cause, reliable diagnostic, or false-positive pattern;
   - an owner correction or durable workflow preference;
   - an exact-current project status, release state, blocker, or next gate;
   - a recurring weakness that needs a test, runbook, skill, doctrine, or product fix.
3. **Search before writing.** Use `recall` or targeted brain search for the project and candidate
   lesson/decision. Append to an existing canonical page when it already covers the fact.
4. **Apply the durability test.** Capture only when the candidate is verified, likely useful in a
   later session, materially changes how work should proceed, and is not already represented.
5. **Close the prevention loop.** Classify each retained learning as:
   - `encoded` — already enforced by a test, runbook, skill, doctrine, or product invariant;
   - `memory-only` — durable context where automation would be disproportionate;
   - `follow-up` — prevention is warranted but outside current authority or scope.
   Record the existing enforcement or the smallest concrete follow-up; never claim prevention
   from documentation or memory alone when a mechanical guard is required.
6. **Persist through `remember`.** Lessons go to `lessons/`, decisions to `decisions/`, durable
   owner preferences to the existing owner/config page, and status deltas append to the matching
   `projects/` page. Preserve writer tags, union-path append-only rules, and sync behavior.
7. **Return a compact result.** Report `captured`, `updated`, `deduplicated`, `follow-up`, or
   `no durable delta`. If push is pending or the brain is unreachable, say so explicitly without
   obscuring the task's real completion state.

## Fleet mode

An always-on harness runs the same quality bar over durable notes and outboxes visible on its own
host. It must not pretend to read another machine's private session history.

1. Resolve Prometheus and sync it using the schema protocol. If it is unavailable, stop and report
   the failure; fleet mode never creates a fallback outbox in a product repository.
2. Derive a controller-binding watermark. For OpenClaw use
   `notes/openclaw-<host>-<agent>-<workspace>-<binding-hash>-ingest.md`, where the hash covers the
   stable full host/machine identity, agent, canonical workspace path, and effective OpenClaw
   state directory, active canonical-or-legacy config path, and profile identity.
   Lowercase text components, replace non-alphanumeric runs with `-`, and refuse a blank component.
   Other harnesses must include an equivalent host plus workspace/session-source identity. Read
   only that binding's high-water mark. If it does not exist, capture the UTC cycle-start time as a
   prospective baseline: do not backfill pre-existing session notes, but still inspect all pending
   `.brain-outbox/` items and exact-current project status. Historical note backfill requires a
   separate owner-authorized bounded migration.
3. Inspect only new harness-local notes, pending `.brain-outbox/` captures in explicitly
   registered/accessible repos, and project-status evidence created since that mark. An outbox
   source file may be removed only after its exact capture is durably committed and pushed.
4. Run Session mode over those deltas, then advance the high-water mark only after captures are
   durably committed. Never skip failed or ambiguous inputs by moving the mark past them.
5. Run `digest` only when its cadence/backlog threshold is due. Its fleet lock decides whether
   this worker may restructure.
6. Stay quiet on routine success or no-op. A due digest that materially changes Prometheus sends
   one concise summary; also surface a push/sync failure, conflicting evidence, an owner decision,
   or a concrete prevention follow-up.

## What good learning looks like

- “The build failed” is noise. “The release wrapper accepted an expired provisioning profile;
  preflight must validate profile expiry before archive” is a lesson with a prevention target.
- “PR merged” is usually noise. “Project X is now on version 2.3 build 41 in TestFlight; production
  remains build 39” is a useful, source-pinned status delta.
- “Reviewer was wrong” is unsupported. “Finding Y is a false positive because invariant Z is
  enforced by test A and unchanged consumer B” is reusable when the evidence is exact-current.

## Related

`recall` (preflight and dedupe) · `remember` (authoritative capture) · `digest` (consolidation) ·
`session-closeout` (honesty audit after this pass).
