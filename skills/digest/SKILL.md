---
name: digest
description: Consolidate the brain — the "dream cycle" for the git-backed memory. Promote inbox captures into typed pages, ingest outboxes, dedupe entities, repair wikilinks, distill lessons, refresh INDEX.md, and report brain health. Use when the user says "/digest", "digest", "process my inbox", "consolidate my brain", "clean up my notes", "run the dream cycle", on a schedule (weekly cron or /loop is a good default), or when `recall` reports contradictions/duplicates. NOT for capturing new material (`remember`) or answering questions (`recall`).
---

# Digest

Capture (`remember`) is optimized to be fast and lossless; digest is where understanding happens —
raw signals become structured, deduplicated, linked knowledge. This is the **only** skill allowed
to restructure or merge existing pages, and only one digest runs fleet-wide at a time. Schema
authority (layout, sync protocol, lock, union-merge caveat): `remember`'s
`references/brain-schema.md`.

## Rules

- **Take the digest lock first** (schema §Digest lock: push-wins claim on `.locks/digest.md`,
  committer-date staleness at 2h, release in the same run even on failure). No lock, no
  restructuring.
- **Respect the union-merge caveat** (schema §Sync): never edit `journal/`, `inbox/`, or
  `projects/` files in place — in-flight appends from other writers would silently resurrect your
  deletions. Inbox promotion is whole-file `git mv`, and only for inbox files older than 1 day.
- **Never delete content during consolidation** — merge it. A page superseded by a merge becomes a
  stub (`status: archived`) whose body is one wikilink to the survivor, so inbound links keep
  resolving. Git history is the true backup; still, prefer archiving over deletion.
- **Merges need evidence.** Dedupe `jane-doe` / `jane-d` only when page content confirms the same
  entity; otherwise tag both `needs-review` and list them in the report.
- **Preserve timelines.** Merging appends log sections in date order, writer tags intact; never
  collapse dated bullets into an undated summary.
- **Bounded pass.** Default budget: eligible inbox + outboxes + link repair + top dedup
  candidates. Leave a `needs-review` trail rather than running unbounded.
- Commit in batches (`brain: digest YYYY-MM-DD [<harness>@<host>]`), push per the sync protocol.

## Flow

1. **Lock.** Per schema. Held → report and stop.
2. **Inventory.** Page counts per type, inbox backlog, pending outboxes, `needs-review` pages,
   days since last digest (git log).
3. **Ingest outboxes.** Any `.brain-outbox/` files in repos you can see, and fenced
   `BRAIN CAPTURE` blocks the owner has queued: file them as normal captures, then delete the
   outbox files.
4. **Promote inbox** (files >1 day old only). Classify → whole-file `git mv` into the typed page
   location, or append its content to an existing page and `git mv` the inbox file to an archived
   stub. Unclear items stay, tagged `needs-review` with a note on what's missing.
5. **Dedupe entities.** Near-duplicate slugs/titles per entity directory; merge with evidence
   (rules above); repoint inbound wikilinks (`rg -l '\[\[<old-slug>\]\]'` → edit).
6. **Repair the graph.** Dangling wikilinks (`rg -o '\[\[[^]]+\]\]'` targets with no file):
   obvious typo → fix; missing entity mentioned ≥2 times → stub page; else log it.
7. **Distill lessons.** Read `journal/` and log entries since the last digest; recurring gotchas
   or themes get promoted into `lessons/` or `notes/` pages — this compounding step is the point
   of the whole system.
8. **Refresh `INDEX.md`** (generated-only; rewrite wholesale): per-type counts, notable recent
   pages, active projects, open `needs-review` items.
9. **Release the lock. Commit + report:** promoted N · ingested M outbox items · merged K
   duplicates · fixed J links · new/updated lessons · what needs the owner's eyes.

## Scheduling

Weekly, or when inbox exceeds ~15 items. Claude Code: `/loop /digest` or a cron job; other
harnesses: their scheduled-task mechanism. Digest is safe to run unattended — locked,
non-deleting, atomic commits — but the report should always reach the owner.

## Related

`remember` (capture + schema) · `recall` (its findings feed steps 5–6) · real gbrain's dream cycle
is the scaled-up version of this skill (schema §Upgrade path).
