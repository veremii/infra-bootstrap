#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'HLP'
Usage: secrets-resolve -s SECRET_VALUE [-k PASS] [-o OUT] [--non-interactive]

Decode and (optionally) decrypt bundled ENV from a single GitHub Secret value.

Input formats:
  - base64-encoded .env (simple case)
  - age-encrypted then base64-encoded .env (provide -k with AGE private key)

Options:
  -s SECRET_VALUE   The value of the GitHub Secret (passed from CI env)
  -k PASS           AGE private key content (starts with 'AGE-SECRET-KEY-...')
  -o OUT            Write resolved .env to OUT (default: stdout)
  --non-interactive Do not ask for confirmation
  -h                Show this help

Behavior:
  - Validates lines as KEY=VALUE
  - Prints summary of keys and asks to proceed (unless non-interactive)
HLP
}

SECRET_VALUE=""
AGE_KEY=""
OUT=""
NONINT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s) SECRET_VALUE="$2"; shift 2 ;;
    -k) AGE_KEY="$2"; shift 2 ;;
    -o) OUT="$2"; shift 2 ;;
    --non-interactive) NONINT=true; shift ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; show_help; exit 2 ;;
  esac
done

if [[ -z "$SECRET_VALUE" ]]; then
  echo "-s SECRET_VALUE is required" >&2
  exit 2
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "$SECRET_VALUE" | base64 -d > "$tmpdir/payload" 2>/dev/null || {
  echo "Provided SECRET_VALUE is not base64 or corrupted" >&2
  exit 1
}

if [[ -n "$AGE_KEY" ]]; then
  command -v age >/dev/null 2>&1 || { echo "age not installed" >&2; exit 1; }
  printf "%s" "$AGE_KEY" > "$tmpdir/key.txt"
  chmod 600 "$tmpdir/key.txt"
  age -d -i "$tmpdir/key.txt" -o "$tmpdir/env" "$tmpdir/payload"
else
  cp "$tmpdir/payload" "$tmpdir/env"
fi

# Validate .env lines
BAD=0
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  if ! [[ "$line" =~ ^[A-Z0-9_]+=.*$ ]]; then
    echo "Invalid line: $line" >&2
    BAD=$((BAD+1))
  fi
done < "$tmpdir/env"

if [[ $BAD -gt 0 ]]; then
  echo "Found $BAD invalid lines in env" >&2
  exit 1
fi

KEYS=$(grep -v '^#' "$tmpdir/env" | sed -n 's/=.*//p')
echo "Resolved keys (masked):"
echo "$KEYS" | while IFS= read -r key; do
  [ -n "$key" ] && echo " - ${key}=********"
done

if ! $NONINT; then
  read -r -p "Proceed with these vars? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "Aborted by user"; exit 130 ;;
  esac
fi

if [[ -n "$OUT" ]]; then
  cp "$tmpdir/env" "$OUT"
  echo "Wrote $OUT"
else
  cat "$tmpdir/env"
fi

