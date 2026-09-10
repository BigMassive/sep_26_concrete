# Godot lab veneer

Thin **physical-world UI** for `sep_26_concrete` (ADR 0001 / 0004). **Not** ground truth — talks only to OTP HTTP at `http://127.0.0.1:4000`.

## Prerequisites

```bash
./scripts/lab-up.sh      # IPFS + IOTA
./scripts/node-up.sh     # OTP :4000
```

## Open

```bash
./scripts/godot-up.sh
# or: godot --path godot
```

Requires **Godot 4.x** on the host (`GODOT_BIN` overrides path).

## What you can do

1. See King principal from `/v1/bootstrap` (truncated ML-DSA-87 public key)
2. See directory **people** from `/v1/directory` (`{pubkey, username}` as **data**, not a plaque)
3. **Create** an info object (DID + IPFS commit) as King
4. See plaque fields from backend refresh, including **author** as truncated pubkey (primary DID is `did:iota:…` when Identity is configured)
5. **Advance** as King
6. **Try as Eve** — King may publish Eve’s directory record; Eve’s plaque advance is still denied
