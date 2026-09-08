#!/usr/bin/env bash
# Beat 6: refresh proof — after OTP restart, plaque still matches (UI has no durable state).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${CONCRETE_HTTP_PORT:-4000}"
BASE="http://127.0.0.1:${PORT}"
DATA_DIR="${CONCRETE_DATA_DIR:-${ROOT}/lab/data/node}"

echo "Health…"
curl -sf "${BASE}/health" | python3 -m json.tool >/dev/null

BOOT=$(curl -sf "${BASE}/v1/bootstrap")
KING=$(echo "$BOOT" | python3 -c "import sys,json; print(json.load(sys.stdin)['king']['id'])")

LIST=$(curl -sf "${BASE}/v1/info_objects")
DID=$(echo "$LIST" | python3 -c "import sys,json; o=json.load(sys.stdin).get('objects') or []; print(o[0]['did'] if o else '')")

if [[ -z "${DID}" ]]; then
  echo "No object yet — creating…"
  CREATED=$(curl -sf -X POST "${BASE}/v1/info_objects" \
    -H 'Content-Type: application/json' \
    -d "{\"principal_id\":\"${KING}\",\"content\":\"beat6 plaque\",\"label\":\"plaque\"}")
  DID=$(echo "$CREATED" | python3 -c "import sys,json; print(json.load(sys.stdin)['did'])")
fi

ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$DID''', safe=''))")
BEFORE=$(curl -sf "${BASE}/v1/info_object?did=${ENC}")
echo "Before restart:"
echo "$BEFORE" | python3 -m json.tool
python3 -c "import json,sys; d=json.load(sys.stdin); open('/tmp/beat6_before.json','w').write(json.dumps({'did':d['did'],'head_cid':d['head_cid'],'content':d['content']}, sort_keys=True))" <<<"$BEFORE"

echo
echo "Restarting OTP (same data dir: ${DATA_DIR})…"
fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1
cd "${ROOT}/runtime"
export CONCRETE_DATA_DIR="${DATA_DIR}"
export CONCRETE_HTTP_PORT="${PORT}"
mix run --no-halt >/tmp/concrete_runtime_beat6.log 2>&1 &
echo $! >/tmp/concrete_runtime_beat6.pid
for i in $(seq 1 60); do
  curl -sf "${BASE}/health" >/dev/null && break
  sleep 0.25
done
curl -sf "${BASE}/health" | python3 -m json.tool >/dev/null

AFTER=$(curl -sf "${BASE}/v1/info_object?did=${ENC}")
echo "After restart:"
echo "$AFTER" | python3 -m json.tool
python3 -c "import json,sys; d=json.load(sys.stdin); open('/tmp/beat6_after.json','w').write(json.dumps({'did':d['did'],'head_cid':d['head_cid'],'content':d['content']}, sort_keys=True))" <<<"$AFTER"

diff -u /tmp/beat6_before.json /tmp/beat6_after.json

# Godot veneer must not persist plaque locally
if grep -REn 'FileAccess|user://|plaque\.json' "${ROOT}/godot/scripts" >/dev/null 2>&1; then
  echo "Godot scripts appear to write local plaque state — fail closed for beat 6." >&2
  exit 1
fi

echo
echo "Beat 6 smoke OK (OTP plaque durable; Godot has no local plaque store)."
echo "Manual: ./scripts/godot-up.sh twice and confirm plaque matches this DID/head."
