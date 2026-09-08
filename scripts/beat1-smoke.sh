#!/usr/bin/env bash
# Smoke-test beat 1: bootstrap capability on first user / first node.
set -euo pipefail

PORT="${CONCRETE_HTTP_PORT:-4000}"
BASE="http://127.0.0.1:${PORT}"

echo "GET ${BASE}/health"
curl -sf "${BASE}/health" | python3 -m json.tool

echo
echo "GET ${BASE}/v1/bootstrap"
BOOT=$(curl -sf "${BASE}/v1/bootstrap")
echo "$BOOT" | python3 -m json.tool

KING_ID=$(echo "$BOOT" | python3 -c "import sys,json; print(json.load(sys.stdin)['king']['id'])")

echo
echo "Authorize King (${KING_ID})…"
curl -sf -X POST "${BASE}/v1/capability/check" \
  -H 'Content-Type: application/json' \
  -d "{\"principal_id\":\"${KING_ID}\",\"action\":\"mutate\"}" | python3 -m json.tool

echo
echo "Create Eve (no bootstrap cap)…"
EVE=$(curl -sf -X POST "${BASE}/v1/principals" \
  -H 'Content-Type: application/json' \
  -d '{"display_name":"Eve"}')
echo "$EVE" | python3 -m json.tool
EVE_ID=$(echo "$EVE" | python3 -c "import sys,json; print(json.load(sys.stdin)['principal']['id'])")

echo
echo "Authorize Eve (expect 403)…"
CODE=$(curl -s -o /tmp/eve_auth.json -w '%{http_code}' -X POST "${BASE}/v1/capability/check" \
  -H 'Content-Type: application/json' \
  -d "{\"principal_id\":\"${EVE_ID}\",\"action\":\"mutate\"}")
python3 -m json.tool </tmp/eve_auth.json
if [[ "$CODE" != "403" ]]; then
  echo "expected HTTP 403 for Eve, got ${CODE}" >&2
  exit 1
fi

echo
echo "Beat 1 smoke OK (King allowed, Eve denied)."
