# Helen / Alice — CoT genesis and first workspaces

Status: **accepted storyboard** (2026-09-20). Not an ADR; it **promotes** paper items and **revises** how 0005/0008/0009 show up in Phase 2. Phase 1 vertical slice stays frozen. Coding brief: [12-helen-alice-build.md](12-helen-alice-build.md).

Do **not** reopen: lobbies as CoT membership, payments/vouchers, real RINA overlay, real seL4, 0008-5 signed HTTP, belief overlay, second OTP node, Phoenix, curl-as-user.

## Intent

One laptop (node-1). **Helen** (human name) is the first user; **King** is her **role** (bootstrap holder). She founds a Circle of Trust, then **Alice** is admitted, logs in, discovers names, and authors an information object with a Wendy-link.

Godot remains veneer; durable mutates are OTP HTTP → IPFS + IOTA Identity ([ADR 0004](decisions/0004-world-state-supervisor.md), [0007](decisions/0007-iota-did-head-authority.md)).

## Vocabulary locks

| Term | Meaning here |
|------|----------------|
| **King** | Bootstrap **role**, not a username. First holder is Helen ([ADR 0005](decisions/0005-bootstrap-capability.md)). |
| **G** | CoT **first-among-equals** **information** DID — the global starting point. |
| **D1** | Data: whitelist of **user** pubkeys (CoT membership of people). |
| **D2** | Data: whitelist of **node EK** pubkeys (boxes). |
| **D3** | Data: pubkey ↔ **username** (existing directory job, [ADR 0008](decisions/0008-user-crypto-identity.md)). |
| **D4** | Data: pubkey ↔ **PIN** (plaintext on IPFS for now; **tight read cap** — lab exception). |
| **D5** | Data: user pubkey ↔ DID of that user’s **discovery root**. |
| **EK** | Node endorsement key (hardware identity). Not the person’s ML-DSA key. |
| **Capability (authority)** | OTP record: holder pubkey, verb/resource, α/β/ω thresholds, optional pointer at a workspace CID. **Not** the GraphEdit picture. |
| **Workspace** | **Data** object: full GraphEdit layout (blocks, positions, wires, lock flags) so the scene can be rebuilt. **Title** is an **information** object Wendy-linked to that data. |
| **Vault** | Per-user, this-node process holding that user’s key material in **volatile** memory. Elixir `GenServer` (simple). Comment: **lab stand-in — rewrite as seL4 later.** No NIFs. |
| **Lab supervisor** | Harness god-view: `powered`, `boot_stage`, `zeroised`. Never holds bootstrap cap. |
| **Node supervisor** | BEAM dynamic supervisor of **tasks** on the working node (vaults, identity process, storage children). |
| **Use-vault** | Capability: only **that** principal may use **that** vault on this node. |
| **Wendy-link** | Bidirectional `{DID, optional CID}` between **any** information **or** data names (Mar_26 IINL pair). Empty CID = live head. Fail closed if either name cannot update. |

**Data vs information:** Data objects **do** have a stable DID and an updatable **CID** (and a **link set** for Wendy-links). They do **not** grow plaque commit-graph / content-read-write *information* facets. Updating data = new IPFS bytes + **same DID**, CID/head moved (ContentHead / IINL style).

**Keys:** Product rule remains in-system **use-not-see**. **Labelled exception:** paper/bank (and genesis/import fields) may show human-readable keys. Godot must not keep seeds in `.tscn`.

## Physical node (mock)

Laptop: **on/off**, **zeroise** (wired enough that only zeroise returns this box to genesis chooser; full CoT/D2 cleanup is **named**, not fully specified). Boot stages are lab-supervisor god-view.

**Power off:** console dark **and** OTP refuses (or the node supervision subtree stops) so curl is not a live node.

**Session layers**

