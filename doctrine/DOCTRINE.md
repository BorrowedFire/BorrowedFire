<!-- BEGIN BORROWEDFIRE DOCTRINE -->
## Borrowed Fire doctrine (v2 — managed by install.sh, do not hand-edit)

**Brain (memory: "Prometheus").** Resolve: `$PROMETHEUS_DIR` → path in
`~/.config/borrowedfire/brain` → `~/prometheus`. Git-authoritative markdown; schema = the
`remember` skill's
`references/brain-schema.md`. If unreachable, write captures to `./.brain-outbox/` in the working
repo — local-only, never committed/pushed (use `.git/info/exclude`); in ephemeral sandboxes emit a
fenced `BRAIN CAPTURE` block instead (`digest` ingests both). Never drop a capture; never scatter
memory files outside a brain root or outbox; never commit private memory to a product repo.

**Brain sync.** `git pull --rebase` before writing; commit per capture
(`brain: capture <path> [<harness>@<host>]`); push immediately; rejected → rebase + retry ×3, then
leave committed and report "push pending". Never force-push or rewrite brain history. Only
`digest` restructures pages; everyone else appends, with a writer tag on every log bullet. On
union-merged paths (`journal/`, `inbox/`, `projects/`) appends are strict: touch no other line,
not even `updated:` frontmatter — digest reconciles it.

**Capture triggers** (offer a one-line `remember` capture; never block work): decision + reason →
`decisions/` · gotcha/postmortem → `lessons/` · new person/org → `people/` `companies/` · meeting
recap → `meetings/` · new repo/app/idea or project status change → its `projects/` page.

**Preflight.** Before substantive work on any repo: `recall` its `lessons/` and `projects/` page.

**Safety rails.** No secrets in the brain, ever (name where a credential lives, not its value).
The denylist (the `land` skill's `references/denylist.md`: migrations/schema/RLS, auth, payments,
secrets/signing, destructive ops, deploys/releases) is always owner-gated regardless of standing
permissions. Store submission is owner-gated by default.

**Tier routing.** Judgment work (review verdicts, planning, owner briefs) may use the paid tier;
volume work (bulk edits, first drafts, summarizing) defaults to the local tier when the fleet has
one. Instance endpoints, caps, and the paid-task whitelist live in the brain's `config/fleet.md` —
never hardcoded.

**Routing.**

| Need | Skill |
|---|---|
| capture / retrieve / consolidate memory | `remember` / `recall` / `digest` |
| land ONE PR through review to merge | `land` |
| work a repo/fleet queue (registry = brain `projects/`) | `maintainer` |
| commit-push-merge-deploy closeout | `ship` |
| undo a bad merge/deploy | `rollback` |
| App Store / Play release train | `store-release` |
| factual release notes / changelog | `changelog` |
| dependency & security updates | `deps` |
| shape a raw report/idea into an issue | `triage` |
| wire a new repo/idea into the system | `bootstrap` |
| bounded QA loop | `qa-audit` |
| marketing / customer-facing copy | `signal` |
<!-- END BORROWEDFIRE DOCTRINE -->
