#!/usr/bin/env bash
# Live Helen→Alice scenes 1–7 against OTP HTTP + lab IPFS/IOTA. Agent-facing.
# Does not drive Godot. Requires ./scripts/lab-up.sh and ./scripts/node-up.sh.
# Uses SmokeAlice-* keys so paper Alice remains free for hand-play.
# If CoT is empty, W0 uses paper-helen (same as w0-smoke). Set
# CONCRETE_SMOKE_ZEROISE=1 to wipe first. Helen PIN 12345 / paper-helen-sk.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${CONCRETE_HTTP_PORT:-4000}"
BASE="http://127.0.0.1:${PORT}"
export BASE

fail() { echo "beat-smoke FAIL: $*" >&2; exit 1; }

echo "Lab…"
curl -sf -X POST "http://127.0.0.1:5001/api/v0/id" >/dev/null || fail "IPFS down"
curl -sf -X POST "http://127.0.0.1:9000" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"iota_getLatestCheckpointSequenceNumber","params":[]}' \
  >/dev/null || fail "IOTA down (502 PTB: ./scripts/lab-up.sh)"

echo "OTP ${BASE}…"
curl -sf "${BASE}/health" >/dev/null || fail "OTP unreachable — ./scripts/node-up.sh"

if [[ "${CONCRETE_SMOKE_ZEROISE:-}" == "1" ]]; then
  echo "Zeroising existing CoT…"
  curl -sS -X POST "${BASE}/v1/lab/zeroise" -H 'Content-Type: application/json' -d '{}' >/dev/null
fi

python3 - <<'PY'
import json, os, sys, time, urllib.error, urllib.parse, urllib.request

base = os.environ["BASE"]

def req(method, path, body=None, expect=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {"Content-Type": "application/json"} if body is not None else {}
    r = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=180) as resp:
            raw = resp.read().decode()
            parsed = json.loads(raw) if raw else {}
            if expect is not None and resp.status != expect:
                print(json.dumps(parsed, indent=2))
                sys.exit(f"expected HTTP {expect} got {resp.status} {path}")
            return resp.status, parsed
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            parsed = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            parsed = {"raw": raw}
        if expect is not None and e.code != expect:
            print(json.dumps(parsed, indent=2))
            sys.exit(f"expected HTTP {expect} got {e.code} {path}")
        return e.code, parsed

def get(path, expect=200):
    return req("GET", path, expect=expect)

def post(path, body, expect=None):
    return req("POST", path, body, expect=expect)

print("scene 1: lab + empty-or-existing CoT")
st, lab = get("/v1/lab")
assert lab.get("powered") is True, lab
print("  powered", lab.get("powered"), "genesis_complete", lab.get("genesis_complete"))

st, boot = get("/v1/bootstrap")
if not boot.get("genesis_complete"):
    print("scene 2: POST /v1/genesis (Helen paper)")
    st, genesis = post("/v1/genesis", {
        "username": "Helen",
        "public_key": "mldsa87:paper-helen",
        "private_key": "paper-helen-sk",
        "pin": "12345",
    }, expect=201)
    assert str(genesis.get("g_did", "")).startswith("did:"), genesis
    print("  g_did", genesis["g_did"])
    boot = get("/v1/bootstrap")[1]
else:
    print("scene 2: CoT already complete — skip W0 (CONCRETE_SMOKE_ZEROISE=1 to retry)")

print("  replay genesis → 409")
st, replay = post("/v1/genesis", {
    "username": "Helen",
    "public_key": "mldsa87:paper-helen",
    "private_key": "paper-helen-sk",
    "pin": "12345",
}, expect=409)
assert replay.get("error") == "genesis_replay", replay

king = boot["king"]
helen_id = king["id"]
cot = boot["cot"]
g_did = cot["g_did"]
d4_did = cot["d4_did"]
print("  king", helen_id)

print("scene 3: GraphEdit locked; W1 SmokeAlice")
st, locked = post("/v1/workspaces/save", {
    "principal_id": helen_id,
    "id": "w1",
    "layout": {"grants": [{"verb": "bootstrap"}]},
}, expect=403)
assert locked.get("error") == "graph_locked", locked

