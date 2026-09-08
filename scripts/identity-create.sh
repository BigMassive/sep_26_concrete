#!/usr/bin/env bash
# Create an on-ledger Identity object on the lab localnet (empty DID doc for now).
# Prints JSON: {did, identity_object_id, package_id, chain_id, digest}
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOTA_DATA="${ROOT}/lab/data/iota"
PKG_FILE="${IOTA_DATA}/identity_pkg_id.txt"
IOTA_IMG="${IOTA_IMAGE:-sep26_concrete/iota-localnet:v1.30.1}"

[[ -f "${PKG_FILE}" ]] || {
  echo "missing ${PKG_FILE} — run ./scripts/identity-publish.sh first" >&2
  exit 1
}
PKG_ID=$(tr -d '[:space:]' <"${PKG_FILE}")

RESP=$(mktemp)
docker run --rm --network host --entrypoint iota \
  -e IOTA_CONFIG_DIR=/data/iota-config \
  -v "${IOTA_DATA}:/data/iota-config" \
  "${IOTA_IMG}" \
  client call \
  --package "${PKG_ID}" \
  --module identity \
  --function new \
  --args '[]' '0x6' \
  --gas-budget 100000000 \
  --json >"${RESP}"

python3 - "${RESP}" "${PKG_ID}" <<'PY'
import json, sys, urllib.request

path, pkg = sys.argv[1], sys.argv[2]
data = json.load(open(path))
status = (data.get("effects") or {}).get("status") or {}
if status.get("status") != "success":
    raise SystemExit(f"tx failed: {status}")

obj = None
for ch in data.get("objectChanges") or []:
    ot = ch.get("objectType") or ""
    if ch.get("type") == "created" and ot.endswith("::identity::Identity"):
        obj = ch.get("objectId")
        break
if not obj:
    raise SystemExit("Identity object not found in objectChanges")

req = urllib.request.Request(
    "http://127.0.0.1:9000",
    data=json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": "iota_getChainIdentifier", "params": []}
    ).encode(),
    headers={"Content-Type": "application/json"},
)
chain = json.load(urllib.request.urlopen(req))["result"]
# did:iota:<network-id>:<object-id> (IOTA DID method v2)
did = f"did:iota:{chain}:{obj}"
print(json.dumps({
    "did": did,
    "identity_object_id": obj,
    "package_id": pkg,
    "chain_id": chain,
    "digest": data.get("digest"),
}))
PY
