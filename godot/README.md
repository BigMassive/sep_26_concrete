# Godot lab veneer

Thin **physical-world UI** for `sep_26_concrete` ([ADR 0001](../docs/decisions/0001-lab-toolchain.md) / [0004](../docs/decisions/0004-world-state-supervisor.md) / [0009](../docs/decisions/0009-godot-scenario-worlds.md)). **Not** ground truth — talks only to OTP HTTP at `http://127.0.0.1:4000`.

**Main scene:** `scenes/world.tscn` — one 3D room, desk, laptop (`node-1`), **identity desk** (sign: Collect identities here), listen-server session. Nested console `scenes/main.tscn` is the node-1 screen (also `--console-only`). Each generated **persona is a separate coloured dummy** (capsule torso, sphere head, hinged cylinder limbs) in the room; first-person hides that body's head. Switching control does not retarget the OTP console (that stays with whoever is seated). HUD says **at node-1** only for the seated body.

Helen → Alice CoT: [docs/11](../docs/11-helen-alice-cot-beats.md), coded per [docs/12](../docs/12-helen-alice-build.md). Sessions are **not** signed HTTP (ADR 0008 stage 5 later); OTP still trusts `principal_id`.

## Prerequisites

```bash
./scripts/lab-up.sh      # IPFS + IOTA (needed for did:iota directory / plaques)
./scripts/node-up.sh     # OTP :4000 — empty CoT, no auto-King
```

Requires **Godot 4.5** on the host (`GODOT_BIN` overrides path). Use a **blank** `lab/data/node/` (or zeroise) for the first play.

## Session (listen-server from the start)

Windowed `godot-up` is the **host** (ENet port **24567**). A second process **joins** and appears as another coloured capsule. Host simulates the room; each process still calls OTP HTTP.

```bash
./scripts/godot-up.sh                          # host, windowed
./scripts/godot-join.sh                        # second body (windowed)
# or: godot --path godot --headless -- --join 127.0.0.1:24567
```

WASD + mouse look. Start on the **Personas** landing (type Helen / Alice / any name, Generate, then enter). Each name **spawns a body** (capsule dummy, distinct colour). HUD switcher changes who you walk; Helen stays at the laptop if she was seated. **E** picks up paper or sits. **G** gives a nearby avatar the giver’s **public-key slip** (not whichever paper was picked up last). **Esc** stands up only if **you** are the seater (OTP **session remains** until **Exit session**). One seater.

## Helen → Alice play (scenes 1–7)

1. Power/sit. Empty-CoT console opens on **Overview** (not linked; wait to connect later, or start genesis). Colour key is on that tab.
2. Open **W0 - Genesis**. **Populate** copies username / public / private from the persona or inventory (fields stay empty until you press it). Type a **5-digit numeric PIN**. One **Genesis** block pass-throughs those fields into D1–D5 / Vault and **Go / Commit** writes them (button and data blocks show a working cue). Replay fails unless **Zeroise**.

Live HTTP check (no Godot): `./scripts/w0-smoke.sh` (W0) and `./scripts/beat-smoke.sh` (scenes 1–7 through Alice W2). Lab-up + node-up. IOTA down is the 502 PTB.
3. Launcher: Helen stays seated. Switch to **Alice** (new body near the identity desk). Pick up her **public-key copy**, walk to Helen, **G** to put it in Helen’s inventory. Switch back to Helen → **W1** → **Populate** (Alice’s name and public key — never Helen’s). Generated PIN is shown once — tell Alice. Helen can run W1 because she holds **any**; Alice cannot (no covering cap). GraphEdit still cannot mint verbs (save layout is denied server-side).
4. **Exit session** (not only Esc).
5. **Login** as Alice: username + PIN + paper **private** key. Starts Alice’s vault. Wrong PIN / not on D1 / no key fail closed.
6. **Discovery**: force graph from D5[Alice]; info she may read; data markers only (no D4 bytes).
7. Run **W2**: text, username picker for read/write, Wendy-link DID (e.g. G). Auto-links her D5. Discovery shows the new info node.

**Power off** on the console makes OTP product routes **503**. **Zeroise** re-opens King-making (full chain/D2 wipe is stubbed).

Vaults are Elixir processes (comment: lab stand-in — rewrite as seL4 later). No NIFs. Paper/genesis fields may show keys; Godot does not keep seeds in `.tscn`.

## Headless peer playbook (option C)

Phase 1 `first-login.json` (paper-as-King + plaque) is leftover. Pickup no longer keys anyone; `create_plaque` / `eve_deny` fail-fast (`superseded_step`). This beat is console-driven W0–W2; a Helen→Alice playbook is later. Until then `./scripts/godot-playbook.sh` is a **known red path**. Curl mutate is still not the user.

```bash
./scripts/godot-up.sh
./scripts/godot-playbook.sh
```

## 2D console only (debug)

```bash
godot --path godot -- --console-only
# or open scenes/main.tscn in the editor
```
