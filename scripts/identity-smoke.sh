#!/usr/bin/env bash
# Phase 2 smoke: Identity package configured, create Identity with ContentHead, resolve on-chain, update head.
set -euo pipefail

PORT="${CONCRETE_HTTP_PORT:-4000}"
BASE="http://127.0.0.1:${PORT}"

echo "Identity status…"
curl -sf "${BASE}/v1/identity/status" | python3 -m json.tool
python3 - <<PY
import json,urllib.request
s=json.load(urllib.request.urlopen("${BASE}/v1/identity/status"))
assert s["iota_identity"]["package_configured"], "package not configured — run identity-publish.sh"
assert s["iota_identity"]["publish_ready"], "publish_ready false"
print("package", s["iota_identity"]["package_id"])
PY

BOOT=$(curl -sf "${BASE}/v1/bootstrap")
KING=$(echo "$BOOT" | python3 -c "import sys,json; print(json.load(sys.stdin)['king']['id'])")

echo
echo "Create Identity with ContentHead (cap-checked)…"
CREATED=$(curl -sf -X POST "${BASE}/v1/identity" \
  -H 'Content-Type: application/json' \
  -d "{\"principal_id\":\"${KING}\",\"head_cid\":\"QmPhase2OnChainHead\"}")
echo "$CREATED" | python3 -m json.tool
DID=$(echo "$CREATED" | python3 -c "import sys,json; print(json.load(sys.stdin)['did'])")

echo
echo "Resolve (expect on-chain head)…"
ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$DID''', safe=''))")
RESOLVED=$(curl -sf "${BASE}/v1/identity/resolve?did=${ENC}")
echo "$RESOLVED" | python3 -m json.tool
echo "$RESOLVED" | python3 -c 'import json,sys
r=json.load(sys.stdin)
assert r.get("head_source")=="on_chain", r
assert r.get("head_cid")=="QmPhase2OnChainHead", r
print("on-chain head", r["head_cid"])'

echo
echo "Update head on-chain (cap-checked)…"
UPDATED=$(curl -sf -X POST "${BASE}/v1/identity/head" \
  -H 'Content-Type: application/json' \
  -d "{\"principal_id\":\"${KING}\",\"did\":\"${DID}\",\"head_cid\":\"QmPhase2SmokeHead2\"}")
echo "$UPDATED" | python3 -m json.tool
echo "$UPDATED" | python3 -c 'import json,sys
r=json.load(sys.stdin)
assert r.get("head_source")=="on_chain", r
assert r.get("head_cid")=="QmPhase2SmokeHead2", r
print("updated on-chain head", r["head_cid"])'

echo
echo "Phase 2 Identity smoke OK (on-chain ContentHead)."
