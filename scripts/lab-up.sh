#!/usr/bin/env bash
# Bring up the sep_26_concrete lab harness (project-private IPFS + IOTA).
# Usage: ./scripts/lab-up.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB="${ROOT}/lab"
COMPOSE=(docker compose -f "${LAB}/docker-compose.yml" --project-directory "${LAB}")

mkdir -p "${LAB}/data/ipfs" "${LAB}/data/iota"

if [[ ! -f "${LAB}/data/swarm.key" ]]; then
  echo "Generating project-private IPFS swarm key → lab/data/swarm.key"
  {
    echo "/key/swarm/psk/1.0.0/"
    echo "/base16/"
    openssl rand -hex 32
  } > "${LAB}/data/swarm.key"
  chmod 600 "${LAB}/data/swarm.key"
fi

# Kubo expects the init script to be executable
chmod +x "${LAB}/ipfs/container-init.sh" "${LAB}/iota/entrypoint.sh"

echo "Starting lab harness (LAB HARNESS — not product topology)…"
"${COMPOSE[@]}" up -d --build

echo "Waiting for IPFS…"
for _ in $(seq 1 60); do
  if curl -sf -X POST "http://127.0.0.1:5001/api/v0/id" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if ! curl -sf -X POST "http://127.0.0.1:5001/api/v0/id" >/dev/null 2>&1; then
  echo "IPFS did not become ready in time. Try: ${COMPOSE[*]} logs ipfs" >&2
  exit 1
fi

echo "Waiting for IOTA RPC…"
for _ in $(seq 1 120); do
  if curl -sf -X POST "http://127.0.0.1:9000" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"iota_getLatestCheckpointSequenceNumber","params":[]}' \
    >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
if ! curl -sf -X POST "http://127.0.0.1:9000" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"iota_getLatestCheckpointSequenceNumber","params":[]}' \
  >/dev/null 2>&1; then
  echo "IOTA did not become ready in time. Try: ${COMPOSE[*]} logs iota" >&2
  exit 1
fi

cat <<EOF

Lab harness is up (project-private).

  IPFS API:      http://127.0.0.1:5001
  IPFS Gateway:  http://127.0.0.1:8080
  IOTA RPC:      http://127.0.0.1:9000
  IOTA Faucet:   http://127.0.0.1:9123

  Status:  ./scripts/lab-status.sh
  Stop:    ./scripts/lab-down.sh

EOF
