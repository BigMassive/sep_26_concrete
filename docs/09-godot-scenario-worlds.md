# Godot scenario worlds (working plan)

Status: **accepted** with [ADR 0009](decisions/0009-godot-scenario-worlds.md) (2026-09-10). Does **not** unfreeze [04-vertical-slice.md](04-vertical-slice.md). First coding brief: [10-godot-stage1-build.md](10-godot-stage1-build.md).

## Why this exists

The programme story is that people live in a **physical world** and use **nodes** (computers) that sit in that world. Phase 1 proved OTP, Identity, caps, and a 2D form. That form is honest about ground truth but is **not** the long-term user surface.

This plan is how we grow Godot into that surface **without** making Godot the ledger.

## Authority map (read this before coding)

| Layer | What it is | Must not |
|-------|------------|----------|
| **Godot world** | Rooms, furniture, bodies, laptop **prop**, session poses, inventory **tokens** | Author DID heads, mint bootstrap caps, store master seeds as product vault |
| **Node console** | Nested UI on the laptop; mouse/keyboard passthrough; still HTTP to OTP | Talk to IPFS/IOTA except via OTP |
| **OTP (`:4000`)** | Executor: cap check, principals, directory index, info-object API | Be driven by a supervisor pretending to be King |
| **IPFS / IOTA Identity** | Content bytes; **information** name → head | Be updated by Godot except through OTP |
| **Sidecar / `CONCRETE_VAULT_DIR`** | Lab custody of FIPS 202 seed + ML-DSA-87 | Live inside Godot scene files |
| **Scenario save (harness)** | Blank world **or** full snapshot of Godot + lab volumes | Be mistaken for on-chain truth |
| **Lab supervisor** | Seed, later god-view publish | Skip cap checks; hold bootstrap cap |

**World vs belief (overlay deferred).** Godot shows the **world**. OTP (and later other system components) hold **belief** that may **differ**. Do not draw two pins in stage 1–4. Do not put `Laptop.global_position` into `bootstrap.json` as “where the node is.” When overlay lands, only **working nodes** get a belief field; chairs and issuer tables stay presentation.

## What is already in the repo (do not throw away)

- `godot/` — Godot **4.5**, main scene `res://scenes/main.tscn`, script `godot/scripts/main.gd`. 2D Control UI: health, bootstrap, directory people, plaque create/advance, Eve deny. `HTTPRequest` sequential; principal ids are huge `mldsa87:…` strings (truncate for labels).
- `scripts/godot-up.sh` — host Godot binary, `--path godot`.
- `runtime/` — Bandit API, Bootstrap, InfoObjects, UserDirectory, UserIdentity sidecar.
- `scripts/node-up.sh` — OTP `:4000`, vault dir, `lab/.venv` for dilithium-py.
- `scripts/beat1-smoke.sh`, `beat2-smoke.sh` — **curl actors**. Keep as **oracle** until a headless **peer** can do the same mutate through the console.
- Identity package + lab IPFS/IOTA via `scripts/lab-up.sh` — required for `did:iota` directory/info objects; blank-world first login can still onboard King if Identity is down **only** if OTP’s unconfigured path is acceptable for that scenario (info objects then lab DID). Prefer lab-up for anything that publishes directory data.

## Settled owner answers (verbose)

### Lobbies

**Outer** is level select: pick a **blank** scenario or **load** a named save; **save** the current run. It is not “pick a CoT” and not login to CONCRETE.

**Inner** is already standing in that room: spawn another coloured body, or let a joining peer become a body. You can have several unkeyed bodies walking around.

### Saves

**Blank world** = mesh + lighting + item placement + empty/factory OTP (and empty vault except what factory needs). Use for “first person who ever existed.”

**Full snapshot** = blank-world payload **plus** Docker/lab IPFS repo, IOTA localnet state, `lab/data/node/` (bootstrap, info index, directory index, iota_heads), and vault files for every persona who had collected a document. Loading it must bring chain heads back; Godot then **refreshes** from OTP rather than trusting saved plaque text.

**Personas in a save:** for each body — net peer id if any, colour, transform, animation/seated flag, inventory list (including issuance document instance id), bound `mldsa87:…` or null, display name if any.

Who may save: treat as a **harness/pause menu** action from the outer lobby (and optionally Esc-menu in-world). Label the UI “lab save,” not “commit to the ledger.”

### First login (chronology)

The **issuer** is a physical presence in the room (table, tray, NPC later — a static tray is enough for v0). It **gives** a **document** the body can pick up. The document goes into **inventory**. That act is the story of “I was issued keys outside the node.”

Until pick-up: the body is a **camera with legs**. Sitting at the laptop might show a lock screen / “no principal” / refuse mutate. They must not succeed at `POST /v1/info_objects`.

