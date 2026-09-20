# Build brief — Helen / Alice CoT (implementation)

This is the **coding prompt** for a new session. Storyboard is accepted: [11-helen-alice-cot-beats.md](11-helen-alice-cot-beats.md). Architecture already accepted: [ADR 0004](decisions/0004-world-state-supervisor.md)–[0009](decisions/0009-godot-scenario-worlds.md). **Do not reopen** payments, real RINA, real seL4, 0008-5 signed HTTP, belief overlay, second OTP node, Phoenix, curl-as-user, lobbies-as-CoT.

Phase 1 vertical slice stays **frozen**. Follow **11** if 0008/0009 text conflicts (paper tray keying, King-at-node-up, Wendy-links info-only).

## Repo facts

- Path: `sep_26_concrete`. Godot **4.5**, main scene `godot/scenes/world.tscn`, console `godot/scenes/main.tscn` in SubViewport. Listen **:24567**. OTP `./scripts/node-up.sh` → `http://127.0.0.1:4000`. Lab: `./scripts/lab-up.sh`.
- Godot talks **only** to OTP HTTP. No seeds in `.tscn`.
- Today: `Bootstrap.fresh_bootstrap!` onboards **King** at start; `authorize/2` is binary `bootstrap_holders`; `POST /v1/principals` is **uncapped**; info objects have **no** links facet or per-object read/write lists. `CONCRETE_VAULT_DIR` sidecar is leftover harness.

## Goal

Implement the **Helen → Alice** play in [11](11-helen-alice-cot-beats.md) as far as one coherent slice allows, in the **implementation order** in that doc (empty CoT → vaults → G/D1–D5 → caps vs GraphEdit → login → launcher/discovery/W2). Prefer a **clumsy but honest** path over a polished menu.

**Done when a human can:** power/sit; run **W0** as Helen (no pre-existing King); Exit; Alice login (PIN + paper private key → **her** vault); see discovery (D5/G, data markers); run **W2** and see a new info node. `mix test` still passes. `godot/README.md` updated.

## Must implement (from 11)

- **No auto-King** on node-up. Genesis **W0** is the one-shot mint; further writes cap-checked as Helen. Replay genesis **fails** unless **zeroise**.
- **EK → D2** at genesis (this node admits itself). Do not auto-write some other CoT’s D2.
- **Capability records** in OTP (holder, verb/resource, α/β/ω stub, workspace CID). GraphEdit **cannot** widen authority. Locked graphs denied **server-side**.
- **Workspaces** as **data** (full 2D layout JSON/CID) + **title info** Wendy-linked. Godot GraphEdit **rebuilds** from that payload.
- **W0, W1, W2** as specified in 11. W1 creates D5[Alice] and links root to G; PIN generated; Alice pubkey not privkey. W2: text, D3 picker, Wendy-link, auto-link author D5; store-on = this node.
- **Wendy-links** between **any** info or data DIDs; data mutate = **same DID, new CID**.
- **G** + **D1–D5**. D4 = pubkey↔PIN on IPFS, **tight read cap** (Helen/bootstrap). Discovery: data = **markers only**.
- **Vaults:** Elixir `GenServer` under node dynamic supervisor, **per user**, volatile. Comments: `lab stand-in — rewrite as seL4 later.` **No NIFs.** First Alice login starts **Alice’s** vault and imports paper private key. **Use-vault** only that principal. Exit session drops **that** user’s use (not Helen’s key left loaded for Alice).
- **Esc** = unsit, session remains. **Exit session** = logout. **Power off** ⇒ OTP **refuses** (and/or subtree stops).
- **Identity process:** username+PIN; stub αβω that **pass** Alice’s caps. Document: **not** signed sessions.
- **Discovery:** force-directed graph from OTP walk starting **D5[user]**; info filtered by read list; Godot does not scrape IPFS.
- **3D tray:** set dressing only; do not keep paper-pickup-as-King.
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
- Unkeyed / wrong PIN / locked graph / unread info omitted.
- If Godot missing, say so; do not fake a pass.
- Headless playbook: optional if W0–W2 are console-drivable; still option C, not curl mutate as the user.

## Art / UX bar

CSG room already exists. GraphEdit can be ugly. Force graph can be ugly. Prefer **obvious Elixir** over clever.

When in doubt: **OTP is authority**; Godot draws workspaces and the room.
