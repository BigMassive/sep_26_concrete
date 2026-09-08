# ADR 0003: Runtime — Elixir / Erlang (BEAM)

- Status: accepted
- Date: 2026-09-08

## Context

The vertical slice needs a **node runtime** for orchestration: talk to stock IPFS and IOTA Identity ([ADR 0002](0002-ipfs-iota-did.md)), enforce one capability check, and expose a thin API that **Godot** calls on localhost ([ADR 0001](0001-lab-toolchain.md)).

Mar_26 used the BEAM and it earned keep for distribution-shaped work, even though that lab’s IOTA integration habits (CLI scraping) are residues to drop. Owner preference and the decentralised / actor-style theme of CONCRETE nodes align with **Elixir / Erlang** on the BEAM.

As with IPFS/IOTA, BEAM distribution and sockets will use **TCP/IP** under the hood in the lab; **RINA** remains a later **overlay** in this prototype (ADR 0002), not a blocker for choosing the runtime.

## Decision

1. **Runtime language:** **Elixir** (and Erlang/OTP where appropriate) on the **BEAM** is the node runtime for `sep_26_concrete`.
2. **Role:** orchestration and typed clients to lab IPFS / IOTA Identity; capability check on the mutate path; HTTP (or similar) surface for Godot — **not** a Phoenix (or other BEAM web) UI; not a requirement to ship a multi-node BEAM cluster on day one.
3. **Transport honesty:** accept **TCP/IP** for BEAM distribution, HTTP, and IPFS/IOTA clients now. Keep dial/transport concerns thin so a **RINA overlay** can land later without rewriting info-object or capability semantics.
4. **Lab packaging:** runtime may run on the host or in Compose; if containerised, pin versions and label as **lab harness**. Prefer clone-and-go that does not require a proprietary toolchain (Elixir/OTP are OSS).
5. **Integration style:** use libraries/SDKs or HTTP APIs from Elixir — **not** `System.cmd` + scrape CLI JSON for ledger mutations (Mar_26 anti-pattern).
6. **Godot** stays the UI veneer; it does not become the orchestration runtime. **No Phoenix** — see [ADR 0004](0004-world-state-supervisor.md).

## Consequences

- Exact app layout (plain OTP vs named cluster) can be a follow-on detail when coding starts; **Phoenix is out** for UI ([ADR 0004](0004-world-state-supervisor.md)).
- Distribution features (nodes, registries) are available when the slice needs them; do not build a mesh platform before the slice works.
- RINA overlay work must treat BEAM-over-TCP as replaceable underlay plumbing, same as ADR 0002’s stance on IPFS/IOTA.
