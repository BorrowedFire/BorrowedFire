#!/usr/bin/env bash
set -u
: "${OPENCLAW_ARGS_FILE:?OPENCLAW_ARGS_FILE is required}"
{
  printf '%s\n' CALL
  printf '%s\n' "$@"
} >> "$OPENCLAW_ARGS_FILE"

if [ "${FAKE_OPENCLAW_FAIL_EDIT:-0}" -eq 1 ] && [ "${1:-}" = "cron" ] && [ "${2:-}" = "edit" ]; then
  exit 9
fi
if [ "${1:-}" = "cron" ] && [ "${2:-}" = "status" ]; then
  if [ "${FAKE_OPENCLAW_SCHEDULER_DISABLED:-0}" -eq 1 ]; then
    printf '{"enabled":false}\n'
  else
    printf '{"enabled":true}\n'
  fi
  exit 0
fi
if [ "${1:-}" = "cron" ] && [ "${2:-}" = "get" ]; then
  python3 - "$OPENCLAW_ARGS_FILE" "${FAKE_OPENCLAW_GET_MISMATCH:-0}" <<'PY'
import json
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
mismatch = sys.argv[2] == "1"

def last_value(flag):
    values = [lines[index + 1] for index, value in enumerate(lines[:-1]) if value == flag]
    return values[-1] if values else ""

print(json.dumps({
    "id": "fixture-job",
    "declarationKey": "borrowedfire.prometheus-learning.v1",
    "enabled": False,
    "agentId": last_value("--agent"),
    "sessionTarget": "isolated",
    "schedule": {
        "kind": "cron",
        "expr": last_value("--cron"),
        "tz": last_value("--tz"),
    },
    "delivery": {
        "mode": "none",
        "channel": last_value("--channel"),
        "to": "wrong-route" if mismatch else last_value("--to"),
    },
    "failureAlert": {
        "after": 2,
        "includeSkipped": True,
        "channel": last_value("--failure-alert-channel"),
        "to": last_value("--failure-alert-to"),
    },
}))
PY
  exit 0
fi
printf '{"id":"fixture-job","declarationKey":"borrowedfire.prometheus-learning.v1"}\n'
