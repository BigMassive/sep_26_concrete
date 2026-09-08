# Concept backlog

Triage every concept before it grows scaffolding. Narrative outline: [07-programme-map.md](07-programme-map.md).

| Status | Meaning |
|--------|---------|
| **slice** | Required for the vertical slice in this prototype |
| **stub** | Interface or minimal placeholder only |
| **paper** | Document / link to site; do not implement yet |

Slice acceptance criteria are **not frozen** yet — treat current **slice** rows as provisional until [04-vertical-slice.md](04-vertical-slice.md) is locked.

## From Mar_26 / site (seed)

| Concept | Status | Notes |
|---------|--------|-------|
| Blob / Tree / Commit content model | slice | Residue — core of the slice |
| Name → head (IINL-like or DID) | slice | Prefer DID (incl. CoT IOTA DID); IINL OK as interim |
| One capability check on mutate | slice | Must be real, not OPA-shaped theatre |
| Thin UI veneer (Godot) | slice | ADR 0001 — editor on host; project in-repo |
| Docker Compose lab harness | stub or slice | Clone-and-go services only when slice needs them; not product topology |
| Serialised mutation of shared authority | stub or slice | If shared AdminCap-like object exists |
| Keystore / crypto hand-out | paper | Real path in programme map; not until slice needs keys |
| Network policy engine (OPA-like) | paper | Only if check cannot live closer to the action |
| seL4 / hardware capabilities | paper | Target node OS with CHERI; see programme map |
| Resource markets / token economics | paper | Superseded in detail by vouchers + task trio |
| Matrix / messaging | paper | |
| Spacetime / clock sync | paper | Elevated: first-class sync + DWDM co-carriage |
| Full HQDM ontological precision | paper | Caps carry a single 4D meaning reference |
| IotaRI-style uncopyable names | paper | Unwired in Mar_26 |

## Hardware and underlay

| Concept | Status | Intent | Touches |
|---------|--------|--------|---------|
| Nodal nature + dependability as hardware priorities | paper | Programme constraint on what a node is | Node, CoT |
| CHERI CPU + seL4 | paper | Working-model compute/OS | Node runtime |
| PQC TPM (embedded or stand-alone) | paper | Holds EK + attestation material | Identity, tamper |
| Endorsement key (EK) as hardware identity | paper | Root principal for the box | Permitted-EK lists |
| Attestation keys → hardware pseudonyms (e.g. per RINA use) | paper | Multiple personas from one EK | RINA, caps |
| Atomic-class on-node clock | paper | Dependable local time | Sync, trilateration |
| Fibre + photonics / DWDM underlay | paper | Physical plant for RINA + sync | RINA |
| RINA (not Ouroboros) on same fibre as clock sync | paper | Networking narrative | Mesh, CoT |
| Tamper mesh / battery / pressure → auto-erase | paper | Physical integrity plane | TPM, EK lifetime |

## Circles of trust and membership

| Concept | Status | Intent | Touches |
|---------|--------|--------|---------|
| Circle of trust (CoT) | paper | Org / authority domain running one network | All scoped objects |
| Many CoTs; nested / embedded CoTs | paper | Plurality and containment of trust domains | Caps, lists, validators |
| Network-held permitted-EK list(s) | paper | Cap-gated admit of hardware into service | EK, info objects |
| UK TOP SECRET (+ allied) viability bar | paper | Assurance aspiration; not accreditation work here | Whole map |

## Time, space, presence

| Concept | Status | Intent | Touches |
|---------|--------|--------|---------|
| National / local clock synchronisation (first-class) | paper | Foundation time service | Clock, DWDM |
| Trilateration / relative physical position | paper | Position as security signal | Sync, caps |
| Node monitors entity/user position + identity | paper | Presence as observed state | Identity evidence |
| 4D manifold presence framework (tubes, intersections, gluing) | paper | Speculative local identity geometry; anti-N² | αβω, sensors |
| Local α / β / ω vs capability thresholds | paper | Graded identity evidence | Caps |
| Nullifier on cohomology obstruction | paper | Retract inconsistent presence hypotheses | Presence |
| Heyting constraints (e.g. impossible motion) | paper | Constructive impossibility checks | Presence |
| Sensor set grows over time (login → camera/RFID/…) | paper | Security capability of CoT is time-varying | Presence |