def ensure_helen_vault():
    sess = get("/v1/session")[1]
    if sess.get("logged_in") and sess.get("principal_id") != helen_id:
        post("/v1/session/logout", {"principal_id": sess["principal_id"]}, expect=200)
    st, login_h = post("/v1/session/login", {
        "username": king.get("display_name") or "Helen",
        "pin": "12345",
        "private_key": "paper-helen-sk",
    })
    if st in (200, 409):
        return
    print(json.dumps(login_h, indent=2))
    sys.exit(f"Helen login failed HTTP {st} (need PIN 12345 / paper-helen-sk)")

uname = f"SmokeAlice-{int(time.time())}"
alice_pk = f"mldsa87:smoke-alice-{int(time.time())}"
alice_sk = "smoke-alice-sk"
print("  introduce", uname)
st, intro = post("/v1/workspaces/run", {
    "principal_id": helen_id,
    "id": "w1",
    "username": uname,
    "public_key": alice_pk,
})
if st == 403 and intro.get("error") == "vault_unusable":
    print("  Helen vault unusable — login with paper")
    ensure_helen_vault()
    st, intro = post("/v1/workspaces/run", {
        "principal_id": helen_id,
        "id": "w1",
        "username": uname,
        "public_key": alice_pk,
    }, expect=201)
elif st != 201:
    print(json.dumps(intro, indent=2))
    sys.exit(f"W1 expected 201 got {st}")
pin = intro.get("pin")
assert pin and len(pin) == 5 and pin.isdigit(), intro
assert str(intro.get("d5_did", "")).startswith("did:"), intro
print("  pin", pin, "d5", intro["d5_did"])

print("scene 4: Exit session")
st, logged = post("/v1/session/logout", {"principal_id": helen_id}, expect=200)
assert logged.get("logged_in") is False, logged

print("scene 5: wrong PIN 403; Alice login")
st, bad = post("/v1/session/login", {
    "username": uname,
    "pin": "00000",
    "private_key": alice_sk,
}, expect=403)
assert bad.get("error") == "pin_mismatch", bad

st, login = post("/v1/session/login", {
    "username": uname,
    "pin": pin,
    "private_key": alice_sk,
}, expect=200)
assert login["principal"]["id"] == alice_pk, login

st, denied = post("/v1/workspaces/run", {
    "principal_id": alice_pk,
    "id": "w1",
    "username": "Mallory",
    "public_key": "mldsa87:mallory",
}, expect=403)
print("  Alice W1 denied", denied.get("error"))

print("scene 6: discovery G + D4 marker")
enc_alice = urllib.parse.quote(alice_pk, safe="")
st, graph = get(f"/v1/discovery?principal_id={enc_alice}")
dids = [n["did"] for n in graph.get("nodes", [])]
assert g_did in dids, {"g_did": g_did, "dids": dids}
d4_node = next((n for n in graph["nodes"] if n["did"] == d4_did), None)
assert d4_node, {"d4_did": d4_did, "nodes": graph["nodes"]}
assert d4_node.get("kind") == "data", d4_node
assert d4_node.get("marker") is True, d4_node
assert "payload" not in d4_node, d4_node
assert "pin" not in d4_node, d4_node

enc_d4 = urllib.parse.quote(d4_did, safe="")
st, d4 = get(f"/v1/data_object?principal_id={enc_alice}&did={enc_d4}")
assert d4.get("marker") is True, d4
assert "payload" not in d4, d4
print("  nodes", len(graph["nodes"]), "D4 marker ok")

print("scene 7: W2 + rediscovery")
st, info = post("/v1/workspaces/run", {
    "principal_id": alice_pk,
    "id": "w2",
    "text": "Hello from SmokeAlice",
    "readers": ["Helen", uname],
    "writers": [uname],
    "link_did": g_did,
}, expect=201)
info_did = info.get("did")
assert str(info_did or "").startswith("did:"), info
print("  info", info_did)

st, graph2 = get(f"/v1/discovery?principal_id={enc_alice}")
dids2 = [n["did"] for n in graph2.get("nodes", [])]
assert info_did in dids2, {"info": info_did, "dids": dids2}
node = next(n for n in graph2["nodes"] if n["did"] == info_did)
assert node.get("kind") == "info", node
assert node.get("marker") is False, node
print("beat-smoke OK")
PY