On pick-up: OTP sidecar `onboard` for a username (lab: colour name or “King” for the first document in a blank world). Vault file appears under `CONCRETE_VAULT_DIR`. The body’s session state stores `principal_id`. Console HTTP uses that id.

**First document in a blank world** is how **King** comes to exist (bootstrap cap minted on first OTP principal — already OTP behaviour). Later documents are other people (Eve, etc.) **without** that cap unless delegated (delegation is out of scope).

Default paper: show truncated **public** key. Do not dump `master_seed_hex` into a `.tscn`.

### Avatars vs principals

Spawn is free and **anyone** can do it (inner lobby, or a peer joining). No King permission. No supervisor permission. Spawn ≠ `POST /v1/principals`.

Keyed vs unkeyed is **inventory of the issuance document**, not “did Godot draw a nametag.”

### Console

Interact on the laptop (E / proximity). Mouse captured to the SubViewport. Keyboard goes to LineEdits in the nested UI. **Esc** unsits, releases capture, body walks again. One seater. First laptop always `node-1` `:4000` until a second node exists.

Reuse `main.gd` logic as the console (move under `godot/console/` or instance the existing scene in a SubViewport). Do not fork a second HTTP dialect.

### Bots (C)

Honest playbook = **second Godot process**. Typical: human or CI starts **host** (windowed or headless); Cursor starts `godot --headless -- --join 127.0.0.1:<port> --playbook <file>`.

The peer:

- Appears as a recoloured body (or takes a spawned body).
- Picks up **its own** issuance document if the beat requires a principal (same as a human). **No skip-to-keyed.**
- Navigates (navmesh or simple steering) to the laptop.
- Sits if free; if King is seated, the beat must say wait or fail (contention).
- Injects UI events into the console (not curl).
- Prints one JSON result to stdout and `quit` with a process code.

**A** (JSON calling functions on the host tree) and **B** (second pawn, same process) may exist as `--debug-puppet` for developers. They must not be what we call a playbook in CI docs.

Headless has no OS mouse: “inject events” means calling the same `interact` / `gui_input` paths the seated human uses.

### Belief overlay

Not in stages 1–8. Keep a comment in code: world transform ≠ belief. OTP may later grow a belief record; Godot may later draw it.

## Development stages (implementation order)

| Stage | Deliverable | Done when |
|-------|-------------|-----------|
| **0** | This ADR/plan | done |
| **1** | 3D room, desk, laptop prop, one body, **ENet (or Godot MP) listen-server**, second process can join and see two bodies | `godot-up` walks; second `godot --headless` joins and a capsule appears |
| **2** | Proximity interact, SubViewport console = current 2D UI, Esc unsits, mouse capture | Human can refresh OTP from the laptop |
| **3** | Issuer tray + document pickup + inventory + unkeyed mutate denied | Blank world, no paper ⇒ create plaque fails; with paper ⇒ King onboard works |
| **4** | Headless peer playbook: join, pick up (if required), sit, one mutate or Eve-deny, JSON out | A scripted peer completes a beat without curl POST for the mutate |
| **5** | Blank + full snapshot save/load including all personas | Round-trip a King-bound body after lab restart |
| **6** | Outer lobby UI | Pick blank vs named save |
| **7** | Inner lobby: spawn body without leaving the room | Second colour walks; still unkeyed until paper |
| **8** | Second laptop / second OTP node | Separate promotion |
| **9** | Belief overlay | Deferred |

**Do not** wait for outer lobby before session join. **Do** get a walkable room before a pretty menu.

## Chronological beat template (for later content)

Use this whenever adding a story, in first person:

1. Scenario name and kind (blank vs snapshot)
2. Who I am (colour; human window vs headless peer; principal if any)
3. System state X (OTP files, Identity configured?, plaque exists?)
4. What I see Y (room, tray, laptop lid, other bodies)
5. What I do Z
6. State Z′ (inventory, OTP, console text, who is seated)
7. Fail path

**v0 story (stage 3–4):** *First login, blank world.* X = no King. Y = empty room, tray with one document, closed/idle laptop. Z = pick up document, sit, bootstrap/create as first user. Z′ = I am King; bootstrap cap on my pubkey; paper still in inventory.

Later: second peer Eve picks a second document, sits after King Escs, advance denied.

## Playbooks vs smokes

| | Actor | Allowed as “user did it”? |
|--|--------|---------------------------|
| `curl POST /v1/info_objects` | Infra | **No** (oracle/setup only, after stage 4) |
| Host-tree JSON puppet (A) | Debug | **No** |
| Headless **peer** (C) | User | **Yes** |
| GET `/v1/info_object` after a peer mutate | Oracle | Yes (check) |

## Non-goals

Phoenix; curl-as-user; A/B as CI actor; hardware KVM; photoreal meshes; combat; RINA; seL4; signed HTTP (0008-5); belief overlay; full BBAC; funding vouchers; Wendy-links; treating ragdoll colour as cryptographic identity.
