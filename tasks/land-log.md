# Land log

Dated entries appended by `land` runs — item, classification, gates, decisions, outcome.

## 2026-08-04 — union-path reconcile protocol (PR #10)
- Item: schema/digest contradiction on union-merged in-place edits; fix defines a digest-only
  reconcile protocol in brain-schema.md; digest + remember defer to it.
- Class: Autonomous (docs-only live skill instructions; 3 files, +33/−14; denylist: no match).
- Gates at open: local CI parity green (skill-lint 15/15 · test-brain 22/22 · test-install 63/63);
  adversarial review, Codex, and live proof recorded on the PR before merge.
- Round 2: adversarial review (empirical two-clone git lab) validated 4 P2s in one design area →
  related-finding circuit breaker → invariant audit posted on the PR; protocol hardened once
  (precondition, Relations whitelist, both append points, retry bound, stranded-commit guard,
  no-stub rule). Core mechanics confirmed correct; no P1s. Follow-ups filed as a repo issue
  (test coverage for the protocol; template README scoping).
- Round 3–4: verify pass caught one regression in the hardening (guard conscripted read-only
  recall into a hard reset) — fixed with four P3 one-liners; Codex round 3 validated one
  literal-reading defect in the no-stub rule — scoped to in-place dedup with the inbox
  promotion exemption explicit. Final: adversarial CLEAN ×2, Codex clean @ `e2692f496b`.
- Outcome: squash-merged as `4788afa` (2026-08-04). Live proof: reconcile protocol executed
  against the real brain pre-merge. Follow-ups: issue #11 (protocol test coverage; template
  README scoping; lock-claim blanket-reset precondition).
- PR: https://github.com/BorrowedFire/BorrowedFire/pull/10
