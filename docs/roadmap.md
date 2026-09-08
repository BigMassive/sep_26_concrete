# Roadmap

## Phase 0 — Docs and plans (current)

- [x] Create `sep_26_concrete` repo skeleton
- [ ] Owner adds new concepts to [05-concept-backlog.md](05-concept-backlog.md)
- [ ] Freeze [04-vertical-slice.md](04-vertical-slice.md) acceptance criteria
- [ ] Resolve open decisions in [03-architecture.md](03-architecture.md) via ADRs as needed
- [ ] Optional: short link/PR note on BigMassive/CONCRETE pointing at this prototype

## Phase 1 — Thin vertical slice

- Implement only what the slice requires
- Prefer typed integrations; no unused sidecars
- Demo path documented; harness labelled if present

## Phase 2 — Iterate

- Promote backlog items deliberately (stub → slice)
- Discard approaches that do not pay rent
- Keep site (CONCRETE) as narrative; keep this repo as working architecture

## Anti-goals for sequencing

- Do not build platform breadth before the slice works
- Do not port Mar_26 compose “because it existed”
