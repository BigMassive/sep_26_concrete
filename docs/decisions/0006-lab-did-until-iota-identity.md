# ADR 0006: Interim lab DID method until IOTA Identity publish

- Status: superseded by [ADR 0007](0007-iota-did-head-authority.md) (2026-09-10) for new objects and head authority
- Date: 2026-09-08

## Context

[ADR 0002](0002-ipfs-iota-did.md) requires **DIDs from the start** via **IOTA Identity** on stock IOTA, with a DID (or DID-linked field) holding the updateable IPFS head.

The frozen vertical slice proves name → head, IPFS commits, and one capability check using a **lab DID method** (`did:concrete:lab:…`) whose document is stored on **IPFS**, with IOTA used only as a **checkpoint stamp** on commit metadata. That is enough for slice acceptance, but it does **not** yet satisfy ADR 0002’s on-ledger Identity publish.

## Decision

1. **Freeze the slice** on the lab DID + IPFS DID document + OTP registry path already implemented.
2. Treat **IOTA Identity create/resolve/update-head** as the **first Phase 2** promotion after freeze — not a redefinition of the frozen slice.
3. Until Identity publish lands, API responses may continue to expose `did:concrete:lab:…`, `did_doc_cid`, and `iota_checkpoint`.
4. When Identity lands, prefer `did:iota:…` (or the method the stock Identity stack provides on this localnet); keep a migration note so Godot still only talks to OTP.
5. Do not expand into a full VC/credentials platform unless a later backlog promotion names that need ([ADR 0002](0002-ipfs-iota-did.md) slice discipline).

## Consequences

- Vertical slice can be marked **frozen** without claiming on-ledger Identity is done.
- Backlog row “Name → head (DID)” stays **slice** for the proven path; add an explicit **Phase 2** row for IOTA Identity publish.
- Open architecture item “bootstrap capability wire format” remains separate; lab JSON on disk is acceptable until caps move on-ledger with Identity.

Phase 1 freeze remains a completed storyboard. Head authority and new-object naming after Identity publish: [ADR 0007](0007-iota-did-head-authority.md).
