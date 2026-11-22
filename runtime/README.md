# Node runtime (Elixir / OTP)

Lab **node runtime** for `sep_26_concrete` — not Phoenix, not Godot. See [ADR 0003](../docs/decisions/0003-runtime-beam.md), [ADR 0005](../docs/decisions/0005-bootstrap-capability.md). Name → head authority is **IOTA Identity** ([ADR 0007](../docs/decisions/0007-iota-did-head-authority.md)); this process executes and caches.

## Start

```bash
./scripts/session-up.sh       # wipe, IPFS + IOTA, identity publish, detached OTP
./scripts/session-down.sh
```

Node-up creates **node-1** and does not mint King. The first user is W0 genesis on the console, or `./scripts/godot-scenario.sh helen-alice`. That user’s index-0 ML-DSA-87 public key is the principal, and W0 assigns the bootstrap/**any** capability. `./scripts/beat1-smoke.sh` is the older bootstrap check, not the way to meet King.

## Beats 2+ — info objects (DID + IPFS)

Requires lab IPFS (`./scripts/lab-up.sh`). When the Identity package is configured, API `did` is `did:iota:…` (ADR 0007 C). Without a package, Phase 1 `did:concrete:lab:…` remains.

```bash
./scripts/beat2-smoke.sh
./scripts/godot-up.sh      # window only; prefer session-up, then godot-up or godot-scenario
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
