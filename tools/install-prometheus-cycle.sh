#!/usr/bin/env bash
# Declare the unattended Prometheus learning cycle on one always-on OpenClaw host.
# Uses OpenClaw's declaration key so re-running updates one job instead of creating duplicates.
set -u

SRC="$(cd "$(dirname "$0")/.." && pwd -P)"
OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
BRAIN=""
CRON_EXPR="35 3 * * *"
TIMEZONE="America/New_York"
AGENT_ID="main"
NOTIFY_CHANNEL=""
NOTIFY_TO=""
DRY=0
ROUTE_PROOF_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/borrowedfire/prometheus-learning-route.sha256"

is_git_checkout() {
  local requested top
  [ -d "$1" ] || return 1
  requested="$(cd "$1" && pwd -P)" || return 1
  top="$(git -C "$requested" rev-parse --show-toplevel 2>/dev/null)" || return 1
  top="$(cd "$top" && pwd -P)" || return 1
  [ "$requested" = "$top" ]
}

is_prometheus_root() {
  is_git_checkout "$1" &&
    [ -f "$1/INDEX.md" ] &&
    [ -f "$1/config/fleet.md" ] &&
    [ -f "$1/.gitattributes" ] &&
    grep -qxF 'journal/*.md merge=union' "$1/.gitattributes" &&
    grep -qxF 'inbox/*.md merge=union' "$1/.gitattributes" &&
    grep -qxF 'projects/*.md merge=union' "$1/.gitattributes"
}

managed_learning_stack_matches() {
  python3 - "$SRC" "$1" <<'PY'
import os
import stat
import sys
from pathlib import Path

source_root = Path(sys.argv[1]).resolve()
workspace = Path(sys.argv[2]).resolve()
skills = ("borrowedfire-learn", "remember", "recall", "digest")
manifest_path = workspace / "skills" / ".borrowedfire-manifest"

try:
    lines = manifest_path.read_text(encoding="utf-8").splitlines()
except OSError:
    raise SystemExit(1)

manifest = {}
for line in lines:
    parts = line.split()
    if len(parts) != 2 or parts[0] in manifest:
        raise SystemExit(1)
    manifest[parts[0]] = parts[1]

def tree_entries(root, ignore_marker=False):
    entries = {}
    for base, dirs, files in os.walk(root, followlinks=False):
        base_path = Path(base)
        for name in dirs + files:
            if ignore_marker and name == ".borrowedfire-copy":
                continue
            path = base_path / name
            relative = path.relative_to(root).as_posix()
            info = path.lstat()
            if stat.S_ISDIR(info.st_mode):
                entries[relative] = ("dir", None)
            elif stat.S_ISREG(info.st_mode):
                entries[relative] = ("file", path.read_bytes())
            elif stat.S_ISLNK(info.st_mode):
                entries[relative] = ("link", os.readlink(path))
            else:
                raise SystemExit(1)
    return entries

for name in skills:
    source = source_root / "skills" / name
    target = workspace / "skills" / name
    mode = manifest.get(name)
    if mode == "link":
        if not target.is_symlink() or os.readlink(target) != str(source):
            raise SystemExit(1)
    elif mode == "copy":
        marker = target / ".borrowedfire-copy"
        if target.is_symlink() or not target.is_dir() or not marker.is_file():
            raise SystemExit(1)
        if tree_entries(source) != tree_entries(target, ignore_marker=True):
            raise SystemExit(1)
    else:
        raise SystemExit(1)

try:
    doctrine = (source_root / "doctrine" / "DOCTRINE.md").read_text(encoding="utf-8")
    context = (workspace / "AGENTS.md").read_text(encoding="utf-8")
except OSError:
    raise SystemExit(1)
if context.count(doctrine) != 1:
    raise SystemExit(1)
PY
}

usage() {
  printf '%s\n' \
    "usage: $0 [--brain <path>] [--agent <id>] [--cron <expression>] [--tz <iana-zone>]" \
    "          --notify-channel <channel> --notify-to <destination> [--dry-run]" \
    "" \
    "Declares one nightly OpenClaw agent job. Provider/model selection remains in private" \
    "fleet configuration; this public installer does not pin either."
}

while [ $# -gt 0 ]; do
  case "$1" in
    --brain) shift; BRAIN="${1:-}" ;;
    --agent) shift; AGENT_ID="${1:-}" ;;
    --cron) shift; CRON_EXPR="${1:-}" ;;
    --tz) shift; TIMEZONE="${1:-}" ;;
    --notify-channel) shift; NOTIFY_CHANNEL="${1:-}" ;;
    --notify-to) shift; NOTIFY_TO="${1:-}" ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$DRY" -eq 0 ] && ! command -v "$OPENCLAW_BIN" >/dev/null 2>&1; then
  printf 'OpenClaw CLI not found: %s\n' "$OPENCLAW_BIN" >&2
  exit 1
