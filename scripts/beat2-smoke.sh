#!/usr/bin/env bash
# Beat 2: create DID + IPFS commit as King; Eve denied on advance.
set -euo pipefail

PORT="${CONCRETE_HTTP_PORT:-4000}"
BASE="http://127.0.0.1:${PORT}"

echo "Health…"
curl -sf "${BASE}/health" | python3 -m json.tool

BOOT=$(curl -sf "${BASE}/v1/bootstrap")
KING=$(echo "$BOOT" | python3 -c "import sys,json; print(json.load(sys.stdin)['king']['id'])")
echo "King=$KING"

echo
echo "Create info object…"
CREATED=$(curl -sf -X POST "${BASE}/v1/info_objects" \
  -H 'Content-Type: application/json' \
  -d "{\"principal_id\":\"${KING}\",\"content\":\"Hello CONCRETE\",\"label\":\"plaque\"}")
echo "$CREATED" | python3 -m json.tool
DID=$(echo "$CREATED" | python3 -c "import sys,json; print(json.load(sys.stdin)['did'])")

echo
echo "Get…"
curl -sf "${BASE}/v1/info_object?did=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$DID''', safe=''))")" | python3 -m json.tool

echo
echo "Advance as King…"
curl -sf -X POST "${BASE}/v1/info_objects/advance" \
  -H 'Content-Type: application/json' \
  -d "{\"principal_id\":\"${KING}\",\"did\":\"${DID}\",\"content\":\"Hello again\",\"message\":\"beat2\"}" | python3 -m json.tool

EVE=$(curl -sf -X POST "${BASE}/v1/principals" -H 'Content-Type: application/json' -d '{"display_name":"Eve"}')
EVE_ID=$(echo "$EVE" | python3 -c "import sys,json; print(json.load(sys.stdin)['principal']['id'])")
echo
echo "Advance as Eve (expect 403)…"
CODE=$(curl -s -o /tmp/eve_adv.json -w '%{http_code}' -X POST "${BASE}/v1/info_objects/advance" \
  -H 'Content-Type: application/json' \
  -d "{\"principal_id\":\"${EVE_ID}\",\"did\":\"${DID}\",\"content\":\"evil\"}")
python3 -m json.tool </tmp/eve_adv.json
[[ "$CODE" == "403" ]] || { echo "expected 403 got $CODE"; exit 1; }

echo
echo "Beat 2 smoke OK."
