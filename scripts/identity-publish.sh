#!/usr/bin/env bash
# Publish IOTA Identity Move package to the lab localnet and persist IOTA_IDENTITY_PKG_ID.
# Requires: ./scripts/lab-up.sh already healthy. Uses the Compose iota image (v1.30.1).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOTA_DATA="${ROOT}/lab/data/iota"
IDENTITY_SRC="${ROOT}/lab/data/identity.rs"
PKG_OUT="${IOTA_DATA}/identity_pkg_id.txt"
IOTA_IMG="${IOTA_IMAGE:-sep26_concrete/iota-localnet:v1.30.1}"
IDENTITY_REF="${IDENTITY_GIT_REF:-main}"

curl -sf -X POST http://127.0.0.1:9000 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"iota_getLatestCheckpointSequenceNumber","params":[]}' >/dev/null \
  || { echo "IOTA RPC not up — run ./scripts/lab-up.sh first" >&2; exit 1; }

if [[ ! -f "${IDENTITY_SRC}/identity_iota_core/packages/iota_identity/Move.toml" ]]; then
  echo "Cloning identity.rs (${IDENTITY_REF}) into lab/data (gitignored)…"
  rm -rf "${IDENTITY_SRC}"
  git clone --depth 1 --branch "${IDENTITY_REF}" \
    https://github.com/iotaledger/identity.rs.git "${IDENTITY_SRC}"
fi

echo "Publishing IotaIdentity package (needs git inside publish container for framework deps)…"
RESP_FILE=$(mktemp)
ERR_FILE=$(mktemp)
docker run --rm --network host --entrypoint bash \
  -e IOTA_CONFIG_DIR=/data/iota-config \
  -v "${IOTA_DATA}:/data/iota-config" \
  -v "${IDENTITY_SRC}:/identity" \
  "${IOTA_IMG}" \
  -lc 'set -euo pipefail
    if ! command -v git >/dev/null 2>&1; then
      apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git >/dev/null
    fi
    iota client publish --with-unpublished-dependencies --silence-warnings --json --gas-budget 500000000 \
      /identity/identity_iota_core/packages/iota_identity
  ' >"${RESP_FILE}" 2>"${ERR_FILE}" || {
  echo "publish failed:" >&2
  tail -n 80 "${ERR_FILE}" >&2
  exit 1
}

PKG_ID=$(python3 - "${RESP_FILE}" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
data = None
for i, ch in enumerate(raw):
    if ch != "{":
        continue
    try:
        data = json.loads(raw[i:])
        break
    except json.JSONDecodeError:
        continue
if not data:
    raise SystemExit("no JSON in publish response")
pkg = None
for ch in data.get("objectChanges") or []:
    if ch.get("type") == "published":
        pkg = ch.get("packageId")
        break
if not pkg:
    raise SystemExit("published packageId not found")
print(pkg)
PY
)

mkdir -p "${IOTA_DATA}"
echo "${PKG_ID}" >"${PKG_OUT}"
echo "IOTA_IDENTITY_PKG_ID=${PKG_ID}"
echo "Wrote ${PKG_OUT}"
echo "Export for this shell: export IOTA_IDENTITY_PKG_ID=${PKG_ID}"
