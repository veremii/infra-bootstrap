#!/usr/bin/env bash
set -euo pipefail

ensure_net() {
  local name="$1"
  local encrypted="$2" # true|false
  if ! docker network ls --format '{{.Name}}' | grep -q "^${name}$"; then
    if [[ "$encrypted" == "true" ]]; then
      docker network create --driver overlay --attachable --opt encrypted "$name" >/dev/null
    else
      docker network create --driver overlay --attachable "$name" >/dev/null
    fi
    echo "Created network: $name (encrypted=$encrypted)"
  else
    echo "Network exists: $name"
  fi
}

# edge: публичная (ingress) — без encryption (TLS на уровне L7)
ensure_net edge false

# app: внутренняя сеть приложений — encrypted
ensure_net app true

# infra: внутренняя сеть инфраструктуры — encrypted
ensure_net infra true

