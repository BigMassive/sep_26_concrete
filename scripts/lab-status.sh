#!/usr/bin/env bash
# Show lab harness container and endpoint status.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB="${ROOT}/lab"
COMPOSE=(docker compose -f "${LAB}/docker-compose.yml" --project-directory "${LAB}")

"${COMPOSE[@]}" ps

echo
echo -n "IPFS: "
if curl -sf -X POST "http://127.0.0.1:5001/api/v0/id" >/dev/null 2>&1; then
  echo "ok (http://127.0.0.1:5001)"
else
  echo "down"
fi

echo -n "IOTA: "
if curl -sf -X POST "http://127.0.0.1:9000" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"iota_getLatestCheckpointSequenceNumber","params":[]}' \
  >/dev/null 2>&1; then
  echo "ok (http://127.0.0.1:9000)"
else
  echo "down"
fi
