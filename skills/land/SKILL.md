---
name: land
description: Autonomously drive ONE branch/PR through commit, review (adversarial + Codex), auto-fix, live proof, and merge-when-clean — surfacing only a decision-ready ask if it cannot finish. The single-PR worker primitive that `maintainer` orchestrates. Use when the user says "/land", "land", "land this", "autoland", "take this through review and merge", "run the review loop", or wants one change shepherded to merge without babysitting. Works in Claude Code, Codex, and other SKILL.md harnesses (see Tool adapters). NOT for deploys or closeout without a review loop (`ship`), NOT for cutting App Store/Play/TestFlight builds (`store-release`), and NOT a general "go achieve a goal" command.
---

# Land

Drive a branch from "I have a change" to **merged · clean · proven** without babysitting. The value
is **reliability + encoded gotchas + decision-ready escalation**, not the happy path. Three gates
stand before merge: **adversarial review · Codex · live proof.** Bias toward escalating ambiguity
over guessing.

## Operating principle — Decision-Ready

**Never hand back an unprepared branch.** Do *all* autonomous work first — implement, auto-fix,
test, **live-prove**, review-to-clean, CI-green — before involving the owner. The only interactions
you may ask for: **land** the prepared PR · **delete/close** it · give **one exact access step** ·
**pick** between documented alternatives. Anything you can decide *reversibly and safely*, decide
it and surface it in the summary. If autonomous work remains, do it and report the item as
*active*; never ask a premature question.

## Classify first

