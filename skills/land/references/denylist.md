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

## Router enforcement rules

These machine-readable rules are consumed by `bf-route` before it applies a generated patch. Keep
them aligned with the authoritative categories above; project `denylist_extra` entries are added at
runtime from the matching Prometheus project page.

<!-- bf-route-path: (?:^|/)migrations?(?:/|$) -->
<!-- bf-route-path: (?:^|/)(?:schema|rls)(?:[._/-]|$) -->
<!-- bf-route-path: (?:^|/)(?:auth|authentication|authorization|sessions?|permissions?)(?:[._/-]|$) -->
<!-- bf-route-path: (?:^|/)(?:payments?|billing|iap)(?:[._/-]|$) -->
<!-- bf-route-path: (?:^|/)(?:secrets?|keys?|signing|credentials?)(?:[._/-]|$) -->
<!-- bf-route-path: (?:^|/)\.env(?:[._-]|$) -->
<!-- bf-route-path: (?:^|/)(?:config|configuration|environments?)(?:/|$) -->
<!-- bf-route-path: (?:^|/)[^/]+\.(?:xcconfig|entitlements)$ -->
<!-- bf-route-path: (?:^|/)scripts?/(?:backfill|seed|migrate|production)(?:[._/-]|$) -->
<!-- bf-route-path: (?:^|/)(?:deploy(?:ment)?|releases?)(?:[._/-]|$) -->
<!-- bf-route-content: \b(?:production data|destructive|backfill|seed production)\b -->
<!-- bf-route-content: \b(?:auth(?:entication|orization)?|payments?|billing|iap|secrets?|signing)\b -->
<!-- bf-route-content: \b(?:deploy(?:ment)?|cut (?:a )?release)\b -->
<!-- bf-route-content: ^\+(?!\+\+)[^\n]*(?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|private[_-]?key|password|passwd|secret)[A-Za-z0-9_.-]*\s*["']?\s*(?::=|=|:)\s*["']?[A-Za-z0-9/+_.=-]{6,} -->
<!-- bf-route-content: ^\+(?!\+\+)[^\n]*BEGIN [A-Z0-9 ]*PRIVATE KEY -->
<!-- bf-route-content: ^\+(?!\+\+)[^\n]*\b(?:DELETE\s+FROM|TRUNCATE(?:\s+TABLE)?|DROP\s+(?:TABLE|DATABASE|SCHEMA))\b -->
<!-- bf-route-content: ^\+(?!\+\+)[^\n]*\.(?:delete|destroy)\s*\( -->
<!-- bf-route-content: ^\+(?!\+\+)[^\n]*\b(?:rm\s+-[A-Za-z]*r[A-Za-z]*f|git\s+(?:reset\s+--hard|clean\s+-[A-Za-z]*f))\b -->
