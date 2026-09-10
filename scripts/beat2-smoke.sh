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
CREATED="$CREATED" BASE="$BASE" python3 - <<'PY'
import json, os, urllib.parse, urllib.request
created = json.loads(os.environ["CREATED"])
base = os.environ["BASE"]
status = json.load(urllib.request.urlopen(f"{base}/v1/identity/status"))
if status["iota_identity"]["package_configured"]:
    iota_did = created.get("iota_did")
    assert created.get("did", "").startswith("did:iota:"), created
    assert iota_did, created
    assert created["did"] == iota_did, created
    enc = urllib.parse.quote(iota_did, safe="")
    resolved = json.load(urllib.request.urlopen(f"{base}/v1/identity/resolve?did={enc}"))
    assert resolved.get("head_source") == "on_chain", resolved
    assert resolved.get("head_cid") == created["head_cid"], resolved
    print("iota_did", iota_did, "on-chain head", resolved["head_cid"])
else:
    print("Identity package not configured — lab DID path")
PY

echo
echo "Get…"
GOT=$(curl -sf "${BASE}/v1/info_object?did=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$DID''', safe=''))")")
echo "$GOT" | python3 -m json.tool
GOT="$GOT" python3 - <<'PY'
import json, os
got = json.loads(os.environ["GOT"])
if got.get("iota_did"):
    assert got.get("did", "").startswith("did:iota:"), got
    assert got.get("head_source") == "on_chain", got
    print("GET head_source on_chain", got["head_cid"])
else:
    assert got.get("head_source") == "otp_registry", got
    print("GET head_source otp_registry", got["head_cid"])
PY

echo
echo "Advance as King…"
ADVANCED=$(curl -sf -X POST "${BASE}/v1/info_objects/advance" \
  -H 'Content-Type: application/json' \
  -d "{\"principal_id\":\"${KING}\",\"did\":\"${DID}\",\"content\":\"Hello again\",\"message\":\"beat2\"}")
echo "$ADVANCED" | python3 -m json.tool
ADVANCED="$ADVANCED" BASE="$BASE" python3 - <<'PY'
import json, os, urllib.parse, urllib.request
advanced = json.loads(os.environ["ADVANCED"])
base = os.environ["BASE"]
iota_did = advanced.get("iota_did")
if iota_did:
    enc = urllib.parse.quote(iota_did, safe="")
    resolved = json.load(urllib.request.urlopen(f"{base}/v1/identity/resolve?did={enc}"))
    assert resolved.get("head_source") == "on_chain", resolved
    assert resolved.get("head_cid") == advanced["head_cid"], resolved
    print("advanced on-chain head", resolved["head_cid"])
PY

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
