---
name: bootstrap
description: Wire a new (or newly adopted) repo, app, or idea into the Borrowed Fire system. Use when the user says "/bootstrap", "bootstrap this repo", "set up a new project", "start a new app/idea", "register this repo", or "make this repo work with the system". Creates the agent context file, CI, conventions the other skills assume, and the brain registry page. NOT for initializing the brain itself (`remember` offers that) and NOT for shipping code (`ship`/`land`).
---

# Bootstrap

Every other skill assumes conventions: an agent context file, a CI lane, branch protection, a
registry page in the brain. A repo missing them makes `maintainer` guess and `land` under-deliver.
Bootstrap wires a project up once so the system works from day one.

## Rules

- **Idempotent and additive.** Detect what exists; never overwrite a hand-written context file,
  CI config, or README — extend or propose instead.
- **Match the repo's stack.** CI, test lane, and lint come from what the repo actually uses;
  don't scaffold a stack onto an empty idea repo that hasn't picked one.
- Branch protection and repo settings changes are proposed as an exact checklist (or `gh`
  commands) for the owner — settings are owner-gated by default.
- An **idea without a repo yet** gets the registry page only (`repo:` omitted, `status: idea`) —
  the rest happens when code exists.

## Flow

1. **Survey.** Stack, existing context files (`CLAUDE.md` / `AGENTS.md` / `QWEN.md`), CI, tests,
   default branch, protections, deploy story. `recall` whether the brain already knows this
   project.
2. **Context file.** Create or extend the repo's agent context file: how to build/test/run, deploy
   path, review policy (the `land` gates), repo-specific denylist additions, and pointers the
   whole system relies on. Multi-harness repos get one canonical file and thin per-harness
   includes, not divergent copies.
3. **CI.** Ensure at least: install + build + test on PR. Extend the existing workflow if one
   exists.
4. **Conventions.** `.gitignore` (include `.brain-outbox/`), PR template if the owner uses them,
   `docs/releases/` for app repos headed to stores.
5. **Register in the brain** (via `remember`): a `projects/<name>.md` page with full registry
   frontmatter (schema §Project registry) — `repo`, `default_branch`, `autonomy` (default
   `gated`), `review_bot`, `denylist_extra`, `status` — plus a first `## Log` line for why the
   project exists.
6. **Protection checklist.** Exact owner steps (or commands) for branch protection, required
   checks, and the review bot's installation (`land` needs `@codex review` reachable, or the
   registry set to `review_bot: none`).
7. **Report.** What was created/extended, the registry page path, the owner checklist, and the
   one-line handoff: the repo is now workable by `maintainer`.

## Related

`remember` (registry page creation; brain initialization) · `maintainer` (consumes the registry) ·
`land` (relies on the review policy wired here) · `ship` (relies on the deploy story wired here).
