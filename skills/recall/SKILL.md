---
name: recall
description: Retrieve from the brain — the private git-backed markdown memory written by `remember`. Use when the user says "/recall", "recall", "what do we know about X", "have we met/discussed X before", "check my brain", "search my notes", "what did we decide about X", or at the start of any task where prior context (people, projects, decisions, lessons) would change the plan. Read-side of the memory system. NOT for searching repo code (use normal code search) and NOT a general web/knowledge lookup — it answers only from the brain.
---

# Recall

Answer from the brain with citations, and say plainly what the brain does *not* know. Retrieval is
grep-based hybrid search plus graph hops over wikilinks — `remember`'s
`references/brain-schema.md` is authoritative for the brain location, layout, freshness rule, and
the ranked search recipe. Never answer memory questions from general knowledge when a brain
exists: look first.

## Rules

- **Freshen first** (schema §Retrieval): if a remote exists and the last sync is stale,
  `git pull --ff-only` before searching — recall never writes, so fast-forward is always safe. If
  the pull fails (offline), answer anyway and say the brain may be stale.
- **Cite pages.** Every claim sourced from the brain names its page path; quote the dated log line
  when the timeline matters.
- **Separate memory from inference.** "The brain says X (page); I'd additionally guess Y" — never
  blend the two silently.
- **Report gaps honestly.** If the brain has nothing (or only stale/`needs-review` pages), say so;
  offer a `remember` capture to fill the gap rather than fabricating.
- **Read-only.** Recall never edits pages. Contradictions or duplicates found while searching are
  reported and left for `digest` (offer to run it).

## Flow

1. Resolve the brain root (schema §Locating). No brain → say so; offer `remember` to start one.
2. Freshen per the rule above.
3. Extract the entities and question from the request.
4. Search cheapest-first per schema §Retrieval: slug match → tags/frontmatter → full-text →
   graph hops (wikilinks out; backlinks via `rg -l '\[\[<slug>\]\]'`). Stop when marginal hits
   stop changing the answer.
5. Read the top pages fully (they are small by design); pull the dated log lines relevant to the
   question.
6. Answer: direct answer first · supporting log lines with page paths · related pages worth a look
   (one hop out) · **gaps** — what the question needed that no page holds.

## Task preflight (proactive use)

Before substantive work on any repo, one cheap pass is doctrine: search `lessons/` and `projects/`
for the repo/surface at hand (`rg -il '<repo|topic>' lessons/ projects/`). A ten-second lookup
that surfaces a prior gotcha pays for itself; this is the read-side twin of `land`'s lessons
write-back.

## Related

`remember` (write side, owns the schema) · `digest` (fixes what recall finds broken).
