# Residues from mar_26_concrete

What remains after discarding the prior lab prototype. Full architect review lived in-session; this is the carry-forward extract.

## Keep (ideas / patterns)

| Residue | Why it paid rent |
|---------|------------------|
| Content graph: Blob / Tree / Commit | Clear sketch of versioned info, not just blob storage |
| Separate trees for content / read / write / links / message | Points at capability-aware information |
| Stable name → content head (IINL-like; DIDs later) | Mutable info with a durable address |
| Serialised authority for shared mutable objects (AdminCap + queue) | Right instinct for conflicting mutations |
| Same release, role by node name | Cheap dual packaging for lab harness vs worker |
| Backend = ground truth; UI = veneer | Documented and mostly held |

## Drop / do not migrate

| Residue | Why |
|---------|-----|
| Four Docker containers per “node” as default topology | Scaffolding, not product architecture |
| OPA-per-node with no policies / no calls | Capability theatre |
| Keystore GenServer of comments only | Paper architecture |
| IOTA via `System.cmd` + scraping CLI effects JSON | Will not survive iteration |
| Privileged supervisor as *product* mesh topology | Undercuts decentralised narrative (lab harness is OK if labelled) |
| Vendored full IOTA tree in-repo | Consume images/binaries; keep overlays + contracts as first-party |
| Full Grafana plane by default | Keep a light OTEL path if needed for the slice |

## Explicitly unfinished in Mar_26 (do not treat as done)

- King / capability bootstrap on launch
- Real encryption (`falsity_encryption_key_int` was a placeholder)
- `previously_started` lifecycle closed loop
- `iota_ri` Move package wired into Elixir
- IINL → IOTA Identity DIDs (noted in Mar_26 TODOs)

## Pointers into BigMassive/CONCRETE

Site material that still constrains this prototype (link, don’t copy wholesale):

- Basic needs (collaboration, understandability, dynamic risk, decentralised-by-default)
- Abstract node as the unit of the foundation
- Access control / capabilities / boss-minted authority
- Stack as a *map of concerns* (IPFS, IOTA, wallet, seL4, …) — not a Docker shopping list
