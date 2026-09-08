# Vocabulary

Single place for terms used in this prototype. Prefer these spellings in docs and code comments. Programme narrative: [07-programme-map.md](07-programme-map.md).

| Term | Meaning in `sep_26_concrete` |
|------|------------------------------|
| **CONCRETE** | Programme / brand name (presentations, site). |
| **`sep_26_concrete`** | This prototype repository and iteration. |
| **Node** | One abstract CONCRETE computing participant in a mesh. Target hardware story: CHERI + seL4 + PQC TPM (paper). Implementation may be one process or a small stack — define per ADR. |
| **Mesh** | Set of nodes that can cooperate; no requirement for a privileged centre *as product architecture*. |
| **Circle of trust (CoT)** | Organisation / authority domain that runs one CONCRETE network instance. Many CoTs may exist; some may nest. Not generic PKI “circle of trust” prose. |
| **Info object** | Versioned information with a durable name and a content head (commit graph). |
| **Data** | Content whose access is gated by capability (+ keystore); distinct from versioned **information** head semantics. |
| **Commit / Tree / Blob** | Git-like content model: head commit points at trees; trees at blobs/CIDs. Facets include content, read, write, links (and related). |
| **Name / head** | Stable identifier (IINL, DID, …) that points at the current content CID. Prefer DID when practical. |
| **IINL** | IOTA IPFS name-link style object: durable id + updateable CID head (Mar_25/26 residue; interim OK). |
| **DID** | Decentralised identifier; preferred universal naming, including for a CoT’s IOTA. |
| **K_DAG** | Symmetric key material for an encrypted IPFS DAG of a named object; derived per name from CoT master via HKDF in the programme map. |
| **EK** | Endorsement key — fundamental hardware identity held in the PQC TPM story. |
| **Capability** | Authority (as data/information) granted boss → user to perform a specific action or access a resource. May include a 4D meaning reference and identity thresholds; holder may self-restrict. Nothing on the critical path without one (once the slice implements it). |
| **Funding / voucher** | Time-limited economic authority (King-issued within a CoT) required alongside capability for many mutations/maintenance. |
| **Boss** | Role that mints or delegates capabilities (site term). Exact hierarchy (King, guards, …) is out of scope until modelled. |
| **King** | Bootstrap / highest local authority persona; in the funding story, controls voucher issuance — refine or rename via ADR before coding. |
| **Shared task object** | Ledger object: escrow for a task (incl. crowdfunding) plus refs to participant node journals. |
| **Node journal** | Local (seL4) accounting of work done by a node for a task. |
| **Settler** | Component that reconciles journals against a shared task and performs settlement (e.g. IOTA PTB); may halt work when funds run out. Label as harness if privileged in a lab. |
| **Wendy-link** | First-class bidirectional relation between named info endpoints `{name, optional CID}`, stored in the links facet — not a one-way hyperlink. |
| **RINA** | Recursive InterNetwork Architecture — networking narrative for this outline (replaces Ouroboros in this repo’s map). |
| **Vault / keystore** | seL4 (or stand-in) component holding keys in volatile memory; users do not see raw keys; remote expunge possible for bosses/auditors. |
| **α / β / ω** | Local likelihood, confidence, and weight of evidence for identity/presence — matched to capability identity thresholds (paper). |
| **Ground truth** | Authoritative state of the system; UI must not invent durable state. |
| **Vertical slice** | One end-to-end user-visible path implemented through all layers that matter for that path. |
| **Slice / stub / paper** | Triage for concepts: implement now / placeholder interface / document only. |
| **Residue** | Idea or pattern kept from a discarded prototype. |

## Certainty labels (from the site)

When useful, mark statements:

- **Stable** — working assumption for this prototype
- **Probable** — likely, not locked
- **Speculative** — exploratory
- **To-do** — known gap
