#!/usr/bin/env bash
# Start the OTP node runtime (beat 1+). Lab IPFS/IOTA should already be up for later beats.
# Usage: ./scripts/node-up.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CONCRETE_DATA_DIR="${CONCRETE_DATA_DIR:-${ROOT}/lab/data/node}"
export CONCRETE_HTTP_PORT="${CONCRETE_HTTP_PORT:-4000}"

PKG_FILE="${ROOT}/lab/data/iota/identity_pkg_id.txt"
if [[ -z "${IOTA_IDENTITY_PKG_ID:-}" && -f "${PKG_FILE}" ]]; then
  IOTA_IDENTITY_PKG_ID="$(tr -d '[:space:]' <"${PKG_FILE}")"
  export IOTA_IDENTITY_PKG_ID
fi

mkdir -p "${CONCRETE_DATA_DIR}"
cd "${ROOT}/runtime"

if [[ ! -d deps ]] || [[ ! -d _build ]]; then
  mix deps.get
  mix compile
fi

echo "Starting concrete_runtime on http://127.0.0.1:${CONCRETE_HTTP_PORT} (data: ${CONCRETE_DATA_DIR})"
if [[ -n "${IOTA_IDENTITY_PKG_ID:-}" ]]; then
  echo "IOTA_IDENTITY_PKG_ID=${IOTA_IDENTITY_PKG_ID}"
fi
exec mix run --no-halt
