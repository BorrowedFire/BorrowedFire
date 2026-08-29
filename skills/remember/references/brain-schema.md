# Brain Schema (authoritative)

The single source of truth for how the Borrowed Fire brain works. `remember`, `recall`, `digest`,
and any skill that writes lessons or reads the project registry follow this file. Design lineage:
Garry Tan's gbrain — **the brain is a git repo of markdown; git is authoritative; everything else
is a cache.** The page format is deliberately gbrain-conformant (typed directories, YAML
frontmatter, wikilinks), so the tree can later be mounted by real gbrain
(github.com/garrytan/gbrain) without migration.

The brain repo is **private**. The skills that operate on it are public; the memory never is.

## Locating the brain

Resolution order (first hit wins):

1. `$PROMETHEUS_DIR` environment variable.
2. The path in `~/.config/borrowedfire/brain` (a one-line pointer file written by `install.sh`).
3. `~/prometheus` if it exists and is a git repo.
4. None found → offer once to initialize (clone the private brain repo, or bootstrap from
   `prometheus-template/`). Never scatter memory files outside a brain root or an outbox
   (see Degradation ladder). A repo-local brain is an explicit owner opt-in for a single private
   repo, never a default; cross-repo memory always goes to the brain.

## Directory tree (page type = path prefix)

```
prometheus/
  INDEX.md          # generated map of contents — digest owns it (see Sync)
  config/           # instance config: fleet.md (tier endpoints, caps), owner prefs
  inbox/            # raw captures, unprocessed    inbox/YYYY-MM-DD-<slug>-<writer>.md
  journal/          # daily log, one file per day  journal/YYYY-MM-DD.md
  people/           # one page per person          people/<name-kebab>.md
  companies/        # one page per org             companies/<name-kebab>.md
  projects/         # registry: one page per repo/app/idea   projects/<name-kebab>.md
  meetings/         # one page per meeting/call    meetings/YYYY-MM-DD-<topic>.md
  decisions/        # one page per durable decision decisions/YYYY-MM-DD-<topic>.md
  lessons/          # gotchas + postmortem learnings lessons/<topic-kebab>.md
  notes/            # evergreen reference notes    notes/<topic-kebab>.md
  .locks/           # cooperative locks (digest)
  .gitattributes    # union-merge rules — required, ships with the template
```

New type directories are added only by `digest` (consolidation), never ad hoc during capture —
unknown material goes to `inbox/`.

## Page format

```markdown
---
type: person            # matches directory prefix
created: 2026-07-02
updated: 2026-07-02
tags: [investor, ios]
source: meeting          # meeting | chat | repo | email | web | agent-run | ...
status: active           # active | archived | needs-review
---

# Jane Doe

One-paragraph summary at the top; details below.

## Relations
- works_at [[companies/acme]]
- advises [[projects/example-app]]

## Log
- 2026-07-02: met at a demo day; interested in local-first apps
  ([[meetings/2026-07-02-demo-day]]) [claude-code@laptop]
```

Rules:

- **Wikilinks are the graph.** `[[people/jane-doe]]` is an edge; `## Relations` lines
  (`- <edge_type> [[target]]`) give typed, greppable edges (gbrain edge types: `works_at`,
  `founded`, `invested_in`, `attended`, `advises`, `mentions`). The graph is recoverable with
  `rg -o '\[\[[^]]+\]\]'`; backlinks are queries: `rg -l '\[\[people/jane-doe\]\]'`.
- **Append, don't rewrite.** Dated `## Log` bullets preserve the timeline. Only `digest`
  restructures or merges pages; every other writer appends.
- **Every log bullet ends with a writer tag** `[<harness>@<host>]` (e.g. `[openclaw@controlnode]`)
  so a bad merge can be traced. When the machine is listed in `config/fleet.md` §Writer
  identities, use that exact spelling. Otherwise pick one stable lowercase host name and keep it.
  Spelling drift (`Host`, `host.local`, `host-2`) breaks audit greps and the fleet-cycle
  watermark binding.
