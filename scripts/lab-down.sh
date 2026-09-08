#!/usr/bin/env bash
# Stop the sep_26_concrete lab harness.
# Usage: ./scripts/lab-down.sh [--wipe]
#   --wipe  also remove lab/data (swarm key, IOTA genesis, IPFS repo)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB="${ROOT}/lab"
COMPOSE=(docker compose -f "${LAB}/docker-compose.yml" --project-directory "${LAB}")

"${COMPOSE[@]}" down

if [[ "${1:-}" == "--wipe" ]]; then
  echo "Wiping lab/data (new swarm key + IOTA genesis on next lab-up)…"
  rm -rf "${LAB}/data"
fi

echo "Lab harness stopped."