fi
if [ "$DRY" -eq 0 ] && ! command -v python3 >/dev/null 2>&1; then
  printf 'python3 is required to validate the OpenClaw declaration response.\n' >&2
  exit 1
fi
JOB_NAME="Prometheus Learning Cycle"
DECLARATION_KEY="borrowedfire.prometheus-learning.v1"
DESCRIPTION="Nightly verified learning, status capture, and due-only consolidation in the shared Prometheus brain."

job_enabled_state_is() {
  local job_id="$1" expected="$2" verify_output
  verify_output="$("$OPENCLAW_BIN" cron get "$job_id")" || return 1
  printf '%s' "$verify_output" | python3 -c '
import json
import sys

expected_id, expected_text = sys.argv[1:]
try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)
job = payload.get("job") if isinstance(payload, dict) and isinstance(payload.get("job"), dict) else payload
expected = expected_text == "true"
if not isinstance(job, dict) or job.get("id") != expected_id or job.get("enabled") is not expected:
    raise SystemExit(1)
' "$job_id" "$expected"
}

disable_job_and_verify() {
  local job_id="$1"
  "$OPENCLAW_BIN" cron disable "$job_id" >/dev/null 2>&1 || return 1
  job_enabled_state_is "$job_id" false
}

read_declaration_inventory() {
  local destination="$1" list_output
  list_output="$("$OPENCLAW_BIN" cron list --all --json)" || return 1
  printf '%s' "$list_output" | python3 -c '
import json
import re
import sys

declaration_key = sys.argv[1]
try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)
jobs = payload if isinstance(payload, list) else payload.get("jobs") if isinstance(payload, dict) else None
if not isinstance(jobs, list):
    raise SystemExit(1)
if isinstance(payload, dict):
    has_more = payload.get("hasMore")
    if has_more not in (None, False):
        raise SystemExit(1)
    total = payload.get("total")
    offset = payload.get("offset", 0)
    if isinstance(total, int) and isinstance(offset, int) and total > offset + len(jobs):
        raise SystemExit(1)
matches = [
    job for job in jobs
    if isinstance(job, dict)
    and job.get("declarationKey") == declaration_key
]
for job in matches:
    job_id = job.get("id")
    agent_id = job.get("agentId")
    if (
        not isinstance(job_id, str)
        or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]*", job_id)
        or not isinstance(agent_id, str)
        or "\n" in agent_id
        or "\t" in agent_id
    ):
        raise SystemExit(1)
    print(f"{job_id}\t{agent_id}")
' "$DECLARATION_KEY" > "$destination"
}

disable_existing_declaration() {
  local inventory job_id _agent_id failed=0
  inventory="$(mktemp)" || return 1
  if ! read_declaration_inventory "$inventory"; then
    rm -f "$inventory"
    return 1
  fi
  while IFS=$'\t' read -r job_id _agent_id; do
    [ -n "$job_id" ] || continue
    disable_job_and_verify "$job_id" || failed=1
  done < "$inventory"
  rm -f "$inventory"
  [ "$failed" -eq 0 ]
}

declaration_is_absent_or_single_for_agent() {
  local inventory expected_agent="$1" count=0 job_id agent_id matched=0
  inventory="$(mktemp)" || return 1
  if ! read_declaration_inventory "$inventory"; then
    rm -f "$inventory"
    return 1
  fi
  while IFS=$'\t' read -r job_id agent_id; do
    [ -n "$job_id" ] || continue
    count=$((count + 1))
    [ "$agent_id" = "$expected_agent" ] && matched=1
  done < "$inventory"
  rm -f "$inventory"
  [ "$count" -eq 0 ] || { [ "$count" -eq 1 ] && [ "$matched" -eq 1 ]; }
}

remove_existing_declarations() {
  local inventory job_id _agent_id failed=0 remaining
  inventory="$(mktemp)" || return 1
  if ! read_declaration_inventory "$inventory"; then
    rm -f "$inventory"
    return 1
  fi
  while IFS=$'\t' read -r job_id _agent_id; do
    [ -n "$job_id" ] || continue
    if ! disable_job_and_verify "$job_id" ||
       ! "$OPENCLAW_BIN" cron rm "$job_id" >/dev/null 2>&1; then
      failed=1
    fi
  done < "$inventory"
  rm -f "$inventory"
  [ "$failed" -eq 0 ] || return 1
  remaining="$(mktemp)" || return 1
  if ! read_declaration_inventory "$remaining"; then
    rm -f "$remaining"
    return 1
  fi
  if [ -s "$remaining" ]; then
    rm -f "$remaining"
    return 1
  fi
  rm -f "$remaining"
}

fail_declaration_safely() {
  local reason="$1"
  if disable_existing_declaration; then
    printf '%s Any existing declaration-key learning job is verified disabled or absent.\n' "$reason" >&2
  else
    printf '%s The matching job could not be proven disabled; inspect OpenClaw before re-enabling it.\n' "$reason" >&2
  fi
  exit 1
}

