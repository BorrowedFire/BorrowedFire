# High-risk denylist (authoritative)

The single definition of "always owner-gated at merge," referenced by `land`, `maintainer`,
`qa-audit`, and the Borrowed Fire doctrine. A diff touching any of these is driven to
clean + proven, then **stopped at the merge gate** for the owner — regardless of any standing
auto-merge permission.

- **Database migrations / schema / RLS / production data writes** (e.g. `**/migrations/**`) —
  gate per the repo's prod-write policy (e.g. an ADR). Never auto-merge.
- **Auth / sessions / permissions.**
- **Payments / billing / IAP.**
- **Secrets / keys / signing config / environment configuration.**
- **Destructive data operations.**
- **Anything that deploys or cuts a release/build** — out of scope for autonomous merge; hand to
  `ship` (deploy) or `store-release` (store builds), which carry their own gates.

Per-repo additions come from the brain's project registry (`projects/<repo>.md` frontmatter,
`denylist_extra:`) — read it before classifying a diff.
