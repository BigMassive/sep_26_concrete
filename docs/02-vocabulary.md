# Vocabulary

Single place for terms used in this prototype. Prefer these spellings in docs and code comments. Programme narrative: [07-programme-map.md](07-programme-map.md).

| Term | Meaning in `sep_26_concrete` |
|------|------------------------------|
| **CONCRETE** | Programme / brand name (presentations, site). |
| **`sep_26_concrete`** | This prototype repository and iteration. |
| **Node** | One abstract CONCRETE computing participant in a mesh. Target hardware story: CHERI + seL4 + PQC TPM (paper). Lab runtime: **Elixir / BEAM** ([ADR 0003](decisions/0003-runtime-beam.md)). |
| **Mesh** | Set of nodes that can cooperate; no requirement for a privileged centre *as product architecture*. |
| **Circle of trust (CoT)** | Organisation / authority domain that runs one CONCRETE network instance. Many CoTs may exist; some may nest. Not generic PKI “circle of trust” prose. |
| **Info object** | Versioned information with a durable name and a content head (commit graph). |
| **Data** | Content whose access is gated by capability (+ keystore); distinct from versioned **information** head semantics. |
| **Commit / Tree / Blob** | Git-like content model: head commit points at trees; trees at blobs/CIDs. Facets include content, read, write, links (and related). |
| **Name / head** | Stable **DID** that points at the current content CID. **Now:** IOTA Identity DID document ContentHead on stock IOTA when the package is configured ([ADR 0002](decisions/0002-ipfs-iota-did.md), [ADR 0007](decisions/0007-iota-did-head-authority.md)). Phase 1 leftover: lab DID + IPFS DID doc if Identity is unconfigured. |
| **Ground truth** | Authoritative state; UI must not invent durable state. Name → head: **on-chain Identity**. Content bytes: **IPFS**. OTP: executor / cache / cap check; Godot talks only to OTP HTTP. |
| **IINL** | Legacy Mar_25/26 IOTA IPFS name-link object. **Not** the naming path for this prototype (DID instead). |
| **DID** | Decentralised identifier; naming from the start, including for a CoT’s IOTA when needed. |
| **K_DAG** | Symmetric key material for an encrypted IPFS DAG of a named object; derived per name from CoT master via HKDF in the programme map. |
| **EK** | Endorsement key — fundamental hardware identity held in the PQC TPM story. |
| **Capability** | Authority (as data/information) granted boss → user to perform a specific action or access a resource. May include a 4D meaning reference and identity thresholds; holder may self-restrict. Nothing on the critical path without one (once the slice implements it). |
| **Bootstrap capability** | Auto-minted to the **first user on the first node** of a fresh instance; authorises **anything anywhere** (admin/root). Live check on mutates; not a Godot flag or supervisor bypass ([ADR 0005](decisions/0005-bootstrap-capability.md)). |
| **Funding / voucher** | Time-limited economic authority (King-issued within a CoT) required alongside capability for many mutations/maintenance. |
| **Boss** | Role that mints or delegates capabilities (site term). Exact hierarchy (guards, …) is out of scope until modelled. |
| **King** | Bootstrap / highest local authority persona — in this prototype, the **first user** who receives the bootstrap capability ([ADR 0005](decisions/0005-bootstrap-capability.md)). Also issues vouchers in the funding story (paper). |
| **Shared task object** | Ledger object: escrow for a task (incl. crowdfunding) plus refs to participant node journals. |
| **Node journal** | Local (seL4) accounting of work done by a node for a task. |
| **Settler** | Component that reconciles journals against a shared task and performs settlement (e.g. IOTA PTB); may halt work when funds run out. Label as harness if privileged in a lab. |
| **Wendy-link** | First-class bidirectional relation between named info endpoints `{DID, optional CID}`, stored in the links facet — not a one-way hyperlink. |
| **RINA** | Recursive InterNetwork Architecture — programme networking narrative; lab introduces it as an **overlay later**, after TCP/IP IPFS/IOTA (ADR 0002). |
| **Vault / keystore** | seL4 (or stand-in) component holding keys in volatile memory; users do not see raw keys; remote expunge possible for bosses/auditors. |
| **α / β / ω** | Local likelihood, confidence, and weight of evidence for identity/presence — matched to capability identity thresholds (paper). |
| **Vertical slice** | One end-to-end user-visible path implemented through all layers that matter for that path. |
| **Slice / stub / paper** | Triage for concepts: implement now / placeholder interface / document only. |
| **Residue** | Idea or pattern kept from a discarded prototype. |
| **Lab harness** | Disposable Docker Compose (etc.) topology for demos — not the product node architecture. |
| **Godot** | OSS UI veneer: thin **physical-world** view (environments, avatars, drawn nodes). Not durable ground truth ([ADR 0004](decisions/0004-world-state-supervisor.md)). |
| **Lab supervisor** | Privileged lab harness process: bootstrap, seed durable facts, may publish **god-view** position. Not product mesh centre; not live capability/commit authority. |
| **God-view (position)** | Objective / actual position of a node in the modelled or physical world. Lab: often supervisor-published. Not solely node self-report. |
| **Node belief (position)** | Where the node *thinks* it is (local estimate). Owned by the node (OTP); confidence/αβω later. |

## Certainty labels (from the site)

When useful, mark statements:

- **Stable** — working assumption for this prototype
- **Probable** — likely, not locked
- **Speculative** — exploratory
- **To-do** — known gap
