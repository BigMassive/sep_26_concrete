#!/usr/bin/env bash
# Headless Godot peer: join host, act as a body (ADR 0009 option C).
# Default playbook `first-login` is leftover Phase 1 (paper-as-King + plaque).
# create_plaque / eve_deny fail-fast with superseded_step. Known red until a
# Helen→Alice playbook can drive W0–W2 from the console.
# Usage: ./scripts/godot-playbook.sh [playbook-name-or-path]
# Host must already be listening (./scripts/godot-up.sh). OTP should be up for mutates.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"
HOST="${CONCRETE_GODOT_HOST:-127.0.0.1}"
PORT="${CONCRETE_GODOT_PORT:-24567}"
PLAYBOOK="${1:-first-login}"

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

exec "${GODOT_BIN}" --path "${ROOT}/godot" --headless -- --join "${HOST}:${PORT}" --playbook "${PLAYBOOK}"
