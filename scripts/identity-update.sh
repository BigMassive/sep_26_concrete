#!/usr/bin/env bash
# Propose+execute an on-chain DID document update (ContentHead → IPFS CID).
# Lab harness: borrow ControllerCap token, Identity::propose_update, put_back.
# Single-controller identities execute immediately inside propose_update.
#
# Env:
#   IDENTITY_OBJECT_ID   shared Identity object
#   CONTROLLER_CAP_ID    owned ControllerCap
#   IDENTITY_DOC_HEX     packed document hex
#   HEAD_CID             if DOC_HEX unset, pack ContentHead for this CID
# Prints JSON: {digest, identity_object_id, controller_cap_id}
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

OBJ="${IDENTITY_OBJECT_ID:-}"
CAP="${CONTROLLER_CAP_ID:-}"
[[ -n "${OBJ}" && -n "${CAP}" ]] || {
  echo "IDENTITY_OBJECT_ID and CONTROLLER_CAP_ID required" >&2
  exit 1
}

HEX="${IDENTITY_DOC_HEX:-}"
if [[ -z "${HEX}" && -n "${HEAD_CID:-}" ]]; then
  HEX=$(python3 "${ROOT}/scripts/identity-doc.py" pack --head-cid "${HEAD_CID}")
fi
[[ -n "${HEX}" ]] || {
  echo "IDENTITY_DOC_HEX or HEAD_CID required" >&2
  exit 1
}
VEC=$(python3 "${ROOT}/scripts/identity-doc.py" vec "${HEX}")

RESP=$(mktemp)
ERR=$(mktemp)
cleanup() { rm -f "${RESP}" "${ERR}"; }
trap cleanup EXIT

docker run --rm --network host --entrypoint iota \
  -e IOTA_CONFIG_DIR=/data/iota-config \
  -v "${IOTA_DATA}:/data/iota-config" \
  "${IOTA_IMG}" \
  client ptb \
  --assign identity "@${OBJ}" \
  --assign cap "@${CAP}" \
  --move-call "${PKG_ID}::controller::borrow" cap \
  --assign borrowed \
  --assign doc "some(vector${VEC})" \
  --assign expiration none \
  --move-call "${PKG_ID}::identity::propose_update" identity borrowed.0 doc expiration @0x6 \
  --move-call "${PKG_ID}::controller::put_back" cap borrowed.0 borrowed.1 \
  --gas-budget 100000000 \
  --json >"${RESP}" 2>"${ERR}" || {
  echo "identity update PTB failed:" >&2
  cat "${ERR}" >&2
  tail -n 40 "${RESP}" >&2
  exit 1
}

python3 - "${RESP}" "${OBJ}" "${CAP}" "${ERR}" <<'PY'
import json, sys

path, obj, cap, err_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
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
    raise SystemExit("no JSON in update response:\n" + raw[-2000:] + open(err_path).read()[-1000:])

status = (data.get("effects") or {}).get("status") or {}
if status.get("status") not in (None, "success"):
    raise SystemExit(f"tx failed: {status}")

print(json.dumps({
    "identity_object_id": obj,
    "controller_cap_id": cap,
    "digest": data.get("digest"),
}))
PY
