# Node runtime (Elixir / OTP)

Lab **ground truth** for `sep_26_concrete` — not Phoenix, not Godot. See [ADR 0003](../docs/decisions/0003-runtime-beam.md), [ADR 0005](../docs/decisions/0005-bootstrap-capability.md).

## Beat 1 — bootstrap

On first start (empty `lab/data/node/`), creates **node-1**, principal **King**, and the **bootstrap/do-anything** capability held by King.

```bash
# Optional: lab IPFS/IOTA (needed from beat 2+)
./scripts/lab-up.sh

./scripts/node-up.sh          # terminal A — http://127.0.0.1:4000
./scripts/beat1-smoke.sh      # terminal B
```

## Beats 2+ — info objects (DID + IPFS)

Requires lab IPFS (`./scripts/lab-up.sh`). Creates `did:concrete:lab:…`, stores content/commit/DID doc on IPFS, stamps optional IOTA checkpoint metadata.

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
| GET | `/v1/identity/resolve?did=…` | Resolve `did:iota:…` via RPC + OTP head map |
| POST | `/v1/identity/head` | Track head CID for a DID (OTP until on-chain doc) |
| GET | `/v1/bootstrap` | Node, King, bootstrap cap, principals |
| POST | `/v1/principals` | `{"display_name":"Eve"}` — extra user **without** bootstrap cap |
| POST | `/v1/capability/check` | `{"principal_id":"…","action":"mutate"}` — allow/deny |
| GET | `/v1/info_objects` | List known objects |
| GET | `/v1/info_object?did=…` | Current plaque (content + head) |
| POST | `/v1/info_objects` | Create (King / bootstrap cap) |
| POST | `/v1/info_objects/advance` | Advance head (cap-checked) |

State: `lab/data/node/` (gitignored). Slice frozen; Identity publish is Phase 2.