| Action | Effect |
|--------|--------|
| **Esc** | Stand up. **Session still that user** if they had logged in. |
| **Exit session** | Logout: drop **that user’s** vault **use** / αβω. Other users’ vaults untouched. Processes may remain but cannot **use Helen’s key** while Alice sits. |
| **Power off** | Volatile vaults die. Paper to re-import. |
| **Zeroise** | Local wipe; **only** path that may re-open King-making. |

**CIK** at boot: not required this beat. **SRK-wrapped activity list** on disk: mention only, **do not build**.

Encrypted recovery of *tasks* later must never persist user private keys.

## Boot chooser

After power-on:

1. **Local:** has this box been set up? (any vault/principal on **this** node.)
2. **Network (later scene):** mock RINA — sign with **this EK**, is it on **D2**, resolve **G**. **This beat** is one node: implement **chooser copy + genesis**. Honest D2-reject needs a second EK/node later.

**EK on D2:** at **genesis**, node-1 **writes its own EK into D2** (“the node admits itself to itself”). A **later** box joining an **existing** CoT must **not** auto-write the remote G’s D2 — that remains wait / Helen updates D2.

**Genesis replay** after a successful G **fails**. Only **zeroise** returns the chooser to King-making.

## Capabilities and workspaces

OTP checks the **authority record**. GraphEdit is how a holder **runs** a workspace. Editing a locked graph must be **denied server-side**. Unlocking layout must **not** add verbs.

Most user caps in this beat **point at** a workspace CID. **Bootstrap** still authors/locks graphs and mints G.

**α / β / ω:** each cap has thresholds. The **identity process** (username + PIN) is a King-started child on suitable nodes. **Stub:** success produces numbers that **pass** Alice’s bundle. This is **not** ML-DSA session binding ([ADR 0008](decisions/0008-user-crypto-identity.md) stage 5 later). OTP still trusts `principal_id` until then — **say so in UI/docs**.

**Identity process ≠ genesis.** Genesis is the system workspace below.

## Genesis exception (chicken and egg)

The **King-making GraphEdit** is **part of the underlying system** (boot chooser, uninitialized node). No prior cap. **Revisit** later. After success, 0005 applies: first principal + bootstrap mint is **one-shot**; **further** writes (G, D1–D5, workspaces) are **cap-checked as Helen**.

Today `Bootstrap.fresh_bootstrap!` onboards King at `node-up` — that **must stop** for empty CoT (delay until genesis workspace succeeds). No two Kings.

## Workspaces in this beat

### W0 — King-making (system)

Entry: **username, public key, private key, PIN**. Sinks: D1–D5 (Helen’s root), **G** + Wendy-links from G to D1–D5, **this EK → D2**. **Vault** block: start Helen’s vault, load private material volatile. Then launcher.

### W1 — Introduce user (locked)

Helen only (bootstrap / this workspace cap). Name, **public** key, **generated 5-digit PIN** (show once — paper exception). Wires **D1, D3, D4** (not D2). Creates **D5[Alice]** and Wendy-links Alice’s root to **G**. Grants Alice’s bundle: home, write-info, use-vault (her vault, once it exists), discovery. Graph **immutable** for Alice.

### W2 — Write information + Wendy-links (locked enough to test)

Text body. Read/write = lists of pubkeys via **immutable username picker → D3**. Store-on = **this node** for now. Wendy-link to an existing info **or** data name. **Auto Wendy-link** the new object onto **the author’s D5 root**.

### Home / launcher

Post-login surface: list runnable workspaces, start processes, **discovery**, **Exit session**. “Home screen on any node” is a cap; this beat has one laptop.

**Issuance tray** in the 3D room is **set dressing** this beat. Real path is workspaces (keys typed/imported). 0009 paper-pickup-as-keying is **superseded** for this story (do not leave two ways to become King).

## Discovery

Force-directed graph. Edges = Wendy-links. Info vs data **icons**. Titles only. **Information:** only nodes this principal **may read**. **Data:** **markers** — existence, not bytes (especially D4). Naive OTP walk; start at **D5[user]** (and G if linked). Godot does not brute-force IPFS.

