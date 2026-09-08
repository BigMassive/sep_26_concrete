# ADR 0002: Stock IPFS + IOTA, DID naming, TCP/IP then RINA

- Status: accepted
- Date: 2026-09-08

## Context

The programme map targets a dependable underlay (including **RINA**) and durable naming that is more universal than Mar_25/26 **IINL** objects. For `sep_26_concrete` we need lab stand-ins that are available now, OSS-friendly under [ADR 0001](0001-lab-toolchain.md), and good enough to prove the vertical slice (name → head, content CID graph, one capability-gated mutate).

Stock **IPFS** and stock **IOTA** will not be the final system’s content/ledger fabric, but they are adequate prototypes. Transport for those stand-ins today is **TCP/IP**. **RINA** is still intended **in this prototype**, later, as an **overlay** — not deferred forever to another repo.

Naming preference is **DID** (via **IOTA Identity** on stock IOTA) from the start, rather than building on IINL and migrating later.

## Decision

1. **Content store (lab):** use **stock IPFS** (Compose-pinned) for the Blob / Tree / Commit CID graph. Label as lab harness stand-in; not a commitment that production CONCRETE ships IPFS.
2. **Ledger / naming plane (lab):** use **stock IOTA** (Compose-pinned) for durable names and authority-related objects needed by the slice. Same stand-in disclaimer.
3. **Naming:** use **DIDs from the start** (IOTA Identity / `did:iota:…` or whatever method the stock Identity stack provides). A DID (or DID-linked document field/service) holds the **updateable content head** (IPFS CID). Do **not** plan an IINL-first path for this prototype; IINL remains residue/history only.
4. **CoT ledger identity:** when needed, this CoT’s IOTA instance / network identity is also expressed as a **DID**, not only an opaque chain id.
5. **Transport now:** accept that IPFS and IOTA speak **TCP/IP** in the lab (localhost / Compose published ports). Client code should treat dial/transport as a thin boundary so a later overlay can change how packets move without rewriting name→head or capability semantics.
6. **RINA later in this prototype:** introduce **RINA as an overlay** in a subsequent step of `sep_26_concrete` (stub then promote). First compose path does not require RINA. TCP/IP remains the bootstrap/harness underlay until the overlay exists.
7. **Integration style:** prefer **typed APIs/SDKs** (IPFS HTTP API, IOTA / Identity SDKs) over shelling out to CLIs and scraping JSON (Mar_26 anti-pattern).
8. **Slice discipline:** keep Identity use thin — create/resolve DID, update head CID under a **real capability check**. Do not expand into a full credentials/VC platform unless the frozen slice names that need.
9. **Godot:** continues to call the node runtime (or thin helpers) on **localhost**; it does not embed IPFS/IOTA protocol stacks.

## Consequences

- Open decisions “content store” and “naming” are resolved for this prototype’s lab path.
- Vertical slice acceptance criteria should say **DID → head CID**, not IINL.
- Wendy-link endpoints use DIDs (optional CID still pins a version).
- Programme-map items (K_DAG TSS, permitted-EK lists, etc.) may key off DID strings when promoted; no IINL dependency.
- Out-of-scope “RINA” means **not in the first TCP/IP compose path**, not “never in sep_26.”
- IPFS and IOTA remain **replaceable** stand-ins; docs and code comments must not treat them as the end-state fabric.
- Runtime is **Elixir / BEAM** ([ADR 0003](0003-runtime-beam.md)); use libraries/HTTP APIs from Elixir for IPFS and IOTA Identity.
