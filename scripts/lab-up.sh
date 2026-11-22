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

# Exit as soon as the container stops. A dead container will not become ready by waiting out the timeout.
wait_ready() {
  local name="$1" tries="$2" pause="$3"
  shift 3
  local i running
  echo "Waiting for ${name}…"
  for i in $(seq 1 "${tries}"); do
    running="$(docker inspect -f '{{.State.Running}}' "sep26_lab_${name}" 2>/dev/null || echo missing)"
    if [[ "${running}" != "true" ]]; then
      echo "${name} container is ${running} before it became ready." >&2
      docker logs --tail 40 "sep26_lab_${name}" >&2 || true
      exit 1
    fi
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${pause}"
  done
  echo "${name} did not become ready in time. Try: ${COMPOSE[*]} logs ${name}" >&2
  exit 1
}

wait_ready ipfs 60 1 \
  curl -sf -X POST "http://127.0.0.1:5001/api/v0/id"

wait_ready iota 120 2 \
  curl -sf -X POST "http://127.0.0.1:9000" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"iota_getLatestCheckpointSequenceNumber","params":[]}'

cat <<EOF

Lab harness is up (project-private).

  IPFS API:      http://127.0.0.1:5001
  IPFS Gateway:  http://127.0.0.1:8080
  IOTA RPC:      http://127.0.0.1:9000
  IOTA Faucet:   http://127.0.0.1:9123

  Status:  ./scripts/lab-status.sh
  Stop:    ./scripts/lab-down.sh

EOF
