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

- **UI** — thinnest possible control/observation surface (technology choice deferred; Godot is an option, not a requirement of the docs phase).
- **Node runtime** — hosts orchestration for the vertical slice (language/runtime deferred; BEAM earned keep in Mar_26 for distribution, not mandated yet).
- **Content store** — content-addressed Blob / Tree / Commit graph (IPFS-like).
- **Naming + authority** — durable name → head; gated mutation of shared authority objects.

## Lab vs product topology

| | Lab harness (allowed) | Product narrative (goal) |
|--|------------------------|---------------------------|
| Control | May use a privileged supervisor for demos | Equal peers; no central controller required |
| Packaging | Containers OK as stand-ins | Stand-ins are disposable; none assumed final |

If a lab harness is used, label it explicitly in the slice doc so it is not mistaken for architecture.

## Integration rules (from residues)

1. Prefer **typed APIs/SDKs** over shelling out to CLIs for ledger/content operations.
2. Do not add policy engines, keystores, or observability planes **until** the vertical slice names a need.
3. One enforced capability check on the critical path before claiming “capability-based.”

## Open decisions (need ADRs)

Record choices under `docs/decisions/` before coding:

- [ ] Runtime language / distribution model
- [ ] UI technology
- [ ] Content store (IPFS vs stand-in)
- [ ] Naming: IINL-like vs IOTA Identity DID vs other
- [ ] How the first capability is represented and checked
- [ ] Whether a lab supervisor exists and how it is labelled

## Non-architecture

See [06-out-of-scope.md](06-out-of-scope.md). Site stack components (seL4, Ouroboros, Matrix, spacetime, full HQDM, resource markets) are **concerns on a map**, not commitments for this repo until promoted via backlog + ADR.
