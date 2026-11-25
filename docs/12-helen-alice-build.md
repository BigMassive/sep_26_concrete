# Build brief — Helen / Alice CoT (implementation)

Storyboard is accepted: [11-helen-alice-cot-beats.md](11-helen-alice-cot-beats.md). Architecture already accepted: [ADR 0004](decisions/0004-world-state-supervisor.md)–[0009](decisions/0009-godot-scenario-worlds.md). **Do not reopen** payments, real RINA, real seL4, 0008-5 signed HTTP, belief overlay, second OTP node, Phoenix, curl-as-user, lobbies-as-CoT.

**Status.** The play is in OTP and the veneer. `./scripts/godot-scenario.sh helen-alice` runs genesis through Alice login. Discovery and W2 are on the console; `./scripts/beat-smoke.sh` covers scenes 1–7 over HTTP. `./scripts/godot-playbook.sh` is still a known red path. The bullets below are the contract that code is held to.

Phase 1 vertical slice stays **frozen**. Follow **11** if 0008/0009 text conflicts (paper tray keying, King-at-node-up, Wendy-links info-only).

## Repo facts

- Path: `sep_26_concrete`. Godot **4.7**, main scene `godot/scenes/world.tscn`, console `godot/scenes/main.tscn` in a texture rendered at the panel size times the display scale (font 16, graph zoom 1, one-pixel wires, block positions at 1.5×). Listen **:24567**. OTP `./scripts/node-up.sh` → `http://127.0.0.1:4000`. Lab: `./scripts/lab-up.sh`.
- Godot AI (`godot/addons/godot_ai`, MIT) connects Cursor to the **open editor**. Use it to see and drive the running game. Details: [godot/README.md](../godot/README.md).
- Godot talks **only** to OTP HTTP. No seeds in `.tscn`.
- Node-up does not mint King. W0 is the one-shot mint; replay fails unless zeroise. `authorize/2` checks capability records (**any** covers every verb). `POST /v1/principals` is `introduce_user` and returns `403` `capability_denied` without a covering cap. Information objects carry links and read/write lists. The session vault is an Elixir `GenServer`. `CONCRETE_VAULT_DIR` remains the lab sidecar that holds the FIPS 202 seed and exports the ML-DSA-87 public key. It is not the product vault.

## Goal

The **Helen → Alice** play in [11](11-helen-alice-cot-beats.md), in that doc’s implementation order (empty CoT → vaults → G/D1–D5 → caps vs GraphEdit → login → launcher/discovery/W2). A clumsy honest path is enough.

**Done when a human can:** power/sit; run **W0** as Helen (no pre-existing King); Exit; Alice login (PIN + paper private key → **her** vault); see discovery (D5/G, data markers); run **W2** and see a new info node. `mix test` still passes. `godot/README.md` updated. The host scenario currently stops at Alice login. Discovery and W2 are exercised by `./scripts/beat-smoke.sh` and by the console, not by that scenario.

## Must implement (from 11)

- **No auto-King** on node-up. Genesis **W0** is the one-shot mint; further writes cap-checked as Helen. Replay genesis **fails** unless **zeroise**.
- **EK → D2** at genesis (this node admits itself). Do not auto-write some other CoT’s D2.
- **Capability records** in OTP (holder, verb/resource, α/β/ω stub, workspace CID). **Run** and mutates are **cap-checked**. Helen’s King **any** cap (bootstrap/do-anything) covers W1; Alice is denied W1 for lack of a covering cap. GraphEdit **cannot** widen authority (save-layout cannot mint verbs).
- **Workspaces** as **data** (full 2D layout JSON/CID) + **title info** Wendy-linked. Godot GraphEdit **rebuilds** from that payload.
- **W0, W1, W2** as specified in 11. W1 creates D5[Alice] and links root to G; PIN generated; Alice pubkey not privkey. W2: text, D3 picker, Wendy-link, auto-link author D5; store-on = this node.
- **Wendy-links** between **any** info or data DIDs; data mutate = **same DID, new CID**.
- **G** + **D1–D5**. D4 = pubkey↔PIN on IPFS, **tight read cap** (Helen/bootstrap). Discovery: data = **markers only**.
- **Vaults:** Elixir `GenServer` under node dynamic supervisor, **per user**, volatile. Comments: `lab stand-in — rewrite as seL4 later.` **No NIFs.** First Alice login starts **Alice’s** vault and imports paper private key. **Use-vault** only that principal. Exit session drops **that** user’s use (not Helen’s key left loaded for Alice).
- **Esc** = unsit, session remains. **Exit to menu** = leave the open workspace or Discovery for the console menu (Overview before genesis, Home / launcher after login); session stays logged in. **Exit session** = logout. **Power off** ⇒ OTP **refuses** (and/or subtree stops).
- **Identity process:** username+PIN; stub αβω that **pass** Alice’s caps. Document: **not** signed sessions.
- **Discovery:** force-directed graph from OTP walk starting **D5[user]**; info filtered by read list; Godot does not scrape IPFS.
- **3D tray / identity desk:** set dressing for paper; sign **Collect identities here**. Pickup does not onboard King. Each persona is a **separate coloured dummy** (capsule/sphere/cylinder, KidsCanCode-style; first-person hides the head). **G** prefers the giver’s **public-key slip**. Console is only the **seated** body. HUD **at node-1** follows the seater. W1 **Populate** copies the admittee (Alice / new user), never the seater.
- Gate **`POST /v1/principals`** (and equivalent) so only W1/bootstrap can add users.

## Explicitly do not

- NIFs / fake seL4 kernel.
- SRK disk activity list (mention in comments if you touch supervisor).
- CIK required at boot.
- Payments, money on launcher.
- Second OTP, real RINA, efficient search.
- PIN salted-verifier migration (owner accepted D4 plaintext + ACL).
- ControllerCap = Helen (named gap: lab wallet).
- Full zeroise/D2 chain cleanup (button may exist; genesis re-entry only via zeroise **flag** is enough if chain wipe is stubbed).

## Tests / verification

- `mix test` green.
- Manual: empty data dir; W0 once; second W0 fails; Helen W1 Alice; Exit; Alice login; discovery; W2 link visible.
- Unkeyed / wrong PIN / no covering cap / unread info omitted.
- If Godot missing, say so; do not fake a pass.
- Host scenario for the Helen → Alice console beat: `./scripts/session-up.sh` then `./scripts/godot-scenario.sh helen-alice` (`godot/scenarios/helen-alice.json`). It presses the console in one process. The joining playbook (`./scripts/godot-playbook.sh`) stays option C and is still the known red path. Curl mutate is still not the user.

## Art / UX bar

CSG room already exists. Avatars are a tutorial-style capsule dummy (not box limbs). GraphEdit can be ugly. Force graph can be ugly. Prefer **obvious Elixir** over clever.

When in doubt: **OTP is authority**; Godot draws workspaces and the room.
