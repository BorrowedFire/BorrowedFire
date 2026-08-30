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
   frontmatter keys; INDEX carries its `## Open follow-ups` section and every open follow-up
   lesson appears there. From a Borrowed Fire checkout, `tools/brain-lint.sh <brain-root>` runs
   these checks. Fix each deviation in this run or file it under INDEX.md's needs-review. The
   two ledger deviations are cleared by this run's own steps 7 and 10, and a stale `updated:`
   is cleared by step 9, so record all three and move on rather than fixing or filing them
   here. Fixing a stale `updated:` at this point is the ordering bug step 9 exists to prevent:
   every later append would re-stale it.
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
7. **Sweep queues and archive old logs.** Remove dead `## Queue` claims (released in a log
   bullet, or older than 24h) per the schema's queue sweep. Move log runs past the archival
   threshold to `projects/archive/<name>.md`, archive page first, live page second. Both are
   reconcile-protocol edits: lock held, one page per commit, pushed immediately. Archival also
   respects the schema's 90-day floor, so a page can sit far past the size threshold with
   nothing eligible; that is a no-op, not a deferral.
   **Repair writer tags** (schema §Writer-tag repair) in the same pass: a dated bullet with no
   `[harness@host]` tag gets the tag git establishes for it, which means the introducing
   commit's message carries that tag. A commit author is not evidence, since harnesses on one
   machine share a git identity. If git only suggests a writer, leave the page in needs-review;
   an invented tag makes a bad merge untraceable while looking traceable.
   **Normalize follow-ups** (schema §Follow-ups) in the same pass: on lessons, rewrite a legacy
   Prevention spelling to the canonical form, and rewrite the classification to `encoded` or
   `memory-only` once its prevention has landed. Lessons are not a union-merged path, so a
   digest holding the lock may edit them in place; no other writer may. Project pages stay
   append-only: closure there is a new log bullet, never an edit. Step 10 collects the open set —
   normalizing here only makes that scan cheap.
8. **Distill lessons.** Read log entries across `projects/` and other pages — plus `journal/`
   when it has entries — since the last digest; recurring gotchas or themes get promoted into
   `lessons/` or `notes/` pages — this compounding step is the point of the whole system.
9. **Close resolved follow-ups, then reconcile `updated:`.** Append a closing bullet on each
   project page whose follow-up this run resolved. That includes **mirroring**: when the work
   was finished on another page — a lesson recording the prevention, a different project
   reporting the fix — the follow-up's own page gets the closing bullet here, citing where the
   work landed. A sweep reading that page cannot see the other one, so an unmirrored item
   returns to the ledger every run. Mirroring belongs in this step and not in step 10 for the
   same reason everything else does: it is an append, and an append after the reconcile leaves
   the page stale. Only then bring stale `updated:` fields level with each page's last dated log
   bullet, one page per commit under the reconcile protocol.
   Push the appends first. The reconcile protocol's precondition allows deferring a reconcile
   when the tree has unpushed work, and taking that branch here would end the run with exactly
   the stale fields this step exists to clear. Finish the batch, then reconcile.
   **Reconcile last.** Every append in steps 3, 4, 7, 8, and this one re-stales the `updated:`
   field of the page it touches, so a reconcile performed before them leaves the brain red the
   moment the lock is released. Outbox ingest counts: a capture filed onto a `projects/` page in
   step 3 leaves that page stale like any other append. If a later step still has to append to a
   page, reconcile that page after it, not before — which is exactly what step 11 does for the
   completion bullet.
10. **Refresh `INDEX.md`** (generated-only; rewrite wholesale): per-type counts, notable recent
    pages, active projects, the `## Open follow-ups` ledger, open `needs-review` items. Collect
    the open set **here**, after steps 8 and 9, so a follow-up created or closed by this run
    reaches the ledger in its final state: lessons whose line-start `Prevention:` still marks a
    follow-up in any spelling, plus project log bullets with no later closing bullet. Search
    `projects/` case-insensitively for `follow.?up` **without requiring a colon**: the plural
    header, a capitalized singular, and colon-less phrasings such as "owner follow-up" each hide
    items that the canonical token misses, and all three have. That search is deliberately wide,
    so most of its hits are prose about follow-ups rather than deferrals; read each sentence and
    keep only work still to be done (schema §Follow-ups). Split a plural header into its numbered
    items and judge each one, since a bullet closing one item leaves the rest open. An item whose
    work landed on another page was already mirrored and closed in step 9, so it is simply not in
    the open set here. Write the survivors in the schema
    §Follow-ups format (`(none)` when empty), and tag any entry whose text names no trigger with
    `no-trigger`.
11. **Record the run — only now.** Append the run's own completion bullet, then reconcile that
    one page's `updated:`. This comes after step 10 on purpose: the schema defines a completed
    digest as a pass that *ends* by regenerating INDEX.md, so a completion bullet written any
    earlier claims a completion that may never happen. If step 10 failed, write no completion
    bullet and say the run was incomplete.
12. **Release the lock, then report.** Re-run the step 2 integrity check and report its result.
    **Release the lock unconditionally**, in the same run that took it, whether the pass
    succeeded, failed, or left the brain red — a stranded lock blocks every future digest
    fleet-wide, which is worse than any state this run could leave behind. Report: promoted N ·
    ingested M outbox items · merged K duplicates · fixed J links · swept Q claims · archived A
    bullets · F open follow-ups (G tagged `no-trigger`) · new/updated lessons · whether the
    integrity check ended clean · what needs the owner's eyes.

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
