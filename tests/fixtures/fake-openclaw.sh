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
if [ "${FAKE_OPENCLAW_FAIL_AGENTS_LIST:-0}" -eq 1 ] && [ "${1:-}" = "agents" ] && [ "${2:-}" = "list" ]; then
  exit 9
fi
if [ "${FAKE_OPENCLAW_FAIL_SKILLS_CHECK:-0}" -eq 1 ] && [ "${1:-}" = "skills" ] && [ "${2:-}" = "check" ]; then
  exit 9
fi
if [ "${FAKE_OPENCLAW_FAIL_ENABLE_AFTER_COMMIT:-0}" -eq 1 ] && [ "${1:-}" = "cron" ] && [ "${2:-}" = "enable" ]; then
  exit 9
fi
if [ "${FAKE_OPENCLAW_FAIL_DISABLE:-0}" -eq 1 ] && [ "${1:-}" = "cron" ] && [ "${2:-}" = "disable" ]; then
  exit 9
fi
if [ "${FAKE_OPENCLAW_FAIL_STATUS:-0}" -eq 1 ] && [ "${1:-}" = "cron" ] && [ "${2:-}" = "status" ]; then
  exit 9
fi
if [ "${FAKE_OPENCLAW_FAIL_ADD:-0}" -eq 1 ] && [ "${1:-}" = "cron" ] && [ "${2:-}" = "add" ]; then
  exit 9
fi
if [ "${1:-}" = "--version" ]; then
  printf '%s\n' "${FAKE_OPENCLAW_VERSION:-OpenClaw fixture-1}"
  exit 0
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
if [ "${1:-}" = "agents" ] && [ "${2:-}" = "bindings" ]; then
  printf '%s\n' "${FAKE_OPENCLAW_BINDINGS:-[]}"
  exit 0
fi
if [ "${1:-}" = "config" ] && [ "${2:-}" = "get" ]; then
  if [ -n "${FAKE_OPENCLAW_CHANNEL_CONFIG:-}" ]; then
    printf '%s\n' "$FAKE_OPENCLAW_CHANNEL_CONFIG"
  elif [ -n "${OPENCLAW_CONFIG_PATH:-}" ] && [ -f "$OPENCLAW_CONFIG_PATH" ]; then
    python3 - "$OPENCLAW_CONFIG_PATH" <<'PY'
import json
import sys

try:
    root = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    root = {}
print(json.dumps(((root.get("channels") or {}).get("imessage") or {})))
PY
  else
    printf '%s\n' '{}'
  fi
  exit 0
fi
if [ "${1:-}" = "channels" ] && [ "${2:-}" = "status" ]; then
  if [ -n "${FAKE_OPENCLAW_CHANNEL_STATUS:-}" ]; then
    printf '%s\n' "$FAKE_OPENCLAW_CHANNEL_STATUS"
  else
    printf '%s\n' '{"channelDefaultAccountId":{"imessage":"default"},"channelAccounts":{"imessage":[{"accountId":"default","configured":true,"enabled":true}]}}'
  fi
  exit 0
fi
if [ "${1:-}" = "skills" ] && [ "${2:-}" = "check" ]; then
  agent="main"
  previous=""
  for value in "$@"; do
    if [ "$previous" = "--agent" ]; then agent="$value"; fi
    previous="$value"
  done
  if [ "$agent" = "alternate" ]; then
    workspace="${FAKE_OPENCLAW_ALT_WORKSPACE:-${FAKE_OPENCLAW_WORKSPACE:?}}"
  else
    workspace="${FAKE_OPENCLAW_WORKSPACE:?}"
  fi
  if [ "${FAKE_OPENCLAW_SKILLS_HIDDEN:-0}" -eq 1 ]; then
    visible='["recall","digest"]'
  else
    visible='["borrowedfire-learn","remember","recall","digest"]'
  fi
  python3 - "$agent" "$workspace" "$visible" <<'PY'
import json
import sys
print(json.dumps({"agentId": sys.argv[1], "workspaceDir": sys.argv[2], "modelVisible": json.loads(sys.argv[3])}))
PY
  exit 0
