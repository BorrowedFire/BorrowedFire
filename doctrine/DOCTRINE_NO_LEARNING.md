<!-- BEGIN BORROWEDFIRE DOCTRINE -->
## Borrowed Fire doctrine (v5 safe mode — managed by install.sh, do not hand-edit)

**Memory.** Prometheus is the private git-backed brain. Resolve it through `$PROMETHEUS_DIR`, then
`~/.config/borrowedfire/brain`, then `~/prometheus`. Before substantive repo work, use `recall` for
the matching project and lessons pages. Use `remember` for durable decisions, gotchas, people,
meetings, and project-status changes; it owns storage, outbox, schema, and sync behavior. Never put
secrets or private brain content in a product repo.

**Writing.** Write so a tired engineer understands on the first read. Every reply, doc, commit
message, PR body, and owner brief follows the same rules: one thought per sentence and one
instruction per sentence; active voice with a named actor; the short everyday word; the condition
before the instruction; one name per thing everywhere; and every word that does no work deleted.
Keep the articles and the small words that make a sentence parse one way. Prefer a period to an em
dash or a semicolon. Scope every "never" and "always" to its hazard and name the sanctioned
exceptions, so a rule cannot forbid an operation the system requires. Run `unslop` on prose before
it ships. Use `technical-writing` for docs, READMEs, RFCs, design notes, `SKILL.md` bodies, PR
descriptions, and commit messages; it owns the full four-layer standard (Diataxis, Google developer
style, ASD-STE100, Global English) and the review checklist.

**Learning disabled.** Automatic learning is disabled because the complete learning stack is not
installer-owned. Restore it with a successful Borrowed Fire install before enabling any recurring
learning controller. Do not invoke `reflect` automatically in this state.

**Safety.** The `land` denylist is always owner-gated: migrations/schema/RLS, auth, payments,
secrets/signing, destructive operations, deploys/releases, and store submission. A workflow skill
never widens the owner's existing authorization.

**Fleet.** Let the active workflow and the private `config/fleet.md` choose eligible tiers.
Judgment stays with the current capable harness; bounded volume work defaults to a configured
local tier when one is available. Never hardcode private endpoints, caps, or provider policy.

**Routing.**

| Need | Skill |
|---|---|
| capture / retrieve / consolidate memory | `remember` / `recall` / `digest` |
| land one PR through review | `land` |
| work a registered repo/fleet queue | `maintainer` |
| commit/push/merge/deploy closeout | `ship` |
| undo a bad merge or deploy | `rollback` |
| App Store / Play release train | `store-release` |
| changelog or release notes | `changelog` |
| dependency/security updates | `deps` |
| shape a report or idea into an issue | `triage` |
| register a new repo/app/idea | `bootstrap` |
| bounded QA loop | `qa-audit` |
| marketing / customer-facing copy | `signal` |
| engineering prose: docs, RFCs, PR descriptions, commit messages | `technical-writing` |
| cut AI tells from any prose before it ships | `unslop` |
| audit requested vs completed work at session end | `session-closeout` |
<!-- END BORROWEDFIRE DOCTRINE -->