- **One entity, one page.** Search existing slugs before creating; knowingly duplicate pages are
  never created — near-misses are `digest`'s dedup job.
- **No secrets, ever.** Keys, tokens, passwords never enter the brain — reference where a
  credential lives, never its value.

## Project registry (`projects/`)

Project pages double as the fleet control plane that `maintainer` reads. Registry frontmatter, in
addition to the standard fields:

```yaml
type: project
repo: <owner>/<name>        # omit for ideas without a repo yet
default_branch: main
autonomy: gated             # full | gated | read-only
review_bot: codex           # codex | none
denylist_extra: []          # repo-specific additions to land's denylist
```

Body sections: `## Queue` (maintainer's claim lines), `## Log` (status changes, lands, decisions).

## Follow-ups (the deferred-work ledger)

A follow-up is prevention or operational work the current task could not do: warranted, but
outside its authority or scope. `reflect` produces them; this section owns their format so
deferred work stays greppable and cannot rot into "later means never".

- **One spelling.** A new follow-up carries the lowercase token `follow-up:` plus the smallest
  concrete action and the condition that triggers it. The sweep still reads legacy spellings
  ("Open follow-up", "OPEN FOLLOW-UP", "owner follow-up") in old bullets; new writes use the
  token.
- **Where they live.** A lesson records prevention debt as a line-start
  ``Prevention: `follow-up`.`` line whose paragraph names the action and the trigger. A project
  page records operational debt as a dated log bullet containing `follow-up:`.
- **What closes one.** On a lesson, `digest` rewrites the Prevention line to `encoded` or
  `memory-only` once the prevention lands (lessons are not union paths, so a locked digest may
  edit them). On a project page, closure is a later dated log bullet that names the follow-up
  and states it is done or superseded — the queue-claim release pattern; the original bullet is
  never edited.
- **The ledger.** `INDEX.md` carries a generated `## Open follow-ups` section: one line per open
  item, `- [<title>](<page path>): <action> (since <date>)`, or `(none)` when the set is empty.
  Keep the link target exact — `brain-lint` matches the delimited form `](<page path>)`.
  `digest` owns the section (its sweep builds it); `recall` and `maintainer` read it as the
  deferred-work ledger. An entry whose text names no trigger gets a trailing `no-trigger` tag —
  those are the ones that rot first, and the digest report calls them out.

## Sync protocol (multi-writer, multi-machine)

Several agents on several machines write concurrently. The protocol is git-native — no server.

**Write sequence (every writer, every capture):**

1. `git pull --rebase` (skip if no remote).
2. Write/append the page. Commit: `brain: capture <path> [<harness>@<host>]`.
3. `git push`. On rejection: `git pull --rebase` and retry, up to 3 times.
4. Still rejected after 3: **stop retrying, leave the commit local**, report "capture saved
   locally, push pending" — it syncs on the next brain operation. Never write the same capture to
   an outbox after committing (that duplicates it). Never force-push; never rewrite brain history.

**Structural conflict avoidance:**

- `.gitattributes` (ships in the template, required):

  ```
  journal/*.md merge=union
  inbox/*.md merge=union
  projects/*.md merge=union
  ```

  Append-only files from concurrent writers then merge cleanly. `projects/*` is included because
  `## Queue` claims and `## Log` appends are the highest-contention writes in the fleet.
- Inbox filenames carry a writer suffix — `inbox/2026-07-02-idea-openclaw.md` — so parallel
  captures are distinct files that can never conflict.
- `INDEX.md` is **generated-only**: digest rewrites it wholesale. On any conflict touching
  INDEX.md, take either side and regenerate; never hand-merge it.

**Rebase conflict rule (any writer, unattended-safe):** if `git pull --rebase` stops on a textual
conflict the union rules didn't absorb: `git rebase --abort`, save your uncommitted/new material to
the degradation ladder below, and report the conflict — never leave a brain clone mid-rebase and
never guess a hand-merge of someone else's content.

**Union-merge caveat (binding on ALL writers):** union merge takes both sides of a conflicting
hunk, so two writers editing the same line (e.g. both bumping `updated:`) concatenate into
duplicated, corrupt YAML, and a rewrite that lands in the same hunk as another writer's in-flight
append resurrects the lines it deleted. Therefore on `journal/`, `inbox/`, and `projects/` paths
every writer is **strictly append-only, frontmatter included**: append your line, touch nothing
else. Inbox promotion is **whole-file move** (`git mv` to the destination page or an `archive/`
stub), and only for inbox files **older than 1 day** — the writer-suffix naming makes a moved
file's path unique, and the age horizon keeps it clear of in-flight appends.

**Reconcile protocol (digest-only exception to the caveat):** stale frontmatter (`updated:`),
stale summary paragraphs, and broken wikilinks in settled content on union-merged pages are fixed
only by `digest`, under the digest lock, one page per commit:

0. Precondition: clean tree and nothing unpushed (`git status --porcelain` empty,
   `git log @{u}..` empty; with no remote, porcelain-empty alone). Otherwise push or finish the
   batch first — or defer the reconcile.
1. `git pull --rebase` immediately before the edit.
2. Touch only settled content — frontmatter, the summary above `## Relations`/`## Log`,
   `## Relations` edge lines, an existing log bullet needing link repair, or a dead `## Queue`
   claim line (see the queue sweep below). Never delete a log bullet in place — the log archival
   below is the one sanctioned relocation — and never touch a **live append point**: the final
   log bullet (end of file), on `projects/` pages the line after the last `## Queue` claim where
   new claims land — and on any union page, the file's last content line, whatever it is. The
   queue sweep is exempt from the append-point rule for dead claim lines only; drop-and-redo
   (step 4) is what makes that exemption safe.
3. Commit the edit alone — `brain: digest reconcile <path> [<harness>@<host>]` — and `git push`
   immediately, before any other digest work.
4. On push rejection, drop the edit (`git reset --hard HEAD~1`), `git pull --rebase`, and redo it
   from the fresh state — never carry an in-place union-path edit through a rebase. After three
   rejections: drop the edit for good, record it as a dated bullet on the day's `journal/` page
   (append-only, durable) plus INDEX.md's needs-review list, and report. Never leave a reconcile
   commit unpushed.

A stranded unpushed `brain: digest reconcile` commit found at the start of any brain operation
that will `git pull --rebase` (captures, digest runs, lock claims) is dropped before pulling —
`git reset --hard @{u}` when it is the **only** unpushed commit; anything else unpushed beneath
it → abort and report instead. `recall` is exempt: its `--ff-only` pull cannot rebase a stranded
commit — it fails, and recall already reports the brain as stale. Reconcile edits are disposable
by design, and rebasing one does not stop on the conflict: union absorbs it and corrupts
silently. Duplicated
frontmatter keys found on any pull are union-merge artifacts; digest repairs them under this same
protocol. Union-merged pages are never stubbed in place during dedup or restructured wholesale —
a duplicate registry page is listed under INDEX.md's needs-review instead. Inbox promotion's
archived stub is different and stays as-is: a sanctioned whole-file `git mv` off the live path,
per the caveat above.

**Queue sweep (digest-only):** a `## Queue` claim line is **dead** once a later `## Log` bullet
releases it, or once it is older than 24 hours (the maintainer claim TTL). digest removes dead
claim lines under this same reconcile protocol — lock held, one page per commit, pushed
immediately, dropped and redone on rejection. No other writer removes a claim line, its own
included; `maintainer` releases a claim by appending a `## Log` bullet. Residual union risk: a
concurrent claim append that rebases over the sweep can resurrect a removed line (union keeps
both sides). The resurrected line is still dead by its own timestamp, readers ignore it, and the
next sweep removes it again — the failure mode is clutter, not loss.

**Log archival (digest-only):** when a `projects/` page's `## Log` grows past roughly 60 bullets
or 15 KB, digest moves the oldest settled bullets — never the final bullet, never a bullet
younger than 90 days — to `projects/archive/<name>.md`, verbatim and in order, writer tags
intact. The archive page is created on first use (`type: project`, `status: archived`, a one-line
summary pointing back to the live page). It sits outside the `projects/*.md` union rule and only
digest writes it. The live page keeps one marker bullet in place of the moved run:
`- <first-date>..<last-date>: earlier log archived to [[projects/archive/<name>]]. [<harness>@<host>]`
Each archival is two reconcile-protocol commits in strict order: first append the bullets to the
archive page and push; then remove them from the live page, leave the marker, and push. A failure
between the two leaves the bullets duplicated, never lost, and the next digest finishes the
removal. `recall` and `maintainer` read archive pages only when the live page's marker points
there.

## Degradation ladder (brain unreachable)

Never drop a capture — but never leak one either. Outbox files are **private memory**: they are
never committed to a product repo, never pushed anywhere but the brain. If the brain root is
missing/unreachable from the current environment (sandboxed session, offline machine):

1. On a **durable machine**: write the capture to `./.brain-outbox/YYYY-MM-DD-<slug>-<writer>.md`
   in the current working repo, page-formatted, with a `destination:` frontmatter hint — as a
   **local-only file**. Add `.brain-outbox/` to the repo's `.git/info/exclude` (takes effect
   locally without committing anything) if it isn't already gitignored. Do not commit or push
   outbox files, even if the repo would accept them.
