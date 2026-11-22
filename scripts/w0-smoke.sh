#!/usr/bin/env bash
# Live W0 genesis against OTP HTTP + lab IPFS/IOTA. Agent-facing.
# Does not drive Godot. Requires ./scripts/lab-up.sh and ./scripts/node-up.sh.
# If CoT already exists, set CONCRETE_SMOKE_ZEROISE=1 to wipe and retry.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${CONCRETE_HTTP_PORT:-4000}"
BASE="http://127.0.0.1:${PORT}"

fail() { echo "w0-smoke FAIL: $*" >&2; exit 1; }

echo "Lab…"
curl -sf -X POST "http://127.0.0.1:5001/api/v0/id" >/dev/null || fail "IPFS down"
curl -sf -X POST "http://127.0.0.1:9000" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"iota_getLatestCheckpointSequenceNumber","params":[]}' \
  >/dev/null || fail "IOTA down (genesis 502 PTB: identity create cannot connect — ./scripts/lab-up.sh)"

echo "OTP ${BASE}…"
LAB_JSON=$(curl -sS "${BASE}/v1/lab" || fail "OTP unreachable — ./scripts/node-up.sh")
echo "${LAB_JSON}" | python3 -m json.tool
python3 -c "
import json,sys
lab=json.loads(sys.argv[1])
assert lab.get('powered', False), 'node powered off'
print('genesis_complete', lab.get('genesis_complete'))
" "${LAB_JSON}"

COMPLETE=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('genesis_complete', False))" "${LAB_JSON}")
if [[ "${COMPLETE}" == "True" ]]; then
  if [[ "${CONCRETE_SMOKE_ZEROISE:-}" == "1" ]]; then
    echo "Zeroising existing CoT…"
    curl -sS -X POST "${BASE}/v1/lab/zeroise" -H 'Content-Type: application/json' -d '{}' | python3 -m json.tool
  else
    echo "CoT already exists — skip genesis (CONCRETE_SMOKE_ZEROISE=1 to retry)."
    echo "w0-smoke OK (already genesis complete)"
    exit 0
  fi
fi

echo "POST /v1/genesis…"
BODY='{"username":"Helen","public_key":"mldsa87:paper-helen","private_key":"paper-helen-sk","pin":"12345"}'
CODE=$(curl -sS -o /tmp/w0-smoke.json -w '%{http_code}' -X POST "${BASE}/v1/genesis" \
  -H 'Content-Type: application/json' -d "${BODY}")
python3 -m json.tool </tmp/w0-smoke.json || cat /tmp/w0-smoke.json
if [[ "${CODE}" != "201" ]]; then
  fail "genesis HTTP ${CODE} (see JSON above)"
fi
python3 -c '
import json
r=json.load(open("/tmp/w0-smoke.json"))
assert str(r.get("g_did","")).startswith("did:"), r
assert str(r.get("d2_did","")).startswith("did:"), r
print("g_did", r["g_did"])
print("d2_did", r["d2_did"])
'
echo "w0-smoke OK"