## First-person beat (single play)

**Scenario:** blank CoT, one node-1. Payments off.

### Scene 1 — Helen, genesis

**X:** Uninitialized OTP (no auto-King). Chooser offers King-making.  
**Y:** Power on, W0 GraphEdit.  
**Z:** Helen, keys, PIN; run graph.  
**Z′:** Helen vault; bootstrap; G; D1–D5; this EK on D2; launcher.  
**Fail:** replay genesis; Identity/IPFS fail ⇒ no half-CoT with a King and no G (retryable/atomic rule).

### Scene 2 — Alice’s paper (outside)

**X:** CoT exists; Alice ∉ D1.  
**Z:** Alice receives human-readable keys (bank/paper). PIN **not** yet — Helen will generate it.  
**Z′:** Alice cannot login.

### Scene 3 — Helen adds Alice (W1)

**Z:** Name, Alice pubkey, generated PIN; grants workspace caps.  
**Z′:** Alice on D1/D3/D4; D5[Alice] linked to G. Helen tells Alice the PIN.  
**Fail:** Alice cannot rewire W1; cannot write D2.

### Scene 4 — Helen Exit session

**Z′:** Helen’s vault **use** dropped. Seater free. Esc alone would have left Helen’s session live — she must **Exit**.

### Scene 5 — Alice login

**Y:** Identity process: username + PIN.  
**Z:** Success → **start Alice’s vault**, **import paper private key**. Stub αβω pass her caps. Home.  
**Fail:** wrong PIN; not on D1; no paper key ⇒ cannot sign/use (fail closed, not unsigned success).

### Scene 6 — Alice discovery

**Y:** Graph from D5[Alice] / G: info she may read, data markers.  
**Fail:** unread info omitted; D4 bytes not shown.

### Scene 7 — Alice authors

**Z:** W2: text; picker for read/write; Wendy-link to existing (e.g. G or a data marker); auto-link to her root.  
**Z′:** Discovery shows the new info node.  
**Fail:** no cap; locked graph; picker cannot edit D3; either-end update fails ⇒ no half-link.

## Named gaps (do not solve here)

- IOTA **ControllerCap** is still the **lab wallet**, not Helen ([ADR 0007](decisions/0007-iota-did-head-authority.md)).
- `POST /v1/principals` is uncapped today — must become cap-gated when coding W1.
- Signed HTTP / challenge (0008-5).
- Real seL4; NIF costume **rejected** — Elixir + comments only.
- Many vaults on many nodes.
- D4 PIN-on-IPFS residual (offline CID, 5 digits) — owner accepted with tight ACL.
- Honest D2 **reject** (second EK).
- Zeroise vs stale D2/G on chain (specify when coding zeroise for real).
- Payments, efficient search, second laptop.

## Implementation order (same story, several slices)

Code in this order; the play above is the demo once they exist:

1. Empty CoT / no auto-King; power refuse.  
2. Vault GenServer (Helen, then Alice); use-not-see; seL4 comments.  
3. G + D1–D5; EK→D2 at genesis; Wendy-links any DID; data = same DID new CID.  
4. Authority records ≠ graphs; W0/W1/W2 stored as data + title info.  
5. Identity process; stub αβω; Exit session.  
6. Launcher + discovery + W2 auto-link D5.

`mix test` must still pass. Headless playbook remains option C when the console can drive these workspaces.

## Revises (when coding, expect ADR follow-ups)

- **0005:** mint at genesis workspace, not process start; replay fail; zeroise exception.  
- **0008:** D3 stays directory job; data may have CID + Wendy-link set; D4 PIN lab exception; vault Elixir not `CONCRETE_VAULT_DIR` as product.  
- **0009:** paper tray not the keying path this beat; spawn body still ≠ onboard.  
- **0004:** god-view allowlist includes power/boot/zeroise.  
- Wendy-link vocab: not info-only.
