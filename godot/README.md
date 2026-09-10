# Godot lab veneer

Thin **physical-world UI** for `sep_26_concrete` ([ADR 0001](../docs/decisions/0001-lab-toolchain.md) / [0004](../docs/decisions/0004-world-state-supervisor.md) / [0009](../docs/decisions/0009-godot-scenario-worlds.md)). **Not** ground truth — talks only to OTP HTTP at `http://127.0.0.1:4000`.

**Today:** 2D form (`scenes/main.tscn`) — plaque create/advance, directory people, Eve deny. This scene is the **node console** content for the 3D laptop (0009).

**Next:** 3D room + session host + issuance document + headless **peer** playbooks. Plan: [docs/09](../docs/09-godot-scenario-worlds.md). Coding brief: [docs/10](../docs/10-godot-stage1-build.md).

## Prerequisites

```bash
./scripts/lab-up.sh      # IPFS + IOTA (needed for did:iota directory / plaques)
./scripts/node-up.sh     # OTP :4000
```

## Open (current 2D console)

```bash
./scripts/godot-up.sh
# or: godot --path godot
```

Requires **Godot 4.x** on the host (`GODOT_BIN` overrides path). Project features **4.5**.

## What the 2D console can do

1. See King from `/v1/bootstrap` (truncated ML-DSA-87 public key)
2. See directory **people** from `/v1/directory` (`{pubkey, username}` as **data**)
3. **Create** an info object as King
4. Plaque from backend, **author** as truncated pubkey
5. **Advance** as King
6. **Try as Eve** — directory publish as King; Eve advance denied

## 3D / playbooks (after stages 1–4)

Windowed process is the **session host**. Scripted user is a **second** `godot --headless` process that joins, picks up an issuance document like a human, sits at the laptop, and drives this console. Curl mutates are not the user. See ADR 0009.
