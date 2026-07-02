---
name: remember
description: Capture anything worth keeping into the brain — a private, git-backed markdown memory shared by every agent and machine. Use when the user says "/remember", "remember this", "note this down", "log this decision", "add to my brain", "save this for later", "capture this", after a meeting/call recap, when a durable decision is made, or when another skill (land, maintainer, rollback, qa-audit, bootstrap) writes back a lesson, gotcha, or registry entry. Write-side of the memory system; `recall` reads, `digest` consolidates. NOT for repo code/docs changes (edit the repo) and NOT for secrets (never stored).
---

# Remember

Turn a passing signal — a person met, a decision made, a gotcha hit, an idea — into a durable,
typed markdown page in the brain, committed and pushed so every other agent and machine sees it.
Capture must be **fast, safe, and lossless**; understanding can wait for `digest`.

`references/brain-schema.md` is authoritative for the brain location, directory tree, page format,
registry frontmatter, sync protocol, and degradation ladder. Do not invent conventions here.
(`recall` and `digest` also depend on that file; the three install together.)

## Rules

- **Never lose the signal.** If typing/filing is uncertain, write
  `inbox/YYYY-MM-DD-<slug>-<writer>.md` verbatim and move on — `digest` promotes inbox items
  later. A misfiled capture is recoverable; a skipped capture is gone. If the brain is unreachable,
  use the schema's degradation ladder (local-only, never-committed `.brain-outbox/` in the working
  repo; in ephemeral environments a fenced `BRAIN CAPTURE` block instead) — never silently drop,
  and never commit private memory to a product repo.
- **Follow the sync protocol exactly** (schema §Sync): pull-rebase before writing, commit per
  capture with the writer tag, push immediately, bounded retries, "push pending" report if the
  push cannot land. Never force-push the brain.
- **Check before creating an entity page.** One entity, one page: search existing slugs first. If
  a page exists, append a dated `## Log` bullet (with writer tag) and bump `updated:`; never
  rewrite prior content — only `digest` restructures.
- **Union-merged paths are append-only, frontmatter included.** On `journal/`, `inbox/`, and
  `projects/` pages, append your line and touch *nothing else* — do not bump `updated:` or edit
  any frontmatter (two concurrent frontmatter edits on a `merge=union` path can concatenate into
  corrupt YAML). `digest` reconciles `updated:` under its lock.
- **Link while you write.** Mention a known person/company/project → wikilink it. Stated relations
  ("Jane works at Acme") go under `## Relations` with a typed edge.
- **Keep the user's words** in the log entry; add your own summary only in addition.
- **No secrets in the brain**, ever. Reference where a credential lives; never its value.

## Flow

1. Resolve the brain root (schema §Locating). None found → offer once to initialize; if declined
   or impossible, use the degradation ladder.
2. Classify the signal → page type by directory prefix. Confident: write the typed page. Not
   confident: `inbox/`.
3. Write or append per schema: frontmatter, summary at top, dated `## Log` bullet with writer tag,
   `## Relations` for stated edges, wikilinks for mentions.
4. Cross-append when it clarifies: a decision affecting a project also gets one log line on the
   project page linking to the decision page. Substance lives in exactly one place.
5. Sync per protocol. Confirm to the user: page path + one-line summary of what was stored.

## Capture triggers worth acting on proactively

When one of these happens in any session, offer a one-line capture (never block work on it):

- A **decision** with a reason → `decisions/`.
- A **gotcha / false-positive pattern / postmortem learning** → `lessons/`, wikilinked to its
  `[[projects/<repo>]]` page. This is the write-back target named by `land`, `maintainer`,
  `rollback`, and `qa-audit` — cross-repo compounding is the point of the system.
- A **person or company** newly relevant → `people/` / `companies/`.
- A **meeting or call** recap → `meetings/`, with attendee wikilinks.
- A **new repo/app/idea** or a project status change → its `projects/` registry page.

## Batch mode (control-plane bridge)

An always-on assistant harness with its own session-local notes (e.g. an OpenClaw workspace's
daily notes) should run `remember` as a nightly batch: scan notes since the last batch, capture
the durable items (decisions, people, lessons — not chit-chat) into the brain, and record the
high-water mark in `notes/<harness>-ingest.md` frontmatter (`last_ingested:`). Push-based: each
machine pushes its own memory; `digest` never reads other machines' workspaces.

## Related

`recall` (read side) · `digest` (consolidation) · schema: `references/brain-schema.md`.