2. In an **ephemeral environment** (a cloud sandbox whose files vanish with the session) or with
   no writable working repo: emit the capture as a fenced `BRAIN CAPTURE` block in the final
   report so the owner (or a later agent) can file it — a local file that will be destroyed is
   not a capture.

`digest` ingests outboxes (and deletes them) whenever it encounters them.

## Digest lock (single-restructurer guarantee)

Only one digest runs fleet-wide at a time. Cooperative lock via push-wins arbitration:

1. **Claim:** `git pull --rebase`; if `.locks/digest.md` exists → held, abort. Else commit the
   file (host + harness + ISO timestamp) and `git push`.
2. **On push rejection:** `git fetch`, inspect the remote `.locks/digest.md`. If the remote has a
   lock → someone else won — drop the local claim and abort: `git reset --hard @{u}` only when
   the claim is the **only** unpushed commit; with anything else unpushed beneath it (e.g. a
   push-pending capture), `git reset --hard HEAD~1` drops just the claim and leaves the rest to
   sync on its normal retry. If the remote has no lock (the rejection was an unrelated capture
   landing) → `git pull --rebase` and push the claim again.
3. **Staleness:** a lock whose *committer date* (not local clock) is older than 2 hours may be
   deleted (commit + push the deletion, then re-claim from step 1).