if ! command -v git >/dev/null 2>&1; then
  if [ "$DRY" -eq 0 ]; then
    fail_declaration_safely 'git is unavailable, so Prometheus cannot be resolved or validated.'
  fi
  printf 'git is required to resolve and validate Prometheus.\n' >&2
  exit 1
fi
if [ -z "$BRAIN" ] && [ -n "${PROMETHEUS_DIR:-}" ]; then
  BRAIN="$PROMETHEUS_DIR"
fi
if [ -z "$BRAIN" ] && [ -f "$HOME/.config/borrowedfire/brain" ]; then
  IFS= read -r BRAIN < "$HOME/.config/borrowedfire/brain"
fi
if [ -z "$BRAIN" ] && is_git_checkout "$HOME/prometheus"; then
  BRAIN="$HOME/prometheus"
fi
if [ -z "$BRAIN" ] || ! is_prometheus_root "$BRAIN"; then
  if [ "$DRY" -eq 0 ]; then
    fail_declaration_safely 'Prometheus brain root/schema not found; pass its exact Git root or configure ~/.config/borrowedfire/brain.'
  fi
  printf 'Prometheus brain root/schema not found; pass its exact Git root or configure ~/.config/borrowedfire/brain.\n' >&2
  exit 1
fi
BRAIN="$(cd "$BRAIN" && pwd -P)"

if [ -z "$AGENT_ID" ] || [ -z "$NOTIFY_CHANNEL" ] || [ -z "$NOTIFY_TO" ]; then
  if [ "$DRY" -eq 0 ]; then
    fail_declaration_safely 'Agent id, notification channel, and notification destination must not be blank.'
  fi
  printf 'agent id, notification channel, and notification destination must not be blank.\n' >&2
  exit 1
fi
if ! printf '%s' "$NOTIFY_CHANNEL" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_-]*$'; then
  if [ "$DRY" -eq 0 ]; then
    fail_declaration_safely 'Notification channel must be one concrete OpenClaw channel id.'
  fi
  printf 'notification channel must be one concrete OpenClaw channel id.\n' >&2
  exit 1
fi

if [ "$DRY" -eq 1 ]; then
  printf 'would declare %s (%s) at %s [%s]\n' "$JOB_NAME" "$DECLARATION_KEY" "$CRON_EXPR" "$TIMEZONE"
  printf 'Prometheus: %s\n' "$BRAIN"
  printf 'Agent: %s; notification channel: %s; explicit destination configured\n' "$AGENT_ID" "$NOTIFY_CHANNEL"
  exit 0
fi

AGENTS_OUTPUT="$("$OPENCLAW_BIN" agents list --json)" ||
  fail_declaration_safely 'Configured OpenClaw agents could not be inspected.'
AGENT_WORKSPACE="$(printf '%s' "$AGENTS_OUTPUT" | python3 -c '
import json
import sys

requested = sys.argv[1]
try:
    agents = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)
if not isinstance(agents, list):
    raise SystemExit(1)
matches = [item for item in agents if isinstance(item, dict) and item.get("id") == requested]
if len(matches) != 1 or not isinstance(matches[0].get("workspace"), str) or not matches[0]["workspace"].strip():
    raise SystemExit(1)
print(matches[0]["workspace"].strip())
' "$AGENT_ID")" || {
  fail_declaration_safely 'Requested OpenClaw agent is not configured with one concrete workspace.'
}
if [ ! -d "$AGENT_WORKSPACE" ]; then
  fail_declaration_safely 'Requested OpenClaw agent workspace does not exist.'
fi
AGENT_WORKSPACE="$(cd "$AGENT_WORKSPACE" && pwd -P)"
if ! managed_learning_stack_matches "$AGENT_WORKSPACE"; then
  fail_declaration_safely 'Requested OpenClaw workspace lacks the exact installer-managed learning stack and doctrine from this checkout.'
fi
SKILLS_OUTPUT="$("$OPENCLAW_BIN" skills check --agent "$AGENT_ID" --json)" ||
  fail_declaration_safely 'Effective OpenClaw skill visibility could not be inspected for the requested agent.'
if ! printf '%s' "$SKILLS_OUTPUT" | python3 -c '
import json
import os
import sys

expected_agent, expected_workspace = sys.argv[1:]
required = {"borrowedfire-learn", "remember", "recall", "digest"}
try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)
visible = payload.get("modelVisible") if isinstance(payload, dict) else None
if (
    not isinstance(payload, dict)
    or payload.get("agentId") != expected_agent
    or not isinstance(payload.get("workspaceDir"), str)
    or os.path.realpath(payload["workspaceDir"]) != os.path.realpath(expected_workspace)
    or not isinstance(visible, list)
    or not all(isinstance(item, str) for item in visible)
    or not required.issubset(set(visible))
):
    raise SystemExit(1)
' "$AGENT_ID" "$AGENT_WORKSPACE"; then
  fail_declaration_safely 'The requested agent cannot see the complete learning skill stack; use a copy install or configure trusted symlink targets and agent skill visibility.'
