# Out of scope (this prototype)

Explicit non-goals for `sep_26_concrete` so they are not silently re-imported from the site or Mar_26.

## Programme / org

- Government leadership phases, contracting, workforce programmes (see site *Development path*)
- Pj MICROCOSM as a deliverable of this repo
- Mandating CONCRETE on any population or organisation

## Full stack components (unless promoted)

Documented as programme paper in [07-programme-map.md](07-programme-map.md) / [05-concept-backlog.md](05-concept-backlog.md) — **not** deliverables of this prototype until promoted:

- seL4 / CHERI / PQC TPM / tamper-erase hardware as the node
- **RINA in the first lab path** (stock IPFS/IOTA use **TCP/IP** initially; RINA is planned as an **overlay later in this prototype** — [ADR 0002](decisions/0002-ipfs-iota-did.md))
- DWDM / photonics plant as a deliverable of this repo
- National or production clock-sync / trilateration / sensor presence stack
- Category-theoretic presence engine (manifolds, cohomology nullifiers, Heyting checkers)
- Real FIPS 202 / HKDF / ML-DSA / ML-KEM / AES-GCM / TSS / MPC validator key ceremonies as **production** custody (lab **stand-in** of user seed + ML-DSA-87 is [ADR 0008](decisions/0008-user-crypto-identity.md); seL4 vault remains later)
- Shared task object / node journal / settler economics and partition anti-overspend protocol
- Dongles / physical banks as shipping accessories
- Maths standards / full 4D ontological model as a shipping requirement
- Full Boss-Based Access Control, guards, revocation graphs, complete pseudonym systems
- Matrix as communications fabric
- Formal UK TOP SECRET (or allied) accreditation of this repository’s code
- **IINL-first naming** (this prototype uses **DIDs** from the start — ADR 0002)
- Treating **stock IPFS / stock IOTA** as the production CONCRETE fabric (lab stand-ins only)

## Prior prototype platform habits

- Recreating Mar_26’s four-container-per-node compose by default
- Shipping unused policy or keystore containers
- Vendoring upstream ledger monorepos
- Treating a privileged supervisor as the product architecture

## Process

- Maintaining Mar_26 as a long-lived product
- Expecting polish, backwards compatibility, or production security review in this docs phase

When something here becomes necessary, move it to [05-concept-backlog.md](05-concept-backlog.md) with status **slice** or **stub**, and add an ADR under `decisions/`.
