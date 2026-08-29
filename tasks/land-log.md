# Land log

> **Note on issue/PR numbers.** This repository was recreated with clean commit
> history on 2026-08-21. Entries below that cite `#N` (for example PR #10, issue #11)
> refer to the **previous** repository, archived privately as
> `BorrowedFire/BorrowedFire-archive-2026-08`. Numbering in this repository restarts from #1,
> so a bare `#N` here does not resolve to the item the entry describes.

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
- PR: https://github.com/BorrowedFire/BorrowedFire-archive-2026-08/pull/10

## 2026-08-05 — reconcile protocol test coverage + doc scopings (issue #11)
- Item: https://github.com/BorrowedFire/BorrowedFire-archive-2026-08/issues/11 — live two-clone coverage for the
  reconcile protocol (drop-and-redo, final-bullet adjacency + settled control, post-Queue append
  point, stranded-commit guard, test 3 hardened to the schema's unconditional claim), template
  README "edit anything" scoped to the union-merge caveat, and the addendum's only-unpushed-commit
  precondition added to the digest-lock claim step 2.
- Class: Autonomous (tests + docs; 3 files, +93/−8; denylist: no match; merge owner-gated per
  instruction).
- Gates at open: local CI parity green (skill-lint 15/15 · test-brain 46/46, up from 22/22 ·
  test-install 63/63 · bash -n clean; shellcheck covered by CI).
- Negative checks (labs on scratch copies, not the repo): guard's drop removed from test 11 →
  "guard: single updated: key" FAILS (45/1); `projects/*.md merge=union` removed from the
  template → new test 3 red on both checks while origin/main's test 3 stays green — the exact
  blind spot issue #11 named.
- Outcome: PR opened, driven to review-clean; merge stopped at the owner gate per instruction.

## 2026-08-24 — writing standard into doctrine + bare skill names (PR #3)
- Item: https://github.com/BorrowedFire/BorrowedFire/pull/3 — adopt `technical-writing` and
  `unslop` (adapted from pstack, MIT), move the writing mandate into a new doctrine **Writing**
  section (v4 → v5, both variants), guard it with a fail-closed `skill-lint.sh` contract, derive
  the manifest count in `test-install.sh`, revert `borrowedfire-triage` to `triage`, and rename
  `borrowedfire-learn` to `reflect`.
- Class: Autonomous (skills, doctrine, lint, tests; 21 files; denylist: no match;
  `denylist_extra: []`). Root cause: the old `Always talk in ASD-STE100` line named a standard
  instead of stating rules, and `~/.codex/AGENTS.md` has no hand-written preamble, so Codex never
  received it at all.
- Gates: adversarial (gate 1) 4 findings, all fixed — a Writing paragraph that broke its own
  no-semicolon rule, a missing contract regression, the deployed-controller rename gap, and
  loop-variable style. Codex (gate 2) 2 × P2, escalated as design calls, owner expanded scope,
  both then fixed. CI green. Live proof recorded.
- Bug in a fix (the review loop earning its keep): rewriting the Writing paragraph moved
  `` `unslop` `` across a hard wrap and broke the line-anchored `grep -F` enforcing it. Fixed at
  the mechanism, not the wrap: prose contracts now match a whitespace-flattened copy via
  `doctrine_has`, proven by re-wrapping the paragraph to 72 columns and confirming the lint holds.
- Gotcha: CI runs `shellcheck` over four shell files and the local gate set does not. A backtick
  inside a single-quoted `sed` expression tripped SC2016 and reddened CI after all local suites
  were green. Run CI's exact five-step sequence locally before declaring gates green.
- Invariant audit (circuit breaker, two validated findings in one design area): every stored
  instruction naming a Borrowed Fire skill must be verified against, or refreshed by, the
  component that owns it, before it becomes active. Doctrine mandates 6 skills; `install.sh`
  verifies only the 4 in `LEARNING_SKILLS`. Stored OpenClaw job declarations on other hosts are
  refreshed by no one. Full consumer matrix posted on the PR.
- Resolution after the owner expanded scope: `DOCTRINE_SKILLS` is now the union of
  `LEARNING_SKILLS` and the new `WRITING_SKILLS`, and both the collision and ownership passes
  verify that union before the full doctrine is written. One reduced doctrine rather than four
  variants: either capability class failing drops the harness to it and exits 1. The writing
  RULES survive degradation because they are self-contained prose; only the two skill mandates
  drop, so the installer never mandates a skill it could not verify.
- Stored-controller resolution: the cycle installer already fails closed before declaring a job
  when the agent cannot see the whole learning stack, so a NEW declaration can never name a
  missing skill. Its two Python skill literals are now held to `install.sh`'s `LEARNING_SKILLS`
  by lint, and its header documents that a rename cannot reach an already-declared controller.
  `reflect`'s description also carries `borrowedfire-learn` as a legacy trigger, which
  `skill-lint.sh` permits for descriptions, so a stale controller prompt still resolves.
- Second sweep (Codex round 3): the same invariant was fixed in `install.sh` but not in
  `tools/install-prometheus-cycle.sh`, which activates that doctrine and validated only the four
  learning skills. Every enumeration site now carries the doctrine-mandated six: the integrity
  check, the model-visibility gate, the test fixture, and the lint drift contract. A hidden
  writing skill now fails the declaration closed, covered by a new regression.
- Residual, not fixable from this repo: a controller declared before this rename keeps its stored
  message until `tools/install-prometheus-cycle.sh` is re-run on that host. Every host running a
  controller needs that run; the affected hosts are tracked in the brain, not here.
- Rounds: 5 Codex rounds, each surfacing one real and progressively smaller defect (2 x P2 design
  -> P3 stale log -> P2 incomplete sweep -> P1 public-repo policy). `--max-rounds 4` was exceeded
  by one verification-only pass to obtain a verdict on the final head.
- Codex re-anchoring hit again: after the first push, both original P2 comments carried the new
  head in `commit_id`. Gating on `created_at` and `original_commit_id` per
  [[lessons/github-review-comment-reanchoring]] correctly showed the round as still pending.
- Outcome: squash-merged as `4874b57`. Gates at merge: adversarial clean (4 found, 4 fixed),
  Codex clean at `c3f0eae5d6` with the sha matching head, CI green, live proof recorded. Verified
  on merged main: skill-lint 18, test-install 135/135, test-brain 46/46,
  test-prometheus-cycle 164/164, and both harnesses serve doctrine v5 from this checkout.

## 2026-08-26 — proof ladder in the Live Proof Gate (PR #6)
- Item: https://github.com/BorrowedFire/BorrowedFire/pull/6 — grade live proof on a five-rung
  ladder (adapted from pstack's blast-radius, MIT). `land` step 9 defines the ladder; every proof
  names its rung; runtime claims pass at rung 4+, class bullets naming a live or drivable surface
  set a rung-5 floor; the step-10 merge predicate requires the floor, not a record. `qa-audit`
  grades evidence on the same ladder; "proven" means rung 4 or higher.
- Class: Autonomous (2 skill bodies + lint + tests; 4 files, +48/−3; denylist: no match).
- Gates: adversarial 2 findings pre-push, both fixed (rung 4 admitted a generic green suite; the
  rung-4 floor undercut the live-system class bullets). Codex round 1: 2×P1 (one mechanism: the
  merge predicate consumed a record, not the threshold) + 1×P2 (lint guarded the label, not the
  threshold) — circuit breaker fired, consumer matrix posted on the PR, one coherent fix. Codex
  round 2: clean @ `6ec12f4` (sha == head). CI green.
- Gotcha (mirror of [[lessons/prose-contracts-break-on-rewrap]]): a fail-closed regression's sed
  was line-anchored while its target phrase hard-wraps, so the mutation no-opped and the case
  failed vacuously. Mutate the sub-phrase that sits on one line, or flatten before matching.
- Outcome: squash-merged as `bfc73a6`. Live proof at final head, rung 4 for a docs/CI diff: the
  executed lint suite (skill-lint 18, test-install 139/139, test-brain 46/46, cycle 164/164,
  shellcheck clean), four contracts proven to fail closed, and the installed skills serving the
  ladder, threshold, and predicate in both harnesses.

## 2026-08-29 — inventory agreement + controller teardown (PR #8)
- Item: https://github.com/BorrowedFire/BorrowedFire/pull/8 — first PR of the ponytail adoption
  (DietrichGebert/ponytail @ `2ed6c52`): keep the skill inventory's copies in agreement and give
  the nightly controller a removal path. skill-lint rule 10 ties `skills/*` to both doctrine
  routing tables (two-sided reduced-mode exemption, Skill-column scoping, malformed-name
  rejection, and the reverse direction) and to the README (links and count). Doctrine v6 adds
  the `reel-maker` row; the owner picked a routing row over an exemption.
  `install-prometheus-cycle.sh --remove` tears down the learning job and probe by declaration
  key and deletes the route proof only when this run removed the learning job.
  `install.sh --uninstall` prints the teardown reminder on stderr, on the no-harness exit, and
  before the fail-closed exit. CI now runs the cycle suite and checks its scripts.
  cycle-contract.md gains a Removal section.
- Class: Autonomous (lint, installers, doctrine text, docs, tests; 10 files; denylist: no match).
- Gates: adversarial max-effort — six finder passes plus a sweep (the line-by-line finder died
  on a 429 mid-run; the sweep re-covered its remit) found 15 findings, all fixed, none refuted.
  Codex round 1: P2, the host-wide route proof was deleted for other profiles — fixed by gating
  deletion on the learning job actually being removed here; per-binding namespacing was rejected
  as converge-path scope. Round 2: P2, the chmod-555 fixture fails under root — fixed with a
  PATH-stubbed failing mktemp. Round 3: clean @ `86116fb` (sha == head, no new findings). CI
  green on both heads of the extended workflow (2m58s, 2m19s).
- Scope note: cumulative fixes grew the diff past 2× the frozen non-test baseline. All growth is
  validated-finding hardening of this PR's own mechanisms, and the owner's "I want this for
  Prometheus" is the scope authorization. Recorded here instead of an escalation.
- Gotcha: a chmod-based negative fixture passes or fails with the runner UID, because root
  ignores mode bits. Fault-inject by stubbing the failing tool on PATH instead. See
  [[lessons/chmod-fixtures-do-not-bind-root]].
- Outcome: squash-merged as `e397570`. Live proof — rung 5 for the doctrine and note surfaces
  (a real `install.sh` run wrote the v6 header and `reel-maker` row into a sandbox harness
  exactly once; a real uninstall printed the note on stderr with a trace present); rung 4 for
  the lint and teardown paths (suites 156/156 and 184/184 executing every new branch including
  eight fail-closed contract mutations; direct host runs: `--remove --dry-run` exit 0, flag
  rejection exit 2). `--remove`'s rung-5 surface is Selene's production scheduler; mutating it
  is rollout, not merge proof. Rollout owed: an `install.sh` re-run per harness for doctrine v6
  (this Mac, and Selene in an interactive session).
