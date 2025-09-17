#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'HLP'
Usage: secrets-to-swarm -f ENV_FILE [-p PREFIX] [-s STACK]

Create/update Docker Swarm secrets from a resolved .env file.

Options:
  -f ENV_FILE  Path to .env file (KEY=VALUE)
  -p PREFIX    Prefix for secret names (default: app_)
  -s STACK     Optional stack name hint (not strictly required)
  -h           Show this help

Notes:
  - For each KEY in ENV_FILE create secret NAME="${PREFIX}${KEY}" with value VALUE
  - Existing secrets with same name are removed and recreated (idempotent)
HLP
}

ENV_FILE=""
PREFIX="app_"
STACK=""

while getopts ":f:p:s:h" opt; do
  case "$opt" in
    f) ENV_FILE="$OPTARG" ;;
    p) PREFIX="$OPTARG" ;;
    s) STACK="$OPTARG" ;;
    h) show_help; exit 0 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
    \?) echo "Unknown option -$OPTARG" >&2; exit 2 ;;
  esac
done

if [[ -z "$ENV_FILE" || ! -f "$ENV_FILE" ]]; then
  echo "Provide -f ENV_FILE" >&2
  exit 2
fi

while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  KEY=${line%%=*}
  VAL=${line#*=}
  NAME="${PREFIX}${KEY}"
  echo "Updating secret: $NAME"
  docker secret rm "$NAME" >/dev/null 2>&1 || true
  printf "%s" "$VAL" | docker secret create "$NAME" - >/dev/null
done < "$ENV_FILE"

echo "Done. You can reference secrets as ${PREFIX}<KEY> in stack files."

