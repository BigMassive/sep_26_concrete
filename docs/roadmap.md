# Roadmap

## Phase 0 — Docs and plans

- [x] Create `sep_26_concrete` repo skeleton
- [x] Owner adds new concepts to [05-concept-backlog.md](05-concept-backlog.md) (+ [07-programme-map.md](07-programme-map.md))
- [x] Freeze [04-vertical-slice.md](04-vertical-slice.md) acceptance criteria
- [x] Resolve open decisions needed for the slice via ADRs (0001–0006); RINA overlay ADR still later
- [ ] Optional: short link/PR note on BigMassive/CONCRETE pointing at this prototype

## Phase 1 — Thin vertical slice

- [x] Implement only what the slice requires (beats 0–6)
- [x] Prefer typed integrations; no unused sidecars
- [x] Demo path documented; harness labelled

## Phase 2 — Iterate (current)

Promote backlog items deliberately (stub → slice). First promotion:

1. **IOTA Identity publish** — replace/augment lab DID with on-ledger Identity name → head ([ADR 0002](decisions/0002-ipfs-iota-did.md), [ADR 0006](decisions/0006-lab-did-until-iota-identity.md))
2. Then pick deliberately: lab supervisor / god-view stub, second node belief, attenuation, RINA overlay packaging, …

- Discard approaches that do not pay rent
- Keep site (CONCRETE) as narrative; keep this repo as working architecture

## Anti-goals for sequencing

- Do not build platform breadth before the slice works
- Do not port Mar_26 compose “because it existed”