fi

AGENT_BINDINGS_OUTPUT="$("$OPENCLAW_BIN" agents bindings --agent "$AGENT_ID" --json)" ||
  fail_declaration_safely 'Effective account bindings could not be inspected for the requested agent.'
CHANNEL_CONFIG_OUTPUT="$("$OPENCLAW_BIN" config get "channels.$NOTIFY_CHANNEL" --json)" ||
  fail_declaration_safely 'Effective notification-channel configuration could not be inspected.'
CHANNEL_STATUS_OUTPUT="$("$OPENCLAW_BIN" channels status --json)" ||
  fail_declaration_safely 'Effective notification-channel account status could not be inspected.'
OPENCLAW_VERSION_OUTPUT="$("$OPENCLAW_BIN" --version)" ||
  fail_declaration_safely 'OpenClaw runtime version could not be inspected.'
OPENCLAW_BASE_HOME="${OPENCLAW_HOME:-$HOME}"
OPENCLAW_CONFIG_FILE_OUTPUT="$("$OPENCLAW_BIN" config file)" ||
  fail_declaration_safely 'Active OpenClaw config path could not be inspected.'
OPENCLAW_ACTIVE_CONFIG_PATH="$(printf '%s' "$OPENCLAW_CONFIG_FILE_OUTPUT" | python3 -c '
import os
import re
import sys

base_home = os.path.realpath(os.path.abspath(os.path.expanduser(sys.argv[1])))
ansi = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
lines = [ansi.sub("", line).strip() for line in sys.stdin.read().splitlines()]
lines = [line for line in lines if line]
if not lines:
    raise SystemExit(1)
value = lines[-1]
if value == "~":
    value = base_home
elif value.startswith("~/"):
    value = os.path.join(base_home, value[2:])
elif not os.path.isabs(value):
    raise SystemExit(1)
print(os.path.realpath(os.path.abspath(value)))
' "$OPENCLAW_BASE_HOME")" || {
  fail_declaration_safely 'OpenClaw returned no single valid active config path.'
}
EFFECTIVE_ROUTE_STATE="$(python3 - "$AGENT_ID" "$NOTIFY_CHANNEL" "$AGENT_BINDINGS_OUTPUT" \
  "$CHANNEL_CONFIG_OUTPUT" "$CHANNEL_STATUS_OUTPUT" "$OPENCLAW_VERSION_OUTPUT" <<'PY'
import hashlib
import json
import re
import sys

agent_id, channel_id, bindings_text, channel_config_text, status_text, version = sys.argv[1:]
channel = channel_id.strip().lower()

try:
    bindings = json.loads(bindings_text)
    channel_config = json.loads(channel_config_text)
    status = json.loads(status_text)
except (json.JSONDecodeError, TypeError):
    raise SystemExit(1)
if not isinstance(bindings, list) or not isinstance(channel_config, dict) or not isinstance(status, dict):
    raise SystemExit(1)

def normalize_account(value):
    if not isinstance(value, str):
        return None
    normalized = value.strip().lower()
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", normalized):
        return None
    return normalized

channel_bindings = []
for binding in bindings:
    if not isinstance(binding, dict) or binding.get("agentId") != agent_id:
        continue
    match = binding.get("match")
    if not isinstance(match, dict) or str(match.get("channel", "")).strip().lower() != channel:
        continue
    channel_bindings.append(match)

# Agent bindings route inbound traffic and may be scoped to a peer, guild, or
# team. Only one channel-wide binding can unambiguously select the account for
# an outbound owner notification. Multiple or scoped bindings deliberately
# fall back to the channel runtime default instead of depending on list order.
bound_account = None
if len(channel_bindings) == 1:
    match = channel_bindings[0]
    scoped = any(match.get(key) is not None for key in ("peer", "guildId", "teamId"))
    candidate = match.get("accountId")
    if not scoped and candidate != "*" and isinstance(candidate, str) and candidate.strip():
        bound_account = normalize_account(candidate)
        if not bound_account:
            raise SystemExit(1)

defaults = status.get("channelDefaultAccountId")
accounts_by_channel = status.get("channelAccounts")
if not isinstance(defaults, dict) or not isinstance(accounts_by_channel, dict):
    raise SystemExit(1)

default_account = None
account_records = None
for key, value in defaults.items():
    if isinstance(key, str) and key.strip().lower() == channel:
        default_account = normalize_account(value)
        break
for key, value in accounts_by_channel.items():
    if isinstance(key, str) and key.strip().lower() == channel:
        account_records = value
        break
if not default_account or not isinstance(account_records, list):
    raise SystemExit(1)

normalized_records = []
for record in account_records:
    if not isinstance(record, dict):
        raise SystemExit(1)
    account_id = normalize_account(record.get("accountId"))
    if not account_id:
        raise SystemExit(1)
    normalized_records.append({
        "accountId": account_id,
        "configured": record.get("configured"),
        "enabled": record.get("enabled"),
    })

