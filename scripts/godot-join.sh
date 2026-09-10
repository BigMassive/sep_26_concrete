#!/usr/bin/env bash
# Join the Godot listen-server as a second body (windowed). Host: ./scripts/godot-up.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"
HOST="${CONCRETE_GODOT_HOST:-127.0.0.1}"
PORT="${CONCRETE_GODOT_PORT:-24567}"

if [[ -z "${GODOT_BIN}" ]]; then
  if [[ -x /home/stuart/Downloads/godot ]]; then
    GODOT_BIN=/home/stuart/Downloads/godot
  elif command -v godot4 >/dev/null 2>&1; then
    GODOT_BIN=$(command -v godot4)
  elif command -v godot >/dev/null 2>&1; then
    GODOT_BIN=$(command -v godot)
  else
    echo "Godot not found. Set GODOT_BIN or install Godot 4.x." >&2
    exit 1
  fi
fi

exec "${GODOT_BIN}" --path "${ROOT}/godot" -- --join "${HOST}:${PORT}"
