# Roadmap

## Phase 0 — Docs and plans

- [x] Create `sep_26_concrete` repo skeleton
- [x] Owner adds new concepts to [05-concept-backlog.md](05-concept-backlog.md) (+ [07-programme-map.md](07-programme-map.md))
- [x] Freeze [04-vertical-slice.md](04-vertical-slice.md) acceptance criteria
- [x] Resolve open decisions needed for the slice via ADRs (0001–0006); RINA overlay ADR still later
- [x] Phase 2 naming authority → **IOTA Identity as name → head**; OTP executor / cache ([ADR 0007](decisions/0007-iota-did-head-authority.md))
- [ ] Optional: short link/PR note on BigMassive/CONCRETE pointing at this prototype

## Phase 1 — Thin vertical slice

- [x] Implement only what the slice requires (beats 0–6)
- [x] Prefer typed integrations; no unused sidecars
- [x] Demo path documented; harness labelled

## Phase 2 — Iterate (current)

Promote backlog items deliberately (stub → slice).

1. **IOTA Identity publish (happy path)** — **done**: package on localnet + `Identity::new` / resolve + on-chain ContentHead ([docs/08](08-phase2-iota-identity.md)).
2. **Identity as sole name → head authority** — **done** ([ADR 0007](decisions/0007-iota-did-head-authority.md)). Lab assumption: Docker + IOTA localnet stay up.
   - **A** — create/advance **fail closed** if the chain does not take the new head
   - **B** — reads hydrate from on-chain ContentHead → IPFS
   - **C** — new objects are `did:iota:…` only (lab DID only if Identity is unconfigured)
   - **D** — OTP registry is an index (iota DID, ControllerCap id, label); not a second head
3. **User cryptographic identity** — **accepted** ([ADR 0008](decisions/0008-user-crypto-identity.md)): stages **1–4 done**. Stage 5 later (signed mutates / vault).
4. **Godot scenario worlds** — **accepted** ([ADR 0009](decisions/0009-godot-scenario-worlds.md), [docs/09](09-godot-scenario-worlds.md)): 3D room + session host; node console; playbooks = **headless peer**. Belief overlay later.
5. **Helen / Alice CoT** — storyboard **accepted** ([docs/11](11-helen-alice-cot-beats.md)); implement per [docs/12](12-helen-alice-build.md). Genesis workspaces, G/D1–D5, caps vs GraphEdit, vaults, discovery, Wendy-links. Payments, real seL4, second node, 0008-5 still later.

Do **not** couple this with: typed BEAM Identity SDK, signed HTTP as the *user* path (until 0008-5), on-ledger bootstrap cap, deleting the OTP node, real RINA, Phoenix, curl-as-King playbooks as the long-term actor.

- Discard approaches that do not pay rent
- Keep site (CONCRETE) as narrative; keep this repo as working architecture

## Anti-goals for sequencing

- Do not build platform breadth before the slice works
- Do not port Mar_26 compose “because it existed”