account = bound_account or default_account
matching_records = [record for record in normalized_records if record["accountId"] == account]
if len(matching_records) != 1 or matching_records[0]["configured"] is not True or matching_records[0]["enabled"] is False:
    raise SystemExit(1)

effective = {
    "agentId": agent_id,
    "channel": channel,
    "accountId": account,
    "bindings": bindings,
    "channelConfig": channel_config,
    "channelDefaultAccountId": default_account,
    "channelAccounts": normalized_records,
    "openclawVersion": version.strip(),
}
encoded = json.dumps(effective, sort_keys=True, separators=(",", ":")).encode("utf-8")
print(account)
print(hashlib.sha256(encoded).hexdigest())
PY
)" || {
  fail_declaration_safely 'A single configured notification account could not be resolved for the requested agent and channel.'
}
NOTIFY_ACCOUNT="${EFFECTIVE_ROUTE_STATE%%$'\n'*}"
EFFECTIVE_ROUTE_CONFIG_DIGEST="${EFFECTIVE_ROUTE_STATE#*$'\n'}"
if ! printf '%s' "$NOTIFY_ACCOUNT" | grep -Eq '^[a-z0-9][a-z0-9_-]{0,63}$' ||
   ! printf '%s' "$EFFECTIVE_ROUTE_CONFIG_DIGEST" | grep -Eq '^[0-9a-f]{64}$'; then
  fail_declaration_safely 'Effective notification account/configuration identity could not be derived.'
fi

resolve_host_name() {
  local value
  if value="$(hostname -f 2>/dev/null)" && [ -n "$value" ]; then
    printf '%s\n' "$value"
  elif value="$(hostname 2>/dev/null)" && [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    return 1
  fi
}

resolve_machine_identity() {
  local value="" identity_file
  for identity_file in /etc/machine-id /var/lib/dbus/machine-id /sys/class/dmi/id/product_uuid; do
    if [ -r "$identity_file" ]; then
      IFS= read -r value < "$identity_file" || value=""
      [ -n "$value" ] && break
    fi
  done
  if [ -z "$value" ] && command -v ioreg >/dev/null 2>&1; then
    value="$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/ {print $(NF-1); exit}')" || value=""
  fi
  if [ -z "$value" ] && command -v sysctl >/dev/null 2>&1; then
    value="$(sysctl -n kern.uuid 2>/dev/null)" || value=""
  fi
  if [ -z "$value" ] && command -v hostid >/dev/null 2>&1; then
    value="$(hostid 2>/dev/null)" || value=""
  fi
  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

HOST_NAME="$(resolve_host_name)" ||
  fail_declaration_safely 'Stable host name could not be resolved; no job was declared.'
MACHINE_ID="$(resolve_machine_identity)" ||
  fail_declaration_safely 'Stable machine identity could not be resolved; no job was declared.'
OPENCLAW_PROFILE_NAME="${OPENCLAW_PROFILE:-default}"
CONTROLLER_BINDING="$(python3 - "$HOST_NAME" "$MACHINE_ID" "$AGENT_ID" "$AGENT_WORKSPACE" \
  "$OPENCLAW_BASE_HOME" "${OPENCLAW_STATE_DIR:-}" "$OPENCLAW_PROFILE_NAME" \
  "$OPENCLAW_ACTIVE_CONFIG_PATH" "$EFFECTIVE_ROUTE_CONFIG_DIGEST" <<'PY'
import hashlib
import os
import re
import sys

def slug(value, limit):
    normalized = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    normalized = normalized[:limit].rstrip("-")
    if not normalized:
        raise SystemExit(1)
    return normalized

host_name = sys.argv[1]
machine_id = sys.argv[2]
agent_id = sys.argv[3]
workspace = os.path.realpath(sys.argv[4])
base_home = os.path.realpath(os.path.expanduser(sys.argv[5]))
state_override = sys.argv[6].strip()
profile = sys.argv[7].strip() or "default"
config_path = os.path.realpath(os.path.abspath(sys.argv[8]))
effective_route_config_digest = sys.argv[9]

def resolve_openclaw_path(value):
    if value == "~":
        value = base_home
    elif value.startswith("~/"):
        value = os.path.join(base_home, value[2:])
    return os.path.realpath(os.path.abspath(value))

if state_override:
    state_dir = resolve_openclaw_path(state_override)
else:
    suffix = "" if profile.lower() == "default" else f"-{profile}"
    state_dir = os.path.join(base_home, f".openclaw{suffix}")
    state_dir = os.path.realpath(state_dir)
host = slug(host_name, 64)
agent = slug(agent_id, 48)
workspace_name = slug(os.path.basename(workspace), 64)
binding = "\0".join((host_name, machine_id, agent_id, workspace, state_dir, config_path, profile))
binding_hash = hashlib.sha256(binding.encode("utf-8")).hexdigest()[:12]
route_scope_hash = hashlib.sha256((binding + "\0" + effective_route_config_digest).encode("utf-8")).hexdigest()
basename = f"openclaw-{host}-{agent}-{workspace_name}-{binding_hash}-ingest.md"
if len(basename.encode("utf-8")) > 240:
    raise SystemExit(1)
print(f"notes/{basename}")
print(route_scope_hash)
PY
)" || {
  fail_declaration_safely 'Host/machine/agent/workspace/controller watermark identity could not be derived; no job was declared.'
}
WATERMARK_FILE="${CONTROLLER_BINDING%%$'\n'*}"
ROUTE_SCOPE_HASH="${CONTROLLER_BINDING#*$'\n'}"
if [ -z "$WATERMARK_FILE" ] ||
   ! printf '%s' "$ROUTE_SCOPE_HASH" | grep -Eq '^[0-9a-f]{64}$'; then
  fail_declaration_safely 'Host/machine/agent/workspace/controller watermark identity could not be derived; no job was declared.'