## User identity and custody

| Concept | Status | Intent | Touches |
|---------|--------|--------|---------|
| User crypto identity (issuance may be external) | paper | Person-principal bootstrap | Caps, lists |
| FIPS 202 → master seed; HKDF index (0=real, 1..=pseudonyms) | paper | Deterministic user/pseudonym material | ML-DSA |
| ML-DSA-87 keypairs | paper | PQC user signatures | Auth |
| Optional ML-KEM wrap with auditor pubkey | paper | Auditor-mediated visibility | Audit |
| Custody: bank / seL4 vault / dongle | paper | Where seed or derived keys live | Vault |
| Offline seL4 vault (volatile, sparse keys) | paper | Disconnected work | Keystore |
| Remote expunge of vault keys (not remote read) | paper | Boss/auditor oversight | Vault, revocation |
| Users never see raw keys | paper | Stable product principle | UI, vault |
| Identity assurance now; intent assurance later | paper | Who vs what-they-meant | Caps |
| Reverse authentication (e.g. launch challenge secret) | paper | User trusts the system | Launch, UI |

## Authority and funding

| Concept | Status | Intent | Touches |
|---------|--------|--------|---------|
| Cap = data/information boss → user | paper | Authority as transferable info/data | Info objects |
| Self-imposed restrictions (attenuation) | paper | Holder narrows own authority | Caps |
| Single 4D ontological meaning on each cap | paper | Semantic precision of “what is allowed” | HQDM |
| Identity thresholds on caps | paper | Act only if confidence ≥ threshold | αβω |
| Mutate/maintain requires capability ∧ funding | paper | Dual gate; do not collapse into one object | Settler |
| King issues time-limited vouchers (org/CoT flow) | paper | Funding control plane | King, CoT |
| Blinded funding flows for auditors | paper | Conditional financial visibility | Audit |

## Task economics (three devices)

| Concept | Status | Intent | Touches |
|---------|--------|--------|---------|
| Shared task object on IOTA (escrow + journal refs) | paper | Crowdfundable escrow for a task | Funding, IOTA |
| Node journal (seL4-local work accounting) | paper | Per-node work log for a task | Settler |
| Settler (reconcile journals, PTB pay, halt if broke) | paper | Settlement + liveness control; label if lab supervisor | Harness |
| Mempool / &lt;⅔ partition → cohort anti-overspend | paper | Spend safety under split view | Task object |

## Data, information, and keys

| Concept | Status | Intent | Touches |
|---------|--------|--------|---------|
| Data and information on IPFS (AES-256-GCM DAG) | paper | Confidential content plane | Content store |
| DID preferred over IINL; DID for CoT IOTA | paper | Universal naming | Name → head |
| C_aud + ML-KEM-1024 → auditor recovers K_DAG | paper | Auditor path into encrypted DAGs | IINL/DID |
| Data access: vault/keystore + capability | paper | Simpler gate for data | Caps |
| Information access: K_DAG + head + permission then crypto | paper | Mar_25/26 information path | Keystore |
| ~20 CoT validators; TSS master; MPC per epoch | paper | Split custody of master key | K_DAG |
| n-of-m → HKDF-SHA-256(master, name) = K_DAG | paper | Per-name DAG key | Keystore |

## Wendy-links

| Concept | Status | Intent | Touches |
|---------|--------|--------|---------|
| Wendy-link structure: dual-ended `{name, opt CID}` in links facet | paper | First-class bidirectional relation; not hyperlink | Info commits |
| Bidirectional bookkeeping when linking A↔B | paper | Both objects’ link sets updated | Keystore / commits |
| Links permissioned like other info facets | paper | Same cap/funding story later | Caps |

## Rule

If it is not on these tables (or the seed table), it is not in the prototype. Promote via an edit here + ADR if it changes architecture.
