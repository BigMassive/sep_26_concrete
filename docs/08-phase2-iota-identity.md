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
| Identity Move package on localnet | **done** — `./scripts/identity-publish.sh` → `lab/data/iota/identity_pkg_id.txt` |
| OTP `Identity::new` + resolve | **done** — `/v1/identity`, `/v1/identity/resolve` |
| Head CID on-chain in DID doc bytes | **pending** — head tracked in OTP `iota_heads.json` until SDK encode/update |

## Lab commands

```bash
./scripts/lab-up.sh
./scripts/identity-publish.sh   # once per genesis (writes identity_pkg_id.txt)
./scripts/node-up.sh            # loads IOTA_IDENTITY_PKG_ID automatically
./scripts/identity-smoke.sh
```

Creating an info object while the package is configured also best-effort attaches an `iota_did` / `identity_object_id`.

## Probe

```bash
curl -s http://127.0.0.1:4000/v1/identity/status | python3 -m json.tool
```

`package_configured` / `publish_ready` should be true after publish + node restart.

## Still open

1. Encode a real DID document (with ContentHead service → IPFS CID) and `propose_update` / `execute_update` on-chain.
2. Prefer a typed Identity client from BEAM (or labelled sidecar) over `iota client` in Docker for create.
3. Godot plaque field for `iota_did`.
