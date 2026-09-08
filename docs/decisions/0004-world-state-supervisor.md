# ADR 0004: World state, lab supervisor, Godot veneer

- Status: accepted
- Date: 2026-09-08

## Context

UI is **Godot** ([ADR 0001](0001-lab-toolchain.md)); runtime is **Elixir/OTP** ([ADR 0003](0003-runtime-beam.md)). Godot should represent a thin **physical-world** view (possibly later a 3D multiplayer space where users move among working nodes). That raises where “state of the world” lives, and how a **lab supervisor** relates to product topology.

Principles already in force: backend is **ground truth**; UI is veneer; a privileged supervisor must not be mistaken for product mesh architecture ([01-residues.md](../01-residues.md), [03-architecture.md](../03-architecture.md)).

There is also a semantic split between **where a node actually is** and **where it thinks it is** — important for later identity/presence work, and easy to collapse wrongly into a single Godot transform.

## Decision

### Runtime / UI shape

1. **No Phoenix** (or other BEAM web UI). All user-facing UI goes through **Godot**. OTP exposes an API (HTTP or similar) that Godot calls.
2. **Godot** is a thin **physical-world veneer**: environments, node placements as drawn, user avatars, multiplayer presentation. It may sync session visuals among clients. It is **not** authoritative for durable node/info/capability state.

### Layers of world-related state

3. **Working node state** (DID heads, commits, capabilities, node liveness as a working entity) lives in **OTP nodes** (+ stock IPFS/IOTA per [ADR 0002](0002-ipfs-iota-did.md)) — **ground truth**.
4. **Durable world facts** that the foundation cares about (e.g. which nodes exist in the CoT; modelled placement if required later) also live on the **OTP / naming+content path**, not only as Godot scene nodes.
5. **Session / presentation state** (avatar pose, camera, who joined this Godot session, interpolation) may live in **Godot** (and optionally a tiny multiplayer relay). Treat as **ephemeral**; re-derive durable facts by refreshing from OTP.

### Lab supervisor (labelled harness)

6. A **lab supervisor** (e.g. privileged Compose/OTP process) **is allowed** for demos. It is **lab harness**, not product architecture.
7. Supervisor responsibilities: bring up / coordinate lab processes; **seed** durable world/node facts into OTP; optionally publish connection endpoints to Godot clients.
8. Supervisor must **not** be the live authority for capability checks or commit advances, and must **not** replace OTP as the store for working nodes.

### God-view vs node belief (position)

9. Keep two distinct notions of position (even if the first slice only stubs them):
   - **God-view (objective) position** — where the node *actually* is in the modelled/physical world. In the lab, the **supervisor** (or another labelled authoritative observer) may hold and publish this. Nodes do not solely author it by self-report.
   - **Node belief** — where the node *thinks* it is (local estimate from clocks, peers, sensors later). Owned by the **node** (OTP), with room later for confidence (α/β/ω).
10. **Godot** may render **both** (e.g. true marker vs believed marker) so the distinction is visible. Rendering is not authority for either.
11. Security-relevant use of mismatch (belief vs god-view) is **later**; do not require trilateration or presence math for the first vertical slice. When space is introduced, use **two fields**, even if belief is initially seeded equal to god-view.

## Consequences

- Open decision “lab supervisor” → **yes, labelled harness**; seed and god-view publish, not product centre.
- Open decision “exact BEAM app shape” → **OTP without Phoenix** for UI; further OTP layout detail when coding starts is fine.
- Vertical slice / scenarios should treat users-in-space and multiplayer as **UI**, with nodes as **working OTP entities**.
- Vocabulary gains god-view vs belief; programme-map presence work can attach later without rewriting this split.
- Residues against “supervisor as product mesh” remain: harness labelling is mandatory in demos and docs.
