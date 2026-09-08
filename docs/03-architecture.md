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

- **UI** — thinnest possible control/observation surface; **Godot** (see [ADR 0001](decisions/0001-lab-toolchain.md)).
- **Node runtime** — hosts orchestration for the vertical slice (language/runtime deferred; BEAM earned keep in Mar_26 for distribution, not mandated yet).
- **Content store** — content-addressed Blob / Tree / Commit graph (IPFS-like).
- **Naming + authority** — durable name → head; gated mutation of shared authority objects.

## Lab vs product topology

| | Lab harness (allowed) | Product narrative (goal) |
|--|------------------------|---------------------------|
| Control | May use a privileged supervisor for demos | Equal peers; no central controller required |
| Packaging | **Docker Compose** OK as stand-ins; pin versions for clone-and-go | Stand-ins are disposable; none assumed final |
| UI tooling | Godot editor on **host**; project in-repo talks to published ports | Not a shipping client stack commitment |

If a lab harness is used, label it explicitly in the slice doc so it is not mistaken for architecture. Contributor path: OSS tools only; Cursor optional ([ADR 0001](decisions/0001-lab-toolchain.md)).

## Integration rules (from residues)

1. Prefer **typed APIs/SDKs** over shelling out to CLIs for ledger/content operations.
2. Do not add policy engines, keystores, or observability planes **until** the vertical slice names a need.
3. One enforced capability check on the critical path before claiming “capability-based.”

## Open decisions (need ADRs)

Record choices under `docs/decisions/` before coding:

- [ ] Runtime language / distribution model
- [x] UI technology → **Godot** ([ADR 0001](decisions/0001-lab-toolchain.md))
- [x] Lab packaging → **Docker Compose** harness; Godot on host ([ADR 0001](decisions/0001-lab-toolchain.md))
- [ ] Content store (IPFS vs stand-in)
- [ ] Naming: IINL-like vs IOTA Identity DID vs other
- [ ] How the first capability is represented and checked
- [ ] Whether a lab supervisor exists and how it is labelled

## Programme map vs this prototype

Owner outline for hardware, CoTs, funding, K_DAG, Wendy-links, presence, etc. lives in [07-programme-map.md](07-programme-map.md) with triage in [05-concept-backlog.md](05-concept-backlog.md). Networking narrative on that map is **RINA** (not Ouroboros). Almost all of that map is **paper** until promoted.

## Non-architecture

See [06-out-of-scope.md](06-out-of-scope.md). Programme-map components (seL4, CHERI, RINA, TSS/MPC key ceremony, Matrix, national sync plant, full HQDM, task settler trio, etc.) are **concerns on a map**, not commitments for this repo until promoted via backlog + ADR.