fi

MESSAGE="Run the installed borrowedfire-learn skill in fleet mode. The Prometheus root is $BRAIN. Follow the skill and its cycle-contract reference exactly. Use only $WATERMARK_FILE as this controller binding's high-water mark. If it is absent, use the exact prospective-bootstrap behavior in the skill: do not backfill pre-existing session notes, but still inspect pending outboxes and exact-current project status. Otherwise ingest only verified durable deltas visible in this agent workspace since that mark. Deduplicate before using remember; advance the mark only after durable commit/push; and invoke digest only when seven days have elapsed since its last completed run or inbox backlog exceeds 15. Never claim access to another host, agent, or workspace's private session history. Do not mutate product repositories, accounts, credentials, deployments, releases, stores, skills, doctrine, or scheduler configuration, except to delete one exact local-only .brain-outbox/<file> after its capture is committed and pushed to Prometheus; never delete the directory, another item, or a pending item. Do not announce routine success or a no-op. Use the configured message target only for one concise material-digest summary, an actionable owner decision, conflicting evidence, a sync/push failure, or a concrete prevention follow-up."

fail_job_safely() {
  local reason="$1"
  if disable_job_and_verify "$JOB_ID"; then
    printf '%s Prometheus learning job is verified disabled.\n' "$reason" >&2
  else
    printf '%s The job could not be proven disabled; inspect OpenClaw before re-enabling it.\n' "$reason" >&2
  fi
  exit 1
}

verify_job_configuration() {
  local expected_enabled="$1" verify_output
  verify_output="$("$OPENCLAW_BIN" cron get "$JOB_ID")" || return 1
  printf '%s' "$verify_output" | python3 -c '
import json
import sys

expected = {
    "job_id": sys.argv[1],
    "agent_id": sys.argv[2],
    "expr": sys.argv[3],
    "timezone": sys.argv[4],
    "channel": sys.argv[5],
    "to": sys.argv[6],
    "name": sys.argv[7],
    "description": sys.argv[8],
    "message": sys.argv[9],
    "account": sys.argv[10],
    "enabled": sys.argv[11] == "true",
}
try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)
job = payload.get("job", payload) if isinstance(payload, dict) else None
if not isinstance(job, dict):
    raise SystemExit(1)
delivery = job.get("delivery")
failure = job.get("failureAlert")
schedule = job.get("schedule")
agent_payload = job.get("payload")
checks = [
    job.get("id") == expected["job_id"],
    job.get("declarationKey") == "borrowedfire.prometheus-learning.v1",
    job.get("name") == expected["name"],
    job.get("displayName") == expected["name"],
    job.get("description") == expected["description"],
    job.get("enabled") is expected["enabled"],
    job.get("deleteAfterRun") is False,
    job.get("agentId") == expected["agent_id"],
    job.get("sessionTarget") == "isolated",
    not job.get("sessionKey"),
    job.get("wakeMode") == "now",
    isinstance(delivery, dict) and delivery.get("mode") == "none",
    isinstance(delivery, dict) and delivery.get("channel") == expected["channel"],
    isinstance(delivery, dict) and delivery.get("to") == expected["to"],
    isinstance(delivery, dict) and delivery.get("accountId") == expected["account"],
    isinstance(delivery, dict) and delivery.get("threadId") is None,
    isinstance(failure, dict) and failure.get("after") == 2,
    isinstance(failure, dict) and failure.get("cooldownMs") == 43200000,
    isinstance(failure, dict) and failure.get("includeSkipped") is True,
    isinstance(failure, dict) and failure.get("mode") == "announce",
    isinstance(failure, dict) and failure.get("channel") == expected["channel"],
    isinstance(failure, dict) and failure.get("to") == expected["to"],
    isinstance(failure, dict) and failure.get("accountId") == expected["account"],
    isinstance(schedule, dict) and schedule.get("expr") == expected["expr"],
    isinstance(schedule, dict) and schedule.get("tz") == expected["timezone"],
    isinstance(agent_payload, dict) and agent_payload.get("kind") == "agentTurn",
    isinstance(agent_payload, dict) and agent_payload.get("message") == expected["message"],
    isinstance(agent_payload, dict) and agent_payload.get("timeoutSeconds") == 900,
    isinstance(agent_payload, dict) and agent_payload.get("lightContext") is False,
    isinstance(agent_payload, dict) and (
        agent_payload.get("toolsAllow") is None
        or agent_payload.get("toolsAllow") == ["*"]
    ),
]
if not all(checks):
    raise SystemExit(1)
