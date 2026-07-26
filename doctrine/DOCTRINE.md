<!-- BEGIN BORROWEDFIRE DOCTRINE -->
## Borrowed Fire doctrine (v3 — managed by install.sh, do not hand-edit)

**Memory.** Prometheus is the private git-backed brain. Resolve it through `$PROMETHEUS_DIR`, then
`~/.config/borrowedfire/brain`, then `~/prometheus`. Before substantive repo work, use `recall` for
the matching project and lessons pages. Use `remember` for durable decisions, gotchas, people,
meetings, and project-status changes; it owns storage, outbox, schema, and sync behavior. Never put
secrets or private brain content in a product repo.

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
<!-- END BORROWEDFIRE DOCTRINE -->
