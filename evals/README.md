# Doctrine evals

The test suites prove the machinery: the installer writes what it claims, the brain protocol
survives concurrent writers, the scheduler declaration converges. None of them proves the thing
the system exists for — that an agent reading the doctrine behaves differently from one that
never saw it.

That gap has bitten before. A rule sat at the top of a context file for weeks and never fired,
and it surfaced by accident (`lessons/name-a-standard-and-it-will-not-fire`). These evals close
it by measuring behavior instead of text.

## What an eval measures

Each eval runs the same task twice: once with the Borrowed Fire skills installed (`doctrine`
arm) and once with an empty skill set (`bare` arm). The result that matters is the **gap**.

| eval | doctrine rule under test | mechanical pass condition | kind |
|---|---|---|---|
| `recall-preflight` | consult the brain's lessons before substantive repo work | a read of `lessons/` precedes the first write of any kind | discriminator |
| `reflect-capture` | a task establishing a durable gotcha captures one lesson with a prevention class | a changed `lessons/` page carries a `Prevention:` line | discriminator |
| `writing-semicolons` | prefer a period to a semicolon | zero semicolons in the deliverable's prose | discriminator |
| `reflect-noop` | a trivial task captures nothing; a clean no-op is success | the seeded brain tree is unchanged | guard |

A **discriminator** should differ between the arms: the bare arm has no reason to read a brain
it was never told about, and no reason to prefer a period. A **guard** should pass in both — the
bare arm has no `reflect` to run, so it cannot manufacture memory, and the point is that
installing the doctrine does not start manufacturing it either. Read a guard's equal columns as
"no regression", and a discriminator's equal columns as "this rule is not doing any work".

Every condition is a property of the transcript or of the files the session left behind. No
model judges another model's output, so a run is reproducible and cheap to argue with.

Read the results the way the runner prints them: **a discriminator is firing when `doctrine`
passes and `bare` does not.** Equal columns on a discriminator mean the behavior was not
produced by the doctrine — the model would have done it anyway, and the rule is decoration. A
rule that fails in both arms is not reaching the agent at all.

## Running it

```sh
export ANTHROPIC_API_KEY=...        # required, see Isolation
evals/run.sh                        # 4 evals x 2 arms x 2 repeats = 16 sessions
evals/run.sh --evals recall-preflight --repeats 4 --keep
```

Flags: `--evals a,b` · `--arms doctrine,bare` · `--repeats N` · `--model M` · `--keep` (keep the
transcripts for inspection).

**This is a pre-release gate, not a CI step.** Every cell is a real agent session that costs
real money and takes real time, and the results are noisy at small `N`. Run it before a release
that touches doctrine, the memory skills, or the writing standard. `tests/test-evals.sh` runs in
CI instead: it proves the scorer against recorded transcripts and costs nothing.

## Isolation

Each cell gets a throwaway `HOME`, a fresh git workspace, and its own brain seeded from
`prometheus-template/`. The `doctrine` arm installs the skills into that `HOME` with
`install.sh --copy`; the `bare` arm installs nothing. The two arms differ by exactly one thing.

The runner requires `ANTHROPIC_API_KEY` and has no fallback. A sandbox `HOME` cannot use the
interactive login, because OAuth credentials live in the system keychain rather than in the home
directory. Running against the operator's real `HOME` would load their own skills into *both*
arms, so the bare arm would silently measure the doctrine too. Ponytail's benchmark shipped that
exact bug — a `SessionStart` hook fired on every arm, and the baseline was secretly running the
skill under test — and caught it only after nearly publishing a 4% result. The runner refuses
that configuration rather than reporting a number it cannot stand behind.

## Adding an eval

1. Add a `prompt_for` case in `run.sh` — one task, stated the way a user would state it. Never
   name the rule in the prompt. Asking "remember to check lessons first" measures instruction
   following, not whether the doctrine fires on its own.
2. Add a scorer in `score.py` returning `(passed, evidence)`. Read the transcript's tool calls
   or the files on disk. If a check needs a model to judge it, it is not ready to be an eval.
3. Add fixtures to `tests/test-evals.sh` covering a passing case, a failing case, and the
   near-miss you expect to get wrong.

## Honest limits

- **Small N.** The default of 2 repeats detects a large gap, not a small one. A one-cell
  difference is noise. Raise `--repeats` before believing a narrow result.
- **Four rules of many.** The doctrine says more than these evals measure. An unmeasured rule is
  unproven, not proven-absent.
- **Prompts age.** A task the model learns to do unprompted stops discriminating between the
  arms. A converged eval should be replaced, not celebrated.
- **The scorer is a proxy.** `recall-preflight` proves that `lessons/` was read before a write,
  not that the lesson changed the fix. That is the honest ceiling of a mechanical check.
