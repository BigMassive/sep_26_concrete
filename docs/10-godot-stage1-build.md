# Godot build brief — stages 1–4 (implementation)

This is the **coding prompt** for a new session. Architecture is already accepted: [ADR 0009](decisions/0009-godot-scenario-worlds.md), plan [09-godot-scenario-worlds.md](09-godot-scenario-worlds.md). Do **not** reopen lobbies, save kinds, bot=C, or deferred belief overlay unless the owner contradicts 0009.

Phase 1 vertical slice stays **frozen**. Do not “fix” Identity/OTP as part of this work except where the console must call existing `:4000` APIs.

## Repo facts

- Path: `sep_26_concrete`. Godot **4.5**, `godot/project.godot`, main scene `godot/scenes/main.tscn` (2D form).
- OTP: `./scripts/node-up.sh` → `http://127.0.0.1:4000`. Lab IPFS/IOTA: `./scripts/lab-up.sh`.
- Principals: `mldsa87:` + urlsafe b64. Sidecar: `scripts/user-identity.py`, vault `lab/data/vault/`.
- Godot must keep talking **only** to OTP HTTP (ADR 0004). No IPFS/IOTA from GDScript.
- Do not put master seeds in `.tscn` / `.gd`.

## Goal of this build-out

Deliver **stages 1–4** of [09](09-godot-scenario-worlds.md):

1. **3D room** (box room, floor, desk, laptop mesh or CSG stand-in), **one player body** (capsule or simple ragdoll, distinctive colour), **WASD/mouse look**, **listen-server session** so a **second Godot process can join** and appear as a second coloured body.
2. **Node console:** proximity + interact on the laptop; nest the **existing** 2D UI (or a moved copy of `main.gd`) in a SubViewport; mouse/keyboard drive that UI; **Esc** stands up.
3. **Issuance document:** a pick-up-able prop on a tray; **inventory** (minimal UI); collecting it onboard via OTP (`POST /v1/principals` with a display name, and/or bootstrap already creating King on node start — **think carefully**):
   - Today OTP **already creates King** on first `Bootstrap` start (sidecar onboard “King”). That fights “empty room then pick up paper then become King.”
   - **Preferred for chronology:** delay or gate “I am a principal” in **Godot** until paper is collected, even if OTP already has King from `node-up`. For a **true** blank CoT, you may need a node-up flag or empty data dir **and** Godot calling ensure-principal only after pickup. Document the choice in a short comment in the PR; do not silently have two Kings.
   - Unkeyed body: console may load but mutates must 403 or be blocked client-side **and** server-side (empty/wrong `principal_id`).
4. **Headless peer playbook:** `godot --headless` joins the host, is a body, picks up a document if the beat says so, sits if free, performs one console action (or Eve-deny), prints **one JSON object** to stdout, exits non-zero on failure.

Stages 5–9 (full snapshots, outer/inner lobby UI polish, second node, belief overlay) are **out of scope** for this brief unless they fall out of 1–4 with almost no extra design (e.g. a stub `MultiplayerSpawner`).

## Session / networking (C from the outset)

- Use Godot 4 High-level multiplayer (ENet) or equivalent **in-tree**, localhost first.
- **Host** (`godot-up.sh`) listens (document port, e.g. `24567`).
- **Peer:** `godot --path godot --headless -- --join 127.0.0.1:24567` (exact argv is yours; put it in `scripts/` and README).
- Authority: host simulates the room; peers send input intents (move, interact, sit). Do not give peers a back door to OTP as King.
- Each peer’s console HTTP still originates **from that Godot process** with **that body’s** `principal_id` after pickup.
- One laptop seat: host tracks `seated_peer_id`; second sit request fails until Esc.

## Art bar

CSG boxes, a capsule `CharacterBody3D`, a laptop-sized box, a paper-sized box, unlit or simple materials, **recolour** via `modulate` / albedo. No AssetLib requirement. No combat.

## Console implementation hints

- Instance `main.tscn` (or extract `Console.tscn`) inside `SubViewport`.
- While seated: `Input.mouse_mode = captured` onto the viewport; forward `InputEvent` to the nested tree; **Esc** handled by the **3D** controller first (unsit), not by quitting the game.
- Truncate `mldsa87:` in 3D nametags the same way `_short_principal` does.

## Playbook JSON (suggested)

Keep it boring, e.g. `{ "name": "first-login", "steps": [ "join", "pickup_nearest_document", "sit_laptop", "wait_console_ready", "create_plaque" ] }`. Stdout: `{ "ok": true, "principal_id": "mldsa87:…", "did": "did:iota:…", "seated": false }` (fields as applicable). Do not scrape the 3D viewport.

## Tests / verification

- `mix test` must still pass (OTP). Do not break Elixir.
- Manual: two terminals, host + headless join, two capsules.
- Manual: sit, see OTP health, Esc, walk.
- Manual: no paper, sit, create plaque fails; with paper, first user can create.
- Playbook: headless peer completes or fails closed without curl mutate.
- If Godot is missing on the agent machine, say so; do not fake a pass.

## Explicitly do not

- Phoenix; curl POST as the playbook actor; putting seeds in Godot; belief overlay gizmos; RINA; rewriting ADR 0007/0008; inner/outer lobby **menus** beyond a debug spawn if needed for two bodies; full IPFS volume snapshot (stage 5); signed HTTP.

## Definition of done (this brief)

- [ ] 3D main scene (or a new `world.tscn` as `run/main_scene`) with room, desk, laptop, walking body.
- [ ] Second process can join and is visible.
- [ ] Laptop console = existing OTP UI; Esc unsits.
- [ ] Issuance pickup gates principal use; sidecar/OTP still custody.
- [ ] Headless playbook script/docs for one chronological beat.
- [ ] `godot/README.md` updated; 2D-only path explained if kept as a debug scene.
- [ ] No secrets committed; `lab/data/` stays gitignored.

When in doubt, prefer a **visible clumsy 3D room that two processes can share** over a polished single-player menu.
