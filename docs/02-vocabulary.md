# Vocabulary

Single place for terms used in this prototype. Prefer these spellings in docs and code comments.

| Term | Meaning in `sep_26_concrete` |
|------|------------------------------|
| **CONCRETE** | Programme / brand name (presentations, site). |
| **`sep_26_concrete`** | This prototype repository and iteration. |
| **Node** | One abstract CONCRETE computing participant in a mesh. Implementation may be one process or a small stack — define per ADR. |
| **Mesh** | Set of nodes that can cooperate; no requirement for a privileged centre *as product architecture*. |
| **Info object** | Versioned information with a durable name and a content head (commit graph). |
| **Commit / Tree / Blob** | Git-like content model: head commit points at trees; trees at blobs/CIDs. |
| **Name / head** | Stable identifier (ledger object, DID, …) that points at the current content CID. |
| **Capability** | Unforgeable authority to perform a specific action or access a resource. Nothing on the critical path without one (once the slice implements it). |
| **Boss** | Role that mints or delegates capabilities (site term). Exact hierarchy (King, guards, …) is out of scope until modelled. |
| **King** | Bootstrap / highest local authority persona used in prior prototypes — refine or rename via ADR before coding. |
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