fi
if [ "${1:-}" = "message" ] && [ "${2:-}" = "send" ]; then
  if [ "${FAKE_OPENCLAW_FAIL_MESSAGE:-0}" -eq 1 ]; then
    exit 10
  fi
  if [ "${FAKE_OPENCLAW_MESSAGE_NO_ACK:-0}" -eq 1 ]; then
    printf '{"channel":"imessage","ok":true}\n'
  elif [ "${FAKE_OPENCLAW_MESSAGE_PLACEHOLDER_ACK:-0}" -eq 1 ]; then
    printf '%s\n' '{"action":"send","channel":"imessage","messageId":"ok","payload":{"messageId":"ok","ok":true}}'
  elif [ "${FAKE_OPENCLAW_MESSAGE_ERROR_WITH_ACK:-0}" -eq 1 ]; then
    printf '%s\n' '{"action":"send","channel":"imessage","messageId":"generated-on-error","payload":{"ok":false,"error":"provider rejected route","messageId":"generated-on-error"}}'
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
  if [ "${FAKE_OPENCLAW_LIST_TRUNCATED:-0}" -eq 1 ]; then
    printf '{"jobs":[{"id":"other-job","declarationKey":"other.declaration","enabled":true}],"total":201,"offset":0,"limit":200,"hasMore":true,"nextOffset":200}\n'
  else
    python3 - "$OPENCLAW_ARGS_FILE" "${FAKE_OPENCLAW_DUPLICATE_DECLARATIONS:-0}" <<'PY'
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
removed = {call[2] for call in calls if len(call) >= 3 and call[:2] == ["cron", "rm"]}
jobs = [
    {
        "id": "fixture-job",
        "declarationKey": "borrowedfire.prometheus-learning.v1",
        "agentId": "main",
        "enabled": True,
    }
]
if sys.argv[2] == "1":
    jobs.append({
        "id": "duplicate-job",
        "declarationKey": "borrowedfire.prometheus-learning.v1",
        "agentId": "alternate",
        "enabled": True,
    })
jobs = [job for job in jobs if job["id"] not in removed]
print(json.dumps({
    "jobs": jobs,
    "total": len(jobs),
    "offset": 0,
    "limit": 200,
    "hasMore": False,
    "nextOffset": None,
}))
PY
  fi
  exit 0
fi
if [ "${1:-}" = "cron" ] && [ "${2:-}" = "get" ]; then
  get_mismatch="${FAKE_OPENCLAW_GET_MISMATCH:-0}"
  [ "${FAKE_OPENCLAW_STALE_SESSION_KEY:-0}" -eq 0 ] || get_mismatch="session"
  python3 - "$OPENCLAW_ARGS_FILE" "$get_mismatch" "${FAKE_OPENCLAW_POST_ENABLE_MISMATCH:-0}" "${3:-fixture-job}" <<'PY'
import json
import os
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

if os.environ.get("FAKE_OPENCLAW_RESTRICTED_TOOLS") == "1":
    tools_allow = ["read"]
elif "--clear-tools" in lines:
    tools_allow = None if os.environ.get("FAKE_OPENCLAW_LEGACY_CLEAR_TOOLS") == "1" else ["*"]
else:
    tools_allow = last_value("--tools").replace(",", " ").split()

print(json.dumps({
    "id": sys.argv[4],
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
        "accountId": last_value("--account"),
        "threadId": None,
    },
    "failureAlert": {
        "after": 2,
        "cooldownMs": 43200000,
        "includeSkipped": True,
        "mode": "announce",
        "channel": last_value("--failure-alert-channel"),
        "to": last_value("--failure-alert-to"),
        "accountId": last_value("--failure-alert-account-id"),
    },
    "payload": {
        "kind": "agentTurn",
        "message": last_value("--message"),
        "timeoutSeconds": 900,
        "lightContext": False,
        "toolsAllow": tools_allow,
    },
}))
PY
  exit 0
fi
if [ "${FAKE_OPENCLAW_ADD_NO_ID:-0}" -eq 1 ] && [ "${1:-}" = "cron" ] && [ "${2:-}" = "add" ]; then
  printf '{"job":{"declarationKey":"borrowedfire.prometheus-learning.v1"}}\n'
  exit 0
fi
printf '{"id":"fixture-job","declarationKey":"borrowedfire.prometheus-learning.v1"}\n'
