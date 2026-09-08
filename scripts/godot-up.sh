#!/usr/bin/env bash
# Open the Godot lab veneer (beat 3). Requires OTP on :4000 and preferably lab IPFS/IOTA.
# Default: run the game. Set GODOT_EDITOR=1 to open the editor.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"

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

echo "Using ${GODOT_BIN}"
echo "Project: ${ROOT}/godot"
if [[ "${GODOT_EDITOR:-}" == "1" ]]; then
  exec "${GODOT_BIN}" --path "${ROOT}/godot" --editor
else
  exec "${GODOT_BIN}" --path "${ROOT}/godot"
fi
