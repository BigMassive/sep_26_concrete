# Node runtime (Elixir / OTP)

Lab **node runtime** for `sep_26_concrete` — not Phoenix, not Godot. See [ADR 0003](../docs/decisions/0003-runtime-beam.md), [ADR 0005](../docs/decisions/0005-bootstrap-capability.md). Name → head authority is **IOTA Identity** ([ADR 0007](../docs/decisions/0007-iota-did-head-authority.md)); this process executes and caches.

## Beat 1 — bootstrap

On first start (empty `lab/data/node/`), creates **node-1**, onboards **King** via the user-identity sidecar (ADR 0008: index-0 ML-DSA-87 **public key** is the principal id), and assigns the **bootstrap/do-anything** capability to that key.

```bash
# Optional: lab IPFS/IOTA (needed from beat 2+)
./scripts/lab-up.sh

./scripts/node-up.sh          # terminal A — http://127.0.0.1:4000
./scripts/beat1-smoke.sh      # terminal B
```

## Beats 2+ — info objects (DID + IPFS)

Requires lab IPFS (`./scripts/lab-up.sh`). When the Identity package is configured, API `did` is `did:iota:…` (ADR 0007 C). Without a package, Phase 1 `did:concrete:lab:…` remains.

```bash
./scripts/beat2-smoke.sh
./scripts/godot-up.sh      # Godot veneer
```

## HTTP

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Liveness (+ `ipfs` / `iota` / naming status) |
| GET | `/v1/identity/status` | Phase 2 IOTA Identity readiness |
| POST | `/v1/identity` | Create on-ledger Identity (cap-checked) |
| GET | `/v1/identity/resolve?did=…` | Resolve `did:iota:…` via RPC; head CID from on-chain DID doc |
| POST | `/v1/identity/head` | Cap-checked on-chain DID-doc update (`ContentHead` → IPFS CID) |
| GET | `/v1/bootstrap` | Node, King, bootstrap cap, principals |
| POST | `/v1/principals` | `{"display_name":"Eve"}` — extra user **without** bootstrap cap |
| GET | `/v1/directory?principal_id=…` | User-directory **data** records (cap-checked) |
| GET | `/v1/directory/record?principal_id=…&did=…` | Hydrate one directory blob from IPFS |
| POST | `/v1/directory` | `{"principal_id","username"}` — publish `{pubkey, username}` to IPFS (cap-checked) |
| POST | `/v1/capability/check` | `{"principal_id":"…","action":"mutate"}` — allow/deny |
| GET | `/v1/info_objects` | List known objects |
| GET | `/v1/info_object?did=…` | Current plaque (content + head) |
| POST | `/v1/info_objects` | Create (King / bootstrap cap) |
| POST | `/v1/info_objects/advance` | Advance head (cap-checked) |

State: `lab/data/node/` (gitignored). Slice frozen (Phase 1). Identity: ADR 0007 A–D (fail closed, GET from chain, `did:iota:…`, index-only registry).
