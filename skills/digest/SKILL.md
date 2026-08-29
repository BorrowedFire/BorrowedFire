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
- **Respect the union-merge caveat** (schema §Sync): on `journal/`, `inbox/`, and `projects/`
  paths, never delete `## Log` content and never touch a live append point — the final log
  bullet, and on `projects/` pages the line after `## Queue` — since a concurrent change landing
  in the same hunk duplicates or resurrects lines via union merge. Reconcile stale frontmatter,
  summaries, `## Relations` edges, or settled log bullets only via the schema's **reconcile
  protocol**: clean tree and nothing unpushed, lock held, one page per commit, pushed
  immediately, dropped and redone on rejection (three rejections → drop for good and report).
  Union-merged pages are never stubbed in place during dedup — list a duplicate registry page
  under INDEX.md's needs-review instead. The schema's **queue sweep** (dead claim lines) and
  **log archival** (old bullets moved verbatim, archive-before-remove order) are the two
  sanctioned removals on a union path, both reconcile-protocol edits. Inbox promotion is
  unaffected: whole-file `git mv` (including its archived-stub move), and only for inbox files
  older than 1 day.
- **Never delete content during consolidation** — merge it. A page superseded by a merge becomes a
  stub (`status: archived`) whose body is one wikilink to the survivor, so inbound links keep
  resolving (union-merged pages are never stubbed in place — see the caveat above; inbox
  promotion's whole-file stub move, the queue sweep, and log archival are the exemptions). Git
  history is the true backup; still, prefer archiving over deletion.
- **Merges need evidence.** Dedupe `jane-doe` / `jane-d` only when page content confirms the same
  entity; otherwise tag both `needs-review` and list them in the report.
- **Preserve timelines.** Merging appends log sections in date order, writer tags intact; never
  collapse dated bullets into an undated summary.
- **Bounded pass.** Default budget: eligible inbox + outboxes + link repair + top dedup
  candidates. Leave a `needs-review` trail rather than running unbounded.
- Commit in batches (`brain: digest YYYY-MM-DD [<harness>@<host>]`), push per the sync protocol;
  reconcile-protocol edits are the exception — one page per commit, pushed immediately.

## Flow

1. **Lock.** Per schema. Held → report and stop.
2. **Inventory.** Page counts per type, inbox backlog, pending outboxes, `needs-review` pages,
   days since the last completed digest (INDEX.md's `Last generated` line). Check integrity while
   counting: every page has frontmatter whose `type` matches its directory plus `created`,
   `updated`, and `status`; no `updated:` is older than the page's last dated log bullet; INDEX
   counts match the tree; no dead `## Queue` claims; every wikilink resolves; no duplicated
   frontmatter keys. From a Borrowed Fire checkout, `tools/brain-lint.sh <brain-root>` runs these
   checks. Fix each deviation in this run or file it under INDEX.md's needs-review.
3. **Ingest outboxes.** Any `.brain-outbox/` files in repos you can see, and fenced
   `BRAIN CAPTURE` blocks the owner has queued: file them as normal captures. Delete only the
   exact local-only source file after its capture commit has pushed successfully; never delete
   the outbox directory, another item, or a file whose push is pending.
4. **Promote inbox** (files >1 day old only). Classify → whole-file `git mv` into the typed page
   location, or append its content to an existing page and `git mv` the inbox file to an archived
   stub. Unclear items stay, tagged `needs-review` with a note on what's missing.
5. **Dedupe entities.** Near-duplicate slugs/titles per entity directory; merge with evidence
   (rules above); repoint inbound wikilinks (`rg -l '\[\[<old-slug>\]\]'` → edit).
6. **Repair the graph.** Dangling wikilinks (`rg -o '\[\[[^]]+\]\]'` targets with no file):
   obvious typo → fix; missing entity mentioned ≥2 times → stub page; else log it.
7. **Sweep queues, archive old logs, reconcile frontmatter.** Remove dead `## Queue` claims
   (released in a log bullet, or older than 24h) per the schema's queue sweep. Move log runs past
   the archival threshold to `projects/archive/<name>.md`, archive page first, live page second.
   Bring stale `updated:` fields level with each page's last dated log bullet. All of these are
   reconcile-protocol edits: lock held, one page per commit, pushed immediately.
   **Sweep follow-ups** (schema §Follow-ups) in the same pass: collect the open set — lessons
   whose line-start ``Prevention: `follow-up`.`` still stands, and project log bullets carrying
   `follow-up:` (legacy spellings included) with no later closing bullet — for the INDEX refresh
   in step 9, and tag any entry whose text names no trigger with `no-trigger`. When a lesson's
   prevention has since landed, rewrite its Prevention line to `encoded` (lessons are not union
   paths). Project pages stay append-only: closure there is a new log bullet, never an edit.
8. **Distill lessons.** Read log entries across `projects/` and other pages — plus `journal/`
   when it has entries — since the last digest; recurring gotchas or themes get promoted into
   `lessons/` or `notes/` pages — this compounding step is the point of the whole system.
9. **Refresh `INDEX.md`** (generated-only; rewrite wholesale): per-type counts, notable recent
   pages, active projects, the `## Open follow-ups` section from step 7's sweep (schema
   §Follow-ups format; `(none)` when empty), open `needs-review` items.
10. **Release the lock. Commit + report:** promoted N · ingested M outbox items · merged K
    duplicates · fixed J links · swept Q claims · archived A bullets · F open follow-ups
    (G tagged `no-trigger`) · new/updated lessons · what needs the owner's eyes.

## Scheduling

Weekly, or when inbox exceeds ~15 items. Only a full pass that regenerates INDEX.md counts as a
completed digest for that cadence (schema §Digest lock); a scoped reconcile under the lock does
not reset the clock. Claude Code: `/loop /digest` or a cron job; other harnesses: their
scheduled-task mechanism. Digest is safe to run unattended — locked, non-destructive, atomic
commits. A direct or standalone scheduled digest always reports to the owner.
When `reflect` invokes digest inside its nightly fleet pass, report material changes or actionable
problems; a clean no-op remains in scheduler run history without notifying the owner.

## Related

`remember` (capture + schema) · `recall` (its findings feed steps 5–6) · real gbrain's dream cycle
is the scaled-up version of this skill (schema §Upgrade path).