4. **Release:** delete the lock file, commit, push — in the same run that took it, even on failure.

A **completed digest** is a full consolidation pass that ends by regenerating `INDEX.md`; its
date is INDEX.md's `Last generated` line. A lock cycle taken for a scoped edit — one reconcile, a
config change — is not a completed digest and does not reset any digest-cadence clock.

## Retrieval without a database

Hybrid search, cheapest first:

1. **Freshness:** if a remote exists and the last sync is over an hour old, run
   `git pull --ff-only` first — recall never writes, so fast-forward is always safe. If the pull
   fails (offline), answer anyway and say the brain may be stale.
2. **Slug/filename match** — `ls`/`fd` on the type directory.
3. **Frontmatter and tag match** — `rg -l 'tags:.*<tag>'`.
4. **Full-text** — `rg -i '<terms>'` across the brain root.
5. **Graph hop** — from a hit page, follow wikilinks out (read targets) and in
   (`rg -l '\[\[<slug>\]\]'`), one or two hops.
6. Rank: exact slug > frontmatter/tag > title > body; recent `updated:` breaks ties.

## Upgrade path

When the tree outgrows grep (≳ tens of thousands of pages), install real gbrain, point it at the
brain root, and swap recall's search steps for `gbrain search` / `gbrain think` — the page format
above is already conformant, and git remains authoritative either way.
