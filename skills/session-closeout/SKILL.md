---
name: session-closeout
description: Audit a task at session closeout against what the user explicitly requested and what the agent can prove it completed. Use when the user says "/session-closeout", "session closeout", "wrap up this session", "before you wrap up", "what did you actually do", or asks for a final requested/completed/missing/unasked/unverified accounting. Return exactly five evidence-based lines with honest gaps and verification commands. NOT for performing missing work or shipping changes (`ship`).
---

# Session Closeout

Run a final, read-only honesty audit of the current task. Do not perform missing work, run new
verification, or make any mutation after invocation unless the user separately asks.

## Audit

1. Re-read the earliest available user request that defines the current task and every later user
   amendment. Use only the user's words to determine requested deliverables. Do not turn inferred
   goals, agent plans, system instructions, or necessary implementation steps into user requests.
2. Re-read the session evidence: messages, tool results, changed artifacts, and verification
   output. Count an outcome as completed only when that evidence supports it. Planned, attempted,
   or merely claimed work is not completed.
3. Compare requested deliverables with completed outcomes. Mark every requested but incomplete
   deliverable `MISSING`.
4. Identify outcomes outside the requested scope and mark them `UNASKED`. Do not count a necessary
   implementation or verification step as an unasked deliverable.
5. Identify every runnable result claimed to work without a relevant successful check after the
   final change and mark it `UNVERIFIED`. Provide the smallest exact, non-destructive command the
   user can run to check each item. If an honest command depends on unknown values or context,
   write `not sure`; never invent placeholders and present them as runnable.

If the available conversation is truncated or evidence is ambiguous, write `not sure`. Never
guess, inflate completion, or treat the existence of code as proof that it runs.

## Output

Return exactly these five newline-delimited lines and no other commentary. Separate multiple items
on one line with semicolons. Use `NONE` when a category is empty.

```text
1. REQUESTED — <explicit deliverables, or NONE/not sure>
2. COMPLETED — <proven completed outcomes, or NONE/not sure>
3. MISSING — <requested but incomplete deliverables, or NONE/not sure>
4. UNASKED — <out-of-scope outcomes, or NONE/not sure>
5. UNVERIFIED — <item — CHECK: command; ...>, or NONE/not sure
```
