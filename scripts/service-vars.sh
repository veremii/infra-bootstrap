#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'HLP'
Usage: service-vars [--export]

Detect and print container IDs for core services by name patterns:
  - BE_NAME (default: backend)
  - FE_NAME (default: frontend)
  - TRF_NAME (default: traefik)

Outputs:
  CID_BE, CID_FE, CID_TRF

Options:
  --export   Print lines as `export VAR=...` (use with `eval $(service-vars --export)`).
  -h         Show this help
HLP
}

EXPORT=false

case "${1:-}" in
  --export) EXPORT=true ;;
  -h|--help) show_help; exit 0 ;;
  "") ;;
  *) echo "Unknown option: $1" >&2; show_help; exit 2 ;;
esac

BE_NAME=${BE_NAME:-backend}
FE_NAME=${FE_NAME:-frontend}
TRF_NAME=${TRF_NAME:-traefik}

CID_BE=$(docker ps --filter "name=${BE_NAME}" --format '{{.ID}}' | head -n1 || true)
CID_FE=$(docker ps --filter "name=${FE_NAME}" --format '{{.ID}}' | head -n1 || true)
CID_TRF=$(docker ps --filter "name=${TRF_NAME}" --format '{{.ID}}' | head -n1 || true)

if $EXPORT; then
  echo "export CID_BE=${CID_BE}"
  echo "export CID_FE=${CID_FE}"
  echo "export CID_TRF=${CID_TRF}"
else
  echo "CID_BE=${CID_BE}"
  echo "CID_FE=${CID_FE}"
  echo "CID_TRF=${CID_TRF}"
fi
