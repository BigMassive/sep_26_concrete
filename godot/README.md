# Godot lab veneer

Thin **physical-world UI** for `sep_26_concrete` ([ADR 0001](../docs/decisions/0001-lab-toolchain.md) / [0004](../docs/decisions/0004-world-state-supervisor.md) / [0009](../docs/decisions/0009-godot-scenario-worlds.md)). **Not** ground truth — talks only to OTP HTTP at `http://127.0.0.1:4000`.

**Main scene:** `scenes/world.tscn` — one 3D room, desk, laptop (`node-1`), issuance tray, listen-server session. The old 2D form (`scenes/main.tscn`) is the **node console** nested in the laptop SubViewport (also `--console-only` for debug).

## Prerequisites

```bash
./scripts/lab-up.sh      # IPFS + IOTA (needed for did:iota directory / plaques)
./scripts/node-up.sh     # OTP :4000
```

Requires **Godot 4.5** on the host (`GODOT_BIN` overrides path).

## Session (listen-server from the start)

Windowed `godot-up` is the **host** (ENet port **24567**). A second process **joins** and appears as another coloured capsule. Host simulates the room; each process still calls OTP HTTP as **that body’s** principal after paper pickup.

```bash
./scripts/godot-up.sh                          # host, windowed
./scripts/godot-join.sh                        # second body (windowed)
# or: godot --path godot --headless -- --join 127.0.0.1:24567
```

WASD + mouse look. **E** pick up paper or sit. **Esc** stands up from the laptop (does not quit). One seater.

## Issuance vs OTP King (do not mint two Kings)

`node-up` already onboards **King** in the sidecar vault (`CONCRETE_VAULT_DIR`) and mints the bootstrap cap. The 3D story still starts unkeyed: walking bodies must not mutate until they **pick up** an issuance document.

**Gate:** Godot-side. First paper in a blank session **binds that body to the existing OTP King** (`GET /v1/bootstrap`) — it does **not** `POST /v1/principals` as another King. Later papers onboard other display names (colour). Unkeyed console mutates send `principal_id=unkeyed` so OTP **403**s. Seeds are not stored in `.tscn`.

## Headless peer playbook (option C)

The user is a **second Godot process**, not curl:

```bash
./scripts/godot-up.sh                 # host already listening
./scripts/godot-playbook.sh           # join, pick up paper, sit, create plaque, one JSON line, exit
```

Playbook file: `godot/playbooks/first-login.json`. Assumes nobody has claimed the first paper yet (otherwise this body is not King and create is 403). Curl `POST /v1/info_objects` is oracle/infra, not this actor. `--debug-puppet` / same-process extra pawns are **not** implemented as the user path.

Stdout ends with one JSON object, e.g. `{ "ok": true, "principal_id": "mldsa87:…", "did": "did:iota:…", "seated": true }`. Non-zero process exit on failure.

## 2D console only (debug)

```bash
godot --path godot -- --console-only
# or open scenes/main.tscn in the editor
```

## What the nested console can do

Same HTTP dialect as before: health, bootstrap, directory **people** (data), create/advance plaque, Eve deny. In the 3D session, create/advance use **this seated body’s** principal after pickup, not “whoever OTP lists as King” unless this body collected the first paper.