' "$JOB_ID" "$AGENT_ID" "$CRON_EXPR" "$TIMEZONE" "$NOTIFY_CHANNEL" "$NOTIFY_TO" "$JOB_NAME" "$DESCRIPTION" "$MESSAGE" "$NOTIFY_ACCOUNT" "$expected_enabled"
}

ARGS=(
  cron add
  --name "$JOB_NAME"
  --display-name "$JOB_NAME"
  --description "$DESCRIPTION"
  --declaration-key "$DECLARATION_KEY"
  --disabled
  --keep-after-run
  --agent "$AGENT_ID"
  --cron "$CRON_EXPR"
  --tz "$TIMEZONE"
  --session isolated
  --wake now
  --no-deliver
  --channel "$NOTIFY_CHANNEL"
  --to "$NOTIFY_TO"
  --account "$NOTIFY_ACCOUNT"
  --timeout-seconds 900
  --message "$MESSAGE"
  --json
)

if ! declaration_is_absent_or_single_for_agent "$AGENT_ID"; then
  if ! remove_existing_declarations; then
    fail_declaration_safely 'Existing declaration-key jobs could not be safely migrated to the requested agent.'
  fi
fi

STATUS_OUTPUT="$("$OPENCLAW_BIN" cron status --json)" ||
  fail_declaration_safely 'OpenClaw scheduler status could not be inspected; no job was declared.'
if ! printf '%s' "$STATUS_OUTPUT" | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)
if not isinstance(payload, dict) or payload.get("enabled") is not True:
    raise SystemExit(1)
'; then
  fail_declaration_safely 'OpenClaw scheduler is disabled or its status could not be verified; no job was declared.'
fi

CREATE_OUTPUT="$("$OPENCLAW_BIN" "${ARGS[@]}")" ||
  fail_declaration_safely 'OpenClaw could not create or converge the disabled learning declaration.'
JOB_ID="$(printf '%s' "$CREATE_OUTPUT" | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)

job = payload.get("job") if isinstance(payload, dict) else None
job_id = payload.get("id") if isinstance(payload, dict) else None
if not job_id and isinstance(job, dict):
    job_id = job.get("id")
if not isinstance(job_id, str) or not job_id.strip():
    raise SystemExit(1)
print(job_id)
')" || {
  fail_declaration_safely 'OpenClaw returned no parseable job id after declaration convergence.'
}

CONVERGE_ARGS=(
  cron edit "$JOB_ID"
  --name "$JOB_NAME"
  --description "$DESCRIPTION"
  --keep-after-run
  --agent "$AGENT_ID"
  --session isolated
  --clear-session-key
  --wake now
  --cron "$CRON_EXPR"
  --tz "$TIMEZONE"
  --message "$MESSAGE"
  --timeout-seconds 900
  --no-light-context
  --clear-tools
  --no-deliver
  --channel "$NOTIFY_CHANNEL"
  --to "$NOTIFY_TO"
  --account "$NOTIFY_ACCOUNT"
)

if ! "$OPENCLAW_BIN" "${CONVERGE_ARGS[@]}" >/dev/null; then
  fail_job_safely 'Agent/workspace job convergence failed.'
fi

if ! "$OPENCLAW_BIN" cron edit "$JOB_ID" --no-failure-alert >/dev/null; then
  fail_job_safely 'Old failure-alert policy could not be cleared.'
fi

ALERT_ARGS=(
  cron edit "$JOB_ID"
  --failure-alert
  --failure-alert-after 2
  --failure-alert-cooldown 12h
  --failure-alert-include-skipped
  --failure-alert-mode announce
  --failure-alert-channel "$NOTIFY_CHANNEL"
  --failure-alert-to "$NOTIFY_TO"
  --failure-alert-account-id "$NOTIFY_ACCOUNT"
)

if ! "$OPENCLAW_BIN" "${ALERT_ARGS[@]}" >/dev/null; then
  fail_job_safely 'Failure-alert setup failed.'
fi

if ! verify_job_configuration false; then
  fail_job_safely 'Stored job does not match the requested safe configuration.'
fi

ROUTE_HASH="$(python3 - "$ROUTE_SCOPE_HASH" "$NOTIFY_CHANNEL" "$NOTIFY_TO" "$NOTIFY_ACCOUNT" <<'PY'
import hashlib
import sys

print(hashlib.sha256("\0".join(sys.argv[1:]).encode("utf-8")).hexdigest())
PY
)" || {
  fail_job_safely 'Could not derive the private notification-route proof.'
}