- **Autonomous** — clear, bounded, reproducible, with a real **live-proof path**. Drive to merge.
- **Needs-owner** — product choice, security/privacy/irreversible call, missing credential/access,
  no live proof, or it touches the **denylist** (`references/denylist.md`, plus the project
  registry's `denylist_extra`). Drive to decision-ready, then emit one Owner Decision Brief.
- **Ignored** — only when the owner explicitly said so. Leave it untouched.

## Tool adapters

The mechanics below are runtime-neutral (`git`, `gh`, and `@codex review` — the GitHub bot,
identical everywhere). Steps that map per runtime:

| Abstract step | Claude Code | Codex | Other harnesses |
|---|---|---|---|
| adversarial review (gate #1) | `/code-review` or a review subagent | `autoreview` | strongest available independent review pass |
| delegate / spawn a worker | background `Agent` subagent | a Codex thread / `codex exec` | one worker process/session |
| self-paced polling | `ScheduleWakeup` or a backgrounded shell loop | a backgrounded task | backgrounded loop |
| branch prefix | `claude/<slug>` | `codex/<slug>` | `<harness>/<slug>` |

## Inputs

`/land [branch] [flags]` (or the harness's skill-invocation equivalent)

| Flag | Default | Effect |
|---|---|---|
| `branch` | current | Branch to land. |
| `--no-auto-merge` | auto-merge **ON** | Stop at the merge gate for owner approval. |
| `--max-rounds N` | `4` | Review rounds before forcing a decision-ready escalation. |
| `--reviewer` | `codex` | `codex` (default) or `adversarial-only` fallback when Codex is down/unavailable. |

Default posture: **auto-merge ON** for Autonomous low/medium-risk diffs; **always owner-gated** for
the denylist.

## The loop

**0 · Preflight.** Confirm `gh` auth + repo; `recall` the brain's `lessons/` and the repo's
`projects/` registry page (autonomy level, `review_bot`, `denylist_extra`) if a brain is
available; identify the diff's **blast radius** — needed for the denylist check, the live-proof
choice, and the summary.

**1 · Un-stale the branch (critical).** `git fetch origin`; if behind the base branch, **merge it
in** first. A stale branch makes the reviewer flag files that exist on the base but not the branch
as "missing/untracked" — phantom findings. If the base merge **conflicts**: resolve only trivial,
mechanical conflicts (imports, adjacent-line churn, lockfiles by regeneration); any conflict
touching the same logic the branch changes is a *semantic* conflict — stop and escalate
decision-ready rather than guessing an integration.

**2 · Commit + push + PR.** Commit intended changes (clear message). Push. Open the PR if missing —
body = problem / root cause / fix / **how it was proven** / scope. Use full clickable URLs, never
bare `#123`.

**3 · Adversarial review (gate #1).** Run a local adversarial pass (see Tool adapters) and
apply/verify its real findings now. This is the *second independent reviewer* — a single green
check is **necessary but not sufficient**.

**4 · Trigger Codex (gate #2).** `gh pr comment <PR> --body "@codex review"`. A push alone does
**not** re-trigger — re-comment every round. (Skip this gate only when the registry says
`review_bot: none`; the merge gate then requires adversarial-clean + live proof + CI, and the
summary must say the Codex gate was absent.)

**5 · Poll for the verdict (self-paced).** Record baseline counts first (`cc` = Codex issue
comments, `cr` = Codex reviews), then poll until a new one appears (see Tool adapters). Codex runs
~2–50 min — never busy-wait; sleep 75–90s between checks. The bot login matches `codex` (e.g.
`chatgpt-codex-connector`). *Bot behavior details here were observed as of 2026-07 — if the bot's
comment shapes change, re-verify before trusting the parsing rules below.*

**6 · Read the verdict — DUAL SIGNAL (load-bearing).**
- **CLEAN** = an *issue comment* "Didn't find any major issues … **Reviewed commit: `<sha>`**". If
  that sha ≠ current head, it's **stale, not clean** — re-trigger.
- **FINDINGS** = *inline review* comments (`gh api repos/<repo>/pulls/<PR>/comments`), each tagged
  P1/P2/P3.
- Check **both** or a clean head reads as "pending forever".

**7 · Handle each finding — VERIFY → FIX *or* REFUTE → (or ESCALATE).** A finding is a *claim, not
a fact.*
- **Validate it** against reality (read the code; query the live system; `ls`/grep the file).
  About half of real findings are doc-gaps, already-handled, or stale re-posts.
- **Real →** fix **narrowly** (match shipped reality; no redesign/scope-creep). Re-push, GOTO 4.
- **False / stale →** do **not** edit correct code to silence it. Post an evidence-backed
  **refutation** on the PR, re-review. (Stale re-posts are often self-contradicted within one
  review — "file missing" alongside "I checked that file".)
- **Judgment / design / decision-record / product →** escalate decision-ready (below). Don't guess.

**8 · Circuit-breakers — stop and escalate when:** `--max-rounds` reached · the **same finding
recurs after a genuine fix** · a fix would **grow the diff past scope** · the reviewer is silent
~60 min · any denylist trigger.

**9 · Live Proof Gate (gate #3) — pre-merge, not optional.** Prove the *exact final candidate*
works through its real changed path. **Never infer a waiver from "review clean" or "tests pass."**
- **UI diff** → drive the real surface (sim/app/browser), screenshot, confirm.
- **Backend / data / migration** → query the **live system** and confirm behavior (RPC output,
  grants, row counts, state transition).
- **Jobs / notifications / external calls** → trigger the real path and observe the result class.
- **Pure docs / metadata / CI** → built-artifact or workflow proof, and *state why* there's no
  runtime boundary.
- Re-run proof after **any** fix that touches the runtime path. Record concrete evidence
  (command + observed state) in the PR + summary; redact secrets.

**10 · Merge gate.** Squash-merge **only when ALL hold:** adversarial-clean · Codex-clean on the
current head (or `review_bot: none` acknowledged) · **live proof recorded** · CI/tests green where
a lane exists · diff **not** in the denylist. If `--no-auto-merge`, stop here with a brief.

**11 · Close out.** Post the summary; append a dated entry to the land log (`tasks/land-log.md` in
the repo — commit it with the work; item, classification, gates, decisions, merge sha or the exact
owner ask). Write any new gotcha / false-positive pattern back via `remember` to the brain's
`lessons/`, wikilinked to `[[projects/<repo>]]` (outbox fallback if the brain is unreachable) — so
the next run, on any machine, needs the owner less.

## High-risk denylist — ALWAYS owner-gated at merge (even with auto-merge ON)

See `references/denylist.md` (authoritative) plus the project registry's `denylist_extra`. Drive to
clean + proven, then **stop at the merge gate**.

## Authorization boundaries

Invoking land authorizes the full chain *except* the denylist. Still: push ≠ a license to
scope-creep; CI-fix stays within the PR's intent; stop cleanly at the last authorized boundary and
report the exact next action. Deploys and release/build cuts are never in scope (`ship` /
`store-release`).

## Owner Decision Brief (the only thing you ever send the owner)

Refresh item state *immediately* before asking; never re-ask something already answered; never
present a stale/red/conflicted item as decision-ready. Each brief:
- full **clickable URL + title**;
- plain-language **what changes & who benefits**;
- **why the decision is needed now**;
- **completed proof** — repro, live proof, tests, adversarial + Codex, CI, mergeability;
- **tradeoffs / residual risk / missing evidence**;
- **your opinionated recommendation + rationale** (don't offload the analysis);
- the **exact choices** (usually: land · delete · one access step · pick alternative).

## Summary (trust mechanism — it auto-merged before they read it)

```
## Land: <branch> → <merged sha | escalated | stopped>
Class: <Autonomous|Needs-owner> · Gates: adversarial <…> · Codex <clean@sha, N rounds> · live-proof <…> · CI <…>

### ⚠️ Decisions worth a look
- Refuted Codex <P?>: "<claim>" — evidence: <…>               (no code change)
- Auto-fixed <file>: <what + why it matched shipped reality>  (<sha>)
- Auto-merged <non-trivial PR>                                (revert: git revert <sha>)

### Live proof
- <command/path → observed result; redacted>

### Routine (collapsed) · Lessons written back
```
Lead with revert-worthy calls; give a sha for every autonomous edit/merge so undoing one is one
command (`rollback` consumes these).

## Honest ceiling

The mechanics (dual-signal, sha-match, branch-currency, polling, re-trigger, live-proof execution)
are ~100% reliable. The auto-fix/auto-merge is *consistent, tireless, audited* judgment — not
*better* than a careful human pass (same model, same ceiling). So: verify before editing, prove
before merging, escalate ambiguity.

## Related

`maintainer` (orchestrates many lands) · `ship` (deploy closeout) · `rollback` (undo a bad land) ·
`remember`/`recall` (lessons write-back/preflight) · `references/denylist.md`.
