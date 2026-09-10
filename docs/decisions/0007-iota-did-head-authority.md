# ADR 0007: IOTA Identity is name → head authority; OTP is executor / cache

- Status: accepted
- Date: 2026-09-10
- Supersedes: [ADR 0006](0006-lab-did-until-iota-identity.md) for **new** objects and for **which store is head authority**. The Phase 1 freeze (lab DID path as a completed storyboard) stays historically valid.

## Context

[ADR 0002](0002-ipfs-iota-did.md) requires durable **DID → head CID** via **IOTA Identity** on stock IOTA. [ADR 0006](0006-lab-did-until-iota-identity.md) froze Phase 1 on `did:concrete:lab:…` plus an IPFS DID document and an OTP JSON registry so the vertical slice could ship without on-ledger Identity.

Phase 2 then dual-published: Identity objects with packed DID-method-v2 documents (`ContentHead` → `ipfs://<cid>`), while InfoObjects still treated OTP `head_cid` as success even when on-chain update was best-effort. That leaves two mutable heads.

Owner direction (2026-09-10): assume the **lab happy path** (Compose IOTA + Docker `iota client ptb` stay up). Near-term target is **`did:iota:…` as the only name → head source of truth**. OTP must not keep a competing authoritative head. Godot still talks only to OTP HTTP ([ADR 0004](0004-world-state-supervisor.md)).

This does **not** move the bootstrap capability on-ledger ([ADR 0005](0005-bootstrap-capability.md) still applies). ControllerCap for Identity updates remains the **lab IOTA wallet**, not King — that gap is named, not solved here.

## Decision

1. **Head authority** is the on-chain IOTA Identity DID document (ContentHead service → IPFS commit CID). IPFS remains the content store (blob / commit bytes). OTP `info_objects.json` / `iota_heads.json` may cache or index; they must not win a conflict with chain.
2. **Name** for new info objects is `did:iota:<network-id>:<identity-object-id>`. Stop minting `did:concrete:lab:…` once this promotion is implemented. Existing lab-DID objects are leftovers, not the ongoing contract.
3. **Fail closed on mutate:** if the Identity package is configured, create/advance **must** land the new head on-chain or the HTTP request **fails**. No log-and-201. Orphan IPFS objects on failure are acceptable; the **name** must not have advanced.
4. **OTP role:** Elixir remains the node runtime — capability check, IPFS writes, packing, PTB/harness calls, HTTP for Godot. It is **executor and optional cache**, not a second ledger for the head.
5. **Reads** hydrate from chain ContentHead → IPFS cat (for objects that have an iota DID). Godot still only calls `:4000`.
6. **Lab assumption:** Docker and localnet IOTA are treated as stable for this promotion. Drift-as-a-product-feature is out of scope; a failed PTB is a failed mutate.
7. **Out of this ADR:** typed BEAM Identity SDK, HTTP auth, on-ledger bootstrap cap, retiring OTP as a process, RINA, lab supervisor, VC/credentials.

## Implementation stages

| Stage | Intent | Status |
|-------|--------|--------|
| **A** | Identity configured ⇒ create/advance fail if chain does not accept the new head | done |
| **B** | `GET` hydrates head from Identity resolve, not from OTP `head_cid` as authority | done |
| **C** | New objects are iota-only (`did` in the API **is** `did:iota:…`) | done |
| **D** | Registry shrinks to an index (iota DID, ControllerCap id, label); rebuildable; no authoritative head field | done |

ControllerCap object ids still need a store (file or wallet inventory) so the node can sign `propose_update`. That is custody metadata, not a second head.

## Consequences

- Aligns naming with ADR 0002; dual-publish is a temporary code state, not the architecture.
- IOTA unavailability becomes create/advance failure (accepted under the happy-path lab assumption).
- Beat 2 / 6 / Godot plaque primary DID is `did:iota:…` when Identity is configured.
- Bootstrap cap remains an OTP membership check until a later ADR moves caps on-ledger.
- CLI/PTB harness remains labelled lab; replacing it is not a prerequisite for A–D.
