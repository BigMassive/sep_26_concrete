#!/usr/bin/env bash
# Phase 2 smoke: Identity package configured, create Identity, resolve, update head.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
echo "Create Identity (cap-checked)…"
CREATED=$(curl -sf -X POST "${BASE}/v1/identity" \
  -H 'Content-Type: application/json' \
  -d "{\"principal_id\":\"${KING}\"}")
echo "$CREATED" | python3 -m json.tool
DID=$(echo "$CREATED" | python3 -c "import sys,json; print(json.load(sys.stdin)['did'])")

echo
echo "Resolve…"
ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$DID''', safe=''))")
curl -sf "${BASE}/v1/identity/resolve?did=${ENC}" | python3 -m json.tool

echo
echo "Update head (OTP-tracked)…"
curl -sf -X POST "${BASE}/v1/identity/head" \
  -H 'Content-Type: application/json' \
  -d "{\"principal_id\":\"${KING}\",\"did\":\"${DID}\",\"head_cid\":\"QmPhase2SmokeHead\"}" | python3 -m json.tool

echo
echo "Phase 2 Identity smoke OK."
