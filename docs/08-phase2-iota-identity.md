# Phase 2 — IOTA Identity publish

First post-freeze promotion ([roadmap.md](roadmap.md), [ADR 0006](decisions/0006-lab-did-until-iota-identity.md)).

## Goal

Replace (or dual-publish alongside) lab `did:concrete:lab:…` with on-ledger **IOTA Identity** so **name → head CID** resolves from stock IOTA, not only OTP disk + IPFS DID doc ([ADR 0002](decisions/0002-ipfs-iota-did.md)).

## Current lab state

| Piece | Status |
|--------|--------|
| IOTA localnet (Compose) | done — beat 0 |
| Checkpoint stamp on commits | done — metadata only |
| Lab DID + IPFS DID document | frozen slice |
| Identity Move package on localnet | **not yet** |
| OTP create/resolve/update via Identity | **not yet** (`ConcreteRuntime.IotaIdentity`) |

## Intended steps

1. **Publish Identity package** to the lab localnet (IOTA docs: [Local Network Setup](https://docs.iota.org/developer/iota-identity/getting-started/local-network-setup) — `publish_identity_package.sh` from `identity.rs`, export `IOTA_IDENTITY_PKG_ID`).
2. Wire OTP (typed client or thin helper) to **create** Identity, **resolve** DID, **update** document service/field holding IPFS head CID — still behind the same capability check.
3. Godot keeps talking only to OTP; plaque shows `did:iota:…` when available.
4. Keep lab DID as fallback until resolve is proven; then deprecate in a follow-up.

## Probe

With lab + node up:

```bash
curl -s http://127.0.0.1:4000/v1/identity/status | python3 -m json.tool
```

`package_configured` is true only when `IOTA_IDENTITY_PKG_ID` is set. `publish_ready` stays false until create/publish is implemented.
