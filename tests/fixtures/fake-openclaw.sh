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
printf '{"id":"fixture-job","declarationKey":"borrowedfire.prometheus-learning.v1"}\n'
