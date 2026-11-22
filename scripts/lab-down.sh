#!/usr/bin/env bash
# Stop the sep_26_concrete lab harness.
# Usage: ./scripts/lab-down.sh [--wipe]
#   --wipe  also remove lab/data (swarm key, IOTA genesis, IPFS repo)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB="${ROOT}/lab"
COMPOSE=(docker compose -f "${LAB}/docker-compose.yml" --project-directory "${LAB}")

"${COMPOSE[@]}" down

# Containers write IOTA databases as root. A plain rm then stops halfway and leaves lab/data behind.
wipe_lab_data() {
  local data="${LAB}/data"
  [[ -e "${data}" ]] || return 0
  echo "Wiping lab/data (new swarm key + IOTA genesis on next lab-up)…"
  if rm -rf "${data}" 2>/dev/null; then
    return 0
  fi
  echo "Some lab/data files are owned by root. Removing them in a container…"
  local image="" candidate
  for candidate in \
    "${IOTA_IMAGE:-sep26_concrete/iota-localnet:v1.30.1}" \
    "ipfs/kubo:v0.34.1"
  do
    if docker image inspect "${candidate}" >/dev/null 2>&1; then
      image="${candidate}"
      break
    fi
  done
  if [[ -z "${image}" ]]; then
    echo "Could not wipe ${data}: root-owned files remain and no local lab image is available." >&2
    return 1
  fi
  # Deleting the mount point itself fails with "device busy"; delete its contents.
  docker run --rm --entrypoint find -v "${data}:/wipe" "${image}" /wipe -mindepth 1 -delete
  rm -rf "${data}"
}

if [[ "${1:-}" == "--wipe" ]]; then
  wipe_lab_data
fi

echo "Lab harness stopped."
