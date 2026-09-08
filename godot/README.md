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

1. See King principal from `/v1/bootstrap`
2. **Create** an info object (DID + IPFS commit) as King
3. See plaque fields from backend refresh
4. **Advance** as King
5. **Try as Eve** — expect deny; plaque unchanged
