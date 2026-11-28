#!/usr/bin/env bash
# A fresh clone has no godot/.godot class cache. Headless Godot then cannot
# see class_name scripts (Player, NodeConsole) and the scenario sits idle.
# Usage: GODOT_BIN=/path/to/godot ./scripts/ensure-godot-import.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${ROOT}/godot/.godot/global_script_class_cache.cfg"

if [[ -s "${CACHE}" ]]; then
  exit 0
fi

if [[ -z "${GODOT_BIN:-}" || ! -x "${GODOT_BIN}" ]]; then
  echo "GODOT_BIN must be an executable Godot 4.7 binary." >&2
  exit 1
fi

echo "Importing the Godot project so class_name scripts resolve…"
"${GODOT_BIN}" --headless --path "${ROOT}/godot" --import --quit

if [[ ! -s "${CACHE}" ]]; then
  echo "Godot import finished without writing ${CACHE}." >&2
  exit 1
fi
