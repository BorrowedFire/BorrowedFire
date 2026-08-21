#!/usr/bin/env bash
set -u
: "${OPENCLAW_ARGS_FILE:?OPENCLAW_ARGS_FILE is required}"
printf '%s\n' "$@" > "$OPENCLAW_ARGS_FILE"
printf '{"id":"fixture-job","declarationKey":"borrowedfire.prometheus-learning.v1"}\n'