if [ -e "$ROUTE_PROOF_FILE" ] || [ -L "$ROUTE_PROOF_FILE" ]; then
  if ! python3 - "$ROUTE_PROOF_FILE" <<'PY'
import os
import stat
import sys

path = sys.argv[1]
flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
try:
    descriptor = os.open(path, flags)
    info = os.fstat(descriptor)
    if not stat.S_ISREG(info.st_mode):
        raise OSError("route proof is not a regular file")
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "r", encoding="utf-8") as handle:
        value = handle.read().strip()
except OSError:
    raise SystemExit(1)
PY
  then
    fail_job_safely 'Existing notification-route proof is unsafe or unreadable.'
  fi
fi

PROOF_DIR="$(dirname "$ROUTE_PROOF_FILE")"
mkdir -p "$PROOF_DIR" || {
  fail_job_safely 'Could not prepare notification-route proof storage.'
}
PROOF_TMP="$(mktemp "$PROOF_DIR/.prometheus-learning-route.XXXXXX")" || {
  fail_job_safely 'Could not prepare notification-route proof storage.'
}
if ! chmod 600 "$PROOF_TMP"; then
  rm -f "$PROOF_TMP"
  fail_job_safely 'Could not prepare notification-route proof storage.'
fi
PROBE_MESSAGE="Prometheus learning notifications are configured on this host. This verifies the route for the current controller configuration."
PROBE_OUTPUT="$("$OPENCLAW_BIN" message send \
  --channel "$NOTIFY_CHANNEL" \
  --target "$NOTIFY_TO" \
  --account "$NOTIFY_ACCOUNT" \
  --message "$PROBE_MESSAGE" \
  --json)" || {
    rm -f "$PROOF_TMP"
    fail_job_safely 'Live notification-route verification failed.'
  }
if ! printf '%s' "$PROBE_OUTPUT" | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)

def acknowledged(value):
    placeholders = {"ok", "unknown", "sent", "success", "true", "none", "null"}
    if isinstance(value, dict):
        for key, item in value.items():
            normalized = key.replace("_", "").lower()
            if normalized in {"messageid", "sentmessageid"} and isinstance(item, str):
                message_id = item.strip()
                if message_id and message_id.lower() not in placeholders:
                    return True
        return any(acknowledged(item) for item in value.values())
    if isinstance(value, list):
        return any(acknowledged(item) for item in value)
    return False

def explicitly_failed(value):
    if isinstance(value, dict):
        for key, item in value.items():
            normalized = key.replace("_", "").lower()
            if normalized in {"ok", "success", "delivered"} and item is False:
                return True
            if normalized in {"iserror", "failed"} and item is True:
                return True
            if normalized in {"error", "errors"} and item not in (None, "", [], {}):
                return True
            if normalized in {"status", "deliverystatus"} and isinstance(item, str):
                if item.strip().lower().replace("-", "_") in {
                    "error", "failed", "partial_failed", "rejected", "skipped", "suppressed"
                }:
                    return True
        return any(explicitly_failed(item) for item in value.values())
    if isinstance(value, list):
        return any(explicitly_failed(item) for item in value)
    return False

if explicitly_failed(payload) or not acknowledged(payload):
    raise SystemExit(1)
'; then
  rm -f "$PROOF_TMP"
  fail_job_safely 'Notification provider returned no message acknowledgement.'
fi

if ! printf '%s\n' "$ROUTE_HASH" > "$PROOF_TMP" ||
   ! python3 - "$PROOF_TMP" "$ROUTE_PROOF_FILE" "$ROUTE_HASH" <<'PY'
import os
import stat
import sys

temporary, target, expected = sys.argv[1:]
try:
    if os.path.lexists(target):
        current = os.lstat(target)
        if not stat.S_ISREG(current.st_mode) or stat.S_ISLNK(current.st_mode):
            raise OSError("unsafe route proof target")
    os.replace(temporary, target)
    current = os.lstat(target)
    if not stat.S_ISREG(current.st_mode) or stat.S_ISLNK(current.st_mode):
        raise OSError("unsafe route proof result")
    if stat.S_IMODE(current.st_mode) != 0o600:
        raise OSError("route proof permissions are not private")
    with open(target, encoding="utf-8") as handle:
        if handle.read().splitlines() != [expected]:
            raise OSError("route proof contents do not match")
except OSError:
    raise SystemExit(1)
PY
then
  rm -f "$PROOF_TMP"
  fail_job_safely 'Could not persist and verify notification-route proof.'
fi
printf 'Notification route verified with a live convergence message.\n'

if ! "$OPENCLAW_BIN" cron enable "$JOB_ID" >/dev/null; then
  fail_job_safely 'Enable failed.'
fi
if ! verify_job_configuration true; then
  fail_job_safely 'Enabled job does not match the requested safe configuration.'
fi
printf 'Prometheus learning job enabled after exact configuration and route verification.\n'
