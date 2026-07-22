---
type: note
created: 1970-01-01
updated: 1970-01-01
tags: [config, fleet]
status: active
---

# Fleet configuration

Instance config for tier routing. Skills (`maintainer` in particular) read this to decide where
work runs and where paid tokens may be spent. Fill in your own values — this file lives only in
your private brain.

## Execution tiers

| Tier | Endpoint / harness | Use for |
|---|---|---|
| local-quality | `http://<host>:<port>/v1` (`<quality-model>`, <context> context) | quality-first repository coding and difficult local implementation |
| local-volume | `http://<host>:<port>/v1` (`<volume-model>`, <context> context) | bulk edits, first drafts, summarize/triage/format |
| judgment | <paid harness: Claude / Codex> | PR review, planning, escalation, owner briefs |

## Router settings

- Controller SSH host: `<ssh-alias>`

## Paid-usage policy

- Paid task whitelist: review, plan, escalate. Everything else defaults to local.
- Escalation cap: <N> retries before an owner brief instead of another paid call.
- Monthly cap note: <where your usage ledger lives, if you track one>.

## Machines

| Host | Role | Notes |
|---|---|---|
| <hostname> | <control-plane / worker / build> | <e.g. only node that can build platform X> |
