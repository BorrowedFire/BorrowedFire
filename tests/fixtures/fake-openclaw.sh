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
if [ "${FAKE_OPENCLAW_FAIL_ENABLE_AFTER_COMMIT:-0}" -eq 1 ] && [ "${1:-}" = "cron" ] && [ "${2:-}" = "enable" ]; then
  exit 9
fi
if [ "${FAKE_OPENCLAW_FAIL_DISABLE:-0}" -eq 1 ] && [ "${1:-}" = "cron" ] && [ "${2:-}" = "disable" ]; then
  exit 9
fi
if [ "${1:-}" = "agents" ] && [ "${2:-}" = "list" ]; then
  if [ "${FAKE_OPENCLAW_UNKNOWN_AGENT:-0}" -eq 1 ]; then
    printf '[{"id":"different","workspace":"%s"}]\n' "${FAKE_OPENCLAW_WORKSPACE:?}"
  else
    printf '[{"id":"main","workspace":"%s"},{"id":"alternate","workspace":"%s"}]\n' \
      "${FAKE_OPENCLAW_WORKSPACE:?}" "${FAKE_OPENCLAW_ALT_WORKSPACE:-${FAKE_OPENCLAW_WORKSPACE:?}}"
  fi
  exit 0
fi
if [ "${1:-}" = "message" ] && [ "${2:-}" = "send" ]; then
  if [ "${FAKE_OPENCLAW_FAIL_MESSAGE:-0}" -eq 1 ]; then
    exit 10
  fi
  if [ "${FAKE_OPENCLAW_MESSAGE_NO_ACK:-0}" -eq 1 ]; then
    printf '{"channel":"imessage","ok":true}\n'
  else
    if [ -n "${FAKE_OPENCLAW_POISON_ROUTE_PROOF:-}" ]; then
      mkdir "${FAKE_OPENCLAW_POISON_ROUTE_PROOF}"
    fi
    printf '{"channel":"imessage","result":{"messageId":"fixture-message"}}\n'
  fi
  exit 0
fi
if [ "${1:-}" = "cron" ] && [ "${2:-}" = "status" ]; then
  if [ "${FAKE_OPENCLAW_SCHEDULER_DISABLED:-0}" -eq 1 ]; then
    printf '{"enabled":false}\n'
  else
    printf '{"enabled":true}\n'
  fi
  exit 0
fi
if [ "${1:-}" = "cron" ] && [ "${2:-}" = "list" ]; then
  printf '{"jobs":[{"id":"fixture-job","declarationKey":"borrowedfire.prometheus-learning.v1","agentId":"main","enabled":true}]}\n'
  exit 0
fi
if [ "${1:-}" = "cron" ] && [ "${2:-}" = "get" ]; then
  get_mismatch="${FAKE_OPENCLAW_GET_MISMATCH:-0}"
  [ "${FAKE_OPENCLAW_STALE_SESSION_KEY:-0}" -eq 0 ] || get_mismatch="session"
  python3 - "$OPENCLAW_ARGS_FILE" "$get_mismatch" "${FAKE_OPENCLAW_POST_ENABLE_MISMATCH:-0}" <<'PY'
import json
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()

calls = []
current = []
for line in lines:
    if line == "CALL":
        if current:
            calls.append(current)
        current = []
    else:
        current.append(line)
if current:
    calls.append(current)

enabled = False
for call in calls:
    if call[:2] == ["cron", "add"] and "--disabled" in call:
        enabled = False
    elif call[:2] == ["cron", "enable"]:
        enabled = True
    elif call[:2] == ["cron", "disable"]:
        enabled = False

mismatch = sys.argv[2] == "1" or (enabled and sys.argv[3] == "1")

def last_value(flag):
    values = [
        call[index + 1]
        for call in calls
        if call[:2] in (["cron", "add"], ["cron", "edit"])
        for index, value in enumerate(call[:-1])
        if value == flag
    ]
    return values[-1] if values else ""

print(json.dumps({
    "id": "fixture-job",
    "declarationKey": "borrowedfire.prometheus-learning.v1",
    "name": last_value("--name"),
    "displayName": last_value("--display-name"),
    "description": last_value("--description"),
    "enabled": enabled,
    "agentId": last_value("--agent"),
    "sessionTarget": "isolated",
    "sessionKey": "stale-session" if sys.argv[2] == "session" or "--clear-session-key" not in lines else None,
    "wakeMode": last_value("--wake"),
    "schedule": {
        "kind": "cron",
        "expr": last_value("--cron"),
        "tz": last_value("--tz"),
    },
    "delivery": {
        "mode": "none",
        "channel": last_value("--channel"),
        "to": "wrong-route" if mismatch else last_value("--to"),
        "threadId": None,
    },
    "failureAlert": {
        "after": 2,
        "cooldownMs": 43200000,
        "includeSkipped": True,
        "mode": "announce",
        "channel": last_value("--failure-alert-channel"),
        "to": last_value("--failure-alert-to"),
    },
    "payload": {
        "kind": "agentTurn",
        "message": last_value("--message"),
        "timeoutSeconds": 900,
        "lightContext": False,
        "toolsAllow": last_value("--tools").replace(",", " ").split(),
    },
}))
PY
  exit 0
fi
printf '{"id":"fixture-job","declarationKey":"borrowedfire.prometheus-learning.v1"}\n'
