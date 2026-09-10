# ADR 0009: Godot scenario worlds — first-person veneer, node console, playbook bots

- Status: **accepted**
- Date: 2026-09-10
- Relates: [ADR 0004](0004-world-state-supervisor.md) (veneer vs ground truth; session vs durable; lab supervisor; god-view vs belief), [ADR 0001](0001-lab-toolchain.md) (Godot on host; headless allowed for CI), [ADR 0005](0005-bootstrap-capability.md) (bootstrap cap on first user), [ADR 0007](0007-iota-did-head-authority.md) (information heads), [ADR 0008](0008-user-crypto-identity.md) (person = index-0 ML-DSA-87 public key; sidecar custody)
- Working plan and staged build: [09-godot-scenario-worlds.md](../09-godot-scenario-worlds.md), [10-godot-stage1-build.md](../10-godot-stage1-build.md)

## Context

Phase 1 Godot is a **2D lab form** (`godot/scenes/main.tscn`): Refresh / Create / Advance / Eve-deny. It talks only to OTP HTTP at `http://127.0.0.1:4000`. It is **not** ground truth. Name → head for **information** is IOTA Identity ([ADR 0007](0007-iota-did-head-authority.md)). Principals are `mldsa87:…` ([ADR 0008](0008-user-crypto-identity.md)). Curl smokes (`scripts/beat*-smoke.sh`) currently **bypass** Godot and therefore do not prove “a person in the world did this.”

Owner direction (2026-09-10): eventually **all human and scripted-person interactions happen through Godot as the real-world veneer**. Fill scenarios **chronologically in first person**. Support **savable worlds** (blank vs full IOTA/IPFS snapshot). Start with **one room and one computer**. Later multiplayer. **Outer lobby** = pick/load/save a scenario; **inner lobby** = already inside, spawn another body. Stock **ragdoll/capsule** avatars, recoloured. Walk up to a **laptop** (the working **node**), open a **node console**, and let the player’s mouse/keyboard act as that node’s. Scripted playbooks are **headless Godot peers in the same session** (option C), not curl-as-King.

Q1–Q8 were asked and answered the same day. This ADR locks them.

## Decision

### Authority (do not invert)

1. **Godot is the only user-facing actuator.** Humans and playbook bots act by being bodies in a Godot session. Durable mutates still go **that body’s console → OTP HTTP**. OTP (+ IPFS + IOTA Identity) remains **ground truth** for DID heads, caps, and principals. Godot must not invent commit heads, mint bootstrap caps, or replace Identity.
2. **Lab supervisor** may seed a scenario and (later) publish god-view. It must **not** skip capability checks or hold the bootstrap cap ([ADR 0005](0005-bootstrap-capability.md)).
3. **Scenario worlds** are **labelled lab harness**: restore a demo starting condition. They are not a second ledger.

### Saves

4. **Two save kinds, both required:**
   - **Blank world** — room/layout plus empty or factory OTP. No IOTA/IPFS history. “New game” / empty CoT.
   - **Full snapshot** — Godot world **and** lab IOTA + IPFS volumes **and** OTP `lab/data/node/` (and vault files needed for bound personas). Continue a run; replay a beat with chain state.
5. A save includes **all personas** then in the world: body id, colour, transform, inventory, whether they have collected an issuance document, OTP principal id if bound.
6. Loading a full snapshot **restores backend state**. The load path is harness (Compose volumes + data dir), not “Godot wrote the chain.”

### Lobbies and first scene

7. **Outer lobby** = pick / load / save a scenario (level select). **Inner lobby** = already in that world; spawn or possess another body. Neither is CoT membership nor an on-ledger cap.
8. **First deliverable space:** one room, one desk, one laptop = **node-1** at OTP `:4000`. Coloured capsule/ragdoll. Approach → interact → **node console** (today’s 2D veneer in a SubViewport / equivalent). While seated, host mouse and keyboard are the **node’s** input; the console pixels are the node’s display. **Esc** stands up and returns input to the body. This is **not** a real OS or hardware KVM.

### Avatars, keys, issuance

9. **Anyone** may spawn and control new avatars (inner lobby or in-world). Spawn does **not** call OTP onboard and does **not** publish a directory record.
10. Until an avatar **collects an in-world issuance document** (inventoried), they may walk around but **must not** mutate as a principal (OTP stays fail-closed: no `mldsa87:` / capability check fails). Collecting the document binds that body to the index-0 ML-DSA-87 public key (sidecar onboard). Directory publish on IPFS remains a **cap-gated data** write ([ADR 0008](0008-user-crypto-identity.md) stage 3), typically after the first user exists.
11. The **issuance document** is the chronological stand-in for **external** issuance (bank/dongle/paper). **Custody** remains `CONCRETE_VAULT_DIR` / sidecar; Godot is not the product vault. Default depiction: **public key visible on the paper**; private/seed material stays in the sidecar. Printing private bytes on the 3D prop is a lab exception, not the product rule (“users never see raw keys”).
12. **Anyone** may introduce new avatars — not King-only, not supervisor-only.

### Playbooks (option C)

13. The **honest playbook actor is a networked Godot peer from the outset** (option C): a **second process**, typically `godot --headless`, joins the host session, **is** an avatar, **collects the issuance document like a human** (no skip-to-keyed), walks, sits, injects console events. Each peer still calls OTP HTTP. Session poses are ephemeral ([ADR 0004](0004-world-state-supervisor.md)).
14. Lay **listen-server / multiplayer foundations in the first 3D stages**. Do not ship a single-player-only architecture and retrofit. Same-process intent scripts (**A**) and second-pawn-in-one-process (**B**) are **debug helpers only**, not the user path, not a reason to demote curl smokes.
15. **Laptop contention:** one seated console user at a time. A second body (human or bot) may wait or be denied the seat. That is a world rule, not an OTP rule.

### World vs belief

16. **Godot presents the world** (lab god-view / scenario layout). **Working nodes and the wider system hold belief** (OTP, later other system state) that **may differ** from that world. Overlaying belief on the Godot view is **useful later** and is **deferred** — no dual markers in the first room. Do **not** encode the laptop’s `Transform3D` as OTP belief. Furniture is presentation-only. Security use of mismatch stays later ([ADR 0004](0004-world-state-supervisor.md) §11).

### How we fill content

17. After a walkable room exists, fill with **chronological first-person beats**: state X, presented Y, action Z, state Z′, plus a fail path. These do **not** unfreeze [04-vertical-slice.md](../04-vertical-slice.md).

### Do not couple

18. Phoenix UI; supervisor-as-King; RINA; 0008 stage 5 (signed HTTP) as a blocker for the room; seL4 vault as a blocker; ragdolls as identity evidence; presence math; hardware KVM; curl-as-King as the long-term actor.

## Out of this ADR

- Production 3D art, animation sets, IK polish, photoreal characters, combat
- Real nested hypervisor / hardware KVM
- Belief overlay UI, trilateration, α/β/ω (deferred / paper)
- On-ledger bootstrap cap; ControllerCap = King (still named gaps from 0007/0008)

## Consequences

- Phase 2 next implementation emphasis is **Godot worlds** with a **session host from stage 1**, so a second process can join. Stages: [09](../09-godot-scenario-worlds.md). First coding brief: [10](../10-godot-stage1-build.md).
- Current 2D `main.tscn` becomes **node console** content, not the whole product UI.
- `beat*-smoke.sh` mutate-via-curl demotes to **oracle/infra** only after a **headless peer** can sit at the laptop.
- Full snapshots copy lab volumes; they must be documented as harness in any UI copy.
- Inventory exists because the issuance document must be carryable; it is not a general RPG loot system.
