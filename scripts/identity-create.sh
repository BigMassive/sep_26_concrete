#!/usr/bin/env bash
# Create an on-ledger Identity with a packed DID document (ContentHead optional).
# Lab harness: iota client PTB in the Compose image (not a typed BEAM SDK).
#
# Env:
#   IDENTITY_DOC_HEX  packed document hex (from OTP pack_hex / identity-doc.py)
#   HEAD_CID          if DOC_HEX unset, pack a ContentHead document for this CID
# Prints JSON: {did, identity_object_id, controller_cap_id, package_id, chain_id, digest}
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

HEX="${IDENTITY_DOC_HEX:-}"
if [[ -z "${HEX}" && -n "${HEAD_CID:-}" ]]; then
  HEX=$(python3 "${ROOT}/scripts/identity-doc.py" pack --head-cid "${HEAD_CID}")
fi

RESP=$(mktemp)
ERR=$(mktemp)
cleanup() { rm -f "${RESP}" "${ERR}"; }
trap cleanup EXIT

PTB=(client ptb --gas-budget 100000000 --json)
if [[ -n "${HEX}" ]]; then
  VEC=$(python3 "${ROOT}/scripts/identity-doc.py" vec "${HEX}")
  PTB+=(--assign doc "some(vector${VEC})")
else
  PTB+=(--assign doc none)
fi
PTB+=(--move-call "${PKG_ID}::identity::new" doc @0x6)

docker run --rm --network host --entrypoint iota \
  -e IOTA_CONFIG_DIR=/data/iota-config \
  -v "${IOTA_DATA}:/data/iota-config" \
  "${IOTA_IMG}" \
  "${PTB[@]}" >"${RESP}" 2>"${ERR}" || {
  echo "identity create PTB failed:" >&2
  cat "${ERR}" >&2
  tail -n 40 "${RESP}" >&2
  exit 1
}

python3 - "${RESP}" "${PKG_ID}" "${ERR}" <<'PY'
import json, sys, urllib.request

path, pkg, err_path = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(path).read()
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
    raise SystemExit("no JSON in create response:\n" + raw[-2000:] + open(err_path).read()[-1000:])

status = (data.get("effects") or {}).get("status") or {}
if status.get("status") not in (None, "success"):
    raise SystemExit(f"tx failed: {status}")

obj = cap = None
for ch in data.get("objectChanges") or []:
    ot = ch.get("objectType") or ""
    if ch.get("type") != "created":
        continue
    if ot.endswith("::identity::Identity"):
        obj = ch.get("objectId")
    elif ot.endswith("::controller::ControllerCap"):
        cap = ch.get("objectId")
if not obj:
    raise SystemExit("Identity object not found in objectChanges")
if not cap:
    raise SystemExit("ControllerCap not found in objectChanges")

req = urllib.request.Request(
    "http://127.0.0.1:9000",
    data=json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": "iota_getChainIdentifier", "params": []}
    ).encode(),
    headers={"Content-Type": "application/json"},
)
chain = json.load(urllib.request.urlopen(req))["result"]
did = f"did:iota:{chain}:{obj}"
print(json.dumps({
    "did": did,
    "identity_object_id": obj,
    "controller_cap_id": cap,
    "package_id": pkg,
    "chain_id": chain,
    "digest": data.get("digest"),
}))
PY
