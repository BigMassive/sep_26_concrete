# Phase 2 — IOTA Identity publish

First post-freeze promotion ([roadmap.md](roadmap.md), [ADR 0006](decisions/0006-lab-did-until-iota-identity.md)). Head authority for **new** work: [ADR 0007](decisions/0007-iota-did-head-authority.md).

## Goal

**Name → head CID** lives on stock IOTA Identity, not in an OTP JSON field that can disagree with the ledger ([ADR 0002](decisions/0002-ipfs-iota-did.md)).

Happy-path publish (package + create/resolve + on-chain ContentHead) and ADR 0007 **A–D** are **implemented**: fail closed on mutate, GET from chain, iota-only names when the package is configured, OTP registry as index.

Lab assumption (owner, 2026-09-10): Compose IOTA and Docker `iota client ptb` are stable enough; do not build drift-as-a-product. A failed PTB is a failed create/advance.

## Current lab state

| Piece | Status |
|--------|--------|
| IOTA localnet (Compose) | done — beat 0 |
| Checkpoint stamp on commits | done — metadata only |
| Lab DID + IPFS DID document | **Phase 1 freeze** — still in code; superseded for *new* objects by ADR 0007 |
| Identity Move package on localnet | **done** — `./scripts/identity-publish.sh` → `lab/data/iota/identity_pkg_id.txt` |
| OTP `Identity::new` + resolve | **done** — `/v1/identity`, `/v1/identity/resolve` |
| Head CID on-chain in DID doc bytes | **done** (happy path) — packed DID-method-v2 JSON via `Identity::new` / `propose_update` |
| OTP vs chain as competing heads | **superseded** — mutate fail-closed; GET from chain |
| Chain as sole head authority | **done** — ADR 0007 A–D |

## Lab commands

```bash
./scripts/lab-up.sh
./scripts/identity-publish.sh   # once per genesis (writes identity_pkg_id.txt)
./scripts/node-up.sh            # loads IOTA_IDENTITY_PKG_ID automatically
./scripts/identity-smoke.sh
```

Creating an info object while the package is configured **requires** on-chain `Identity::new` / `propose_update` (or the HTTP call fails). OTP persists an index (iota DID, ControllerCap id, label), not an authoritative `head_cid`. Without a package, the Phase 1 lab DID path remains.

## On-chain DID document

Packed per [IOTA DID method v2](https://docs.iota.org/developer/iota-identity/references/iota-did-method-spec): magic `DID`, version `1`, JSON encoding `0`, `u16` length, then `{"doc":…,"meta":…}` with placeholder `did:0:0`. A `ContentHead` service holds `ipfs://<head_cid>`. Create uses `Identity::new`; later heads use `controller::borrow` → `Identity::propose_update` → `put_back` (single-controller identities execute inside `propose_update`).

`iota_heads.json` keeps the **ControllerCap** id needed to sign updates (custody metadata), not a head.

## Stages (done)

See [ADR 0007](decisions/0007-iota-did-head-authority.md).

1. **A — Fail closed.** Package configured ⇒ create/advance errors if on-chain head does not move. Orphan IPFS blobs allowed; the name does not advance.
2. **B — Reads from chain.** Hydrate plaque from Identity ContentHead → IPFS.
3. **C — Iota-only names.** API `did` is `did:iota:…`. Stop minting `did:concrete:lab:…` when the package is configured. Godot / beat 2 / beat 6 follow.
4. **D — Index only.** OTP stores iota DID, ControllerCap id, label; list is a projection. GenServer remains orchestrator (cap check + IPFS + PTB), not a second ledger.

Godot still talks only to OTP `:4000`.

## Probe

```bash
curl -s http://127.0.0.1:4000/v1/identity/status | python3 -m json.tool
```

`package_configured` / `publish_ready` should be true after publish + node restart.

## Still open (not this promotion)

1. Typed Identity client from BEAM (or labelled sidecar) instead of `iota client ptb` — ADR 0002 preference; not a prerequisite for A–D.
2. CLI Option encoding (`none` / `some(vector[…])`) is harness detail; packed document is specified.
3. ControllerCap is owned by the **lab IOTA wallet**, not by King. Bootstrap cap stays OTP ([ADR 0005](decisions/0005-bootstrap-capability.md)) until a later ADR.
4. Pin `identity.rs` publish ref to a tag (lab reproducibility).
