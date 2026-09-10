# Architecture (this prototype)

Working architecture for `sep_26_concrete`. This is **not** a restatement of the full CONCRETE stack on the site. It is what we are willing to build toward in this iteration.

## Target shape (stable intent)

```text
[ thin UI veneer ]
        |
        v
[ node runtime — compute / orchestration ]
        |
   +----+----+
   v         v
[ content store ]   [ naming + authority (ledger-like) ]
   (CID graph)         (name → head, caps / AdminCap-like)
```

- **UI** — **Godot** physical-world veneer only; no Phoenix ([ADR 0001](decisions/0001-lab-toolchain.md), [ADR 0004](decisions/0004-world-state-supervisor.md)).
- **Node runtime** — **Elixir / OTP (BEAM)** for orchestration ([ADR 0003](decisions/0003-runtime-beam.md)); TCP/IP under the hood now, RINA overlay later.
- **Content store** — content-addressed Blob / Tree / Commit graph on **stock IPFS** (lab stand-in; [ADR 0002](decisions/0002-ipfs-iota-did.md)).
- **Naming + authority** — durable **DID** → head: **IOTA Identity** on stock IOTA is head authority ([ADR 0007](decisions/0007-iota-did-head-authority.md)); OTP orchestrates and checks the bootstrap cap ([ADR 0005](decisions/0005-bootstrap-capability.md)). Content bytes on IPFS ([ADR 0002](decisions/0002-ipfs-iota-did.md)).

## Lab vs product topology

| | Lab harness (allowed) | Product narrative (goal) |
|--|------------------------|---------------------------|
| Control | May use a privileged **lab supervisor** for demos (seed world, publish god-view) | Equal peers; no central controller required |
| Packaging | **Docker Compose** OK as stand-ins; pin versions for clone-and-go | Stand-ins are disposable; none assumed final |
| UI tooling | Godot editor on **host**; project in-repo talks to OTP API ports | Physical veneer only; not ground truth ([ADR 0004](decisions/0004-world-state-supervisor.md)) |
| Position | Supervisor (lab) may hold **god-view**; node holds **belief** | Same split without a privileged centre |

If a lab harness is used, label it explicitly in the slice doc so it is not mistaken for architecture. Contributor path: OSS tools only; Cursor optional ([ADR 0001](decisions/0001-lab-toolchain.md)).

## Integration rules (from residues)

1. Prefer **typed APIs/SDKs** over shelling out to CLIs for ledger/content operations.
2. Do not add policy engines, keystores, or observability planes **until** the vertical slice names a need.
3. One enforced capability check on the critical path before claiming “capability-based.”

## Open decisions (need ADRs)

Record choices under `docs/decisions/` before coding:

- [x] Runtime language / distribution model → **Elixir / BEAM** ([ADR 0003](decisions/0003-runtime-beam.md))
- [x] UI technology → **Godot** ([ADR 0001](decisions/0001-lab-toolchain.md))
- [x] Lab packaging → **Docker Compose** harness; Godot on host ([ADR 0001](decisions/0001-lab-toolchain.md))
- [x] Content store → **stock IPFS** (lab stand-in; [ADR 0002](decisions/0002-ipfs-iota-did.md))
- [x] Naming → **DID** via IOTA Identity on stock IOTA ([ADR 0002](decisions/0002-ipfs-iota-did.md))
- [x] How the first capability is represented and checked → **bootstrap cap to first user on first node** (do-anything; [ADR 0005](decisions/0005-bootstrap-capability.md))
- [x] Lab supervisor → **yes, labelled harness**; seed + god-view; not live cap/commit authority ([ADR 0004](decisions/0004-world-state-supervisor.md))
- [x] Godot scenario worlds / node console / playbook bots → **accepted** ([ADR 0009](decisions/0009-godot-scenario-worlds.md); plan [09](09-godot-scenario-worlds.md); stages 1–4 brief [10](10-godot-stage1-build.md); belief overlay later)
- [ ] RINA overlay packaging (later in this prototype; [ADR 0002](decisions/0002-ipfs-iota-did.md))
- [x] BEAM app shape for UI → **OTP without Phoenix**; Godot only ([ADR 0004](decisions/0004-world-state-supervisor.md))
- [x] Interim naming for frozen slice → **lab DID + IPFS DID doc** ([ADR 0006](decisions/0006-lab-did-until-iota-identity.md)); superseded for new objects by 0007
- [x] Name → head authority after Identity → **on-chain Identity DID doc**; OTP executor / cache ([ADR 0007](decisions/0007-iota-did-head-authority.md))
- [x] User cryptographic identity → **external FIPS 202 seed; HKDF/ML-DSA-87; pubkey as principal truth; `{pubkey, username}` as IPFS data + `did:iota`; bootstrap cap gates access** ([ADR 0008](decisions/0008-user-crypto-identity.md) accepted; stages 1–4 in lab; signatures/vault later)
- [ ] Exact OTP process layout (index vs GenServer after 0007 D)
- [ ] Bootstrap capability wire format (Move / DID-linked / …) when caps move on-ledger with Identity
- [ ] Typed Identity client from BEAM (harness CLI/PTB remains until this pays rent)

## Programme map vs this prototype

Owner outline for hardware, CoTs, funding, K_DAG, Wendy-links, presence, etc. lives in [07-programme-map.md](07-programme-map.md) with triage in [05-concept-backlog.md](05-concept-backlog.md). Networking narrative on that map is **RINA** (not Ouroboros). Lab path starts on **TCP/IP** with stock IPFS/IOTA; **RINA overlay later in this prototype** ([ADR 0002](decisions/0002-ipfs-iota-did.md)). Almost all of the programme map remains **paper** until promoted.

## Non-architecture

See [06-out-of-scope.md](06-out-of-scope.md). Programme-map components (seL4, CHERI, RINA, TSS/MPC key ceremony, Matrix, national sync plant, full HQDM, task settler trio, etc.) are **concerns on a map**, not commitments for this repo until promoted via backlog + ADR.
