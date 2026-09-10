# Programme map (working outline)

Owner outline for Project CONCRETE foundations as they constrain `sep_26_concrete`. **Most items are paper** for this prototype — see triage in [05-concept-backlog.md](05-concept-backlog.md). Vertical slice freeze is still pending.

Certainty: treat this document as **Probable** programme shape unless marked otherwise. It is not an implementation plan.

## Hardware / node

- **Priorities:** nodal nature and dependability.
- **Working model:** CHERI-based CPU running **seL4**, plus embedded or stand-alone **PQC TPM**.
- **TPM holds:** endorsement key (**EK** — fundamental hardware identity) and attestation-style keys for **pseudonyms** (e.g. different **RINA** uses). Networking narrative is **RINA**, not Ouroboros.
- **Clock:** accurate on-node clock (modern atomic-class).
- **Fibre / photonics:** DWDM on the same physical fibre for **RINA** and **clock sync**.
- **Tamper:** physical meshes, battery, pressure (etc.) sensors; **auto-erase** on detect.

## Circles of trust

- Organisation running one of these networks = **circle of trust (CoT)**.
- Expect **many** CoTs; some may be **embedded within others**.
- Network-held **permitted-EK list(s)**; updated by actors with a suitable **capability** as hardware enters service.

## Assurance bar

- Approach should be a viable candidate for **UK TOP SECRET**, and preferably allied contexts (US, GER, FRA, …).
- Accreditation and national COMSEC programmes remain out of scope for this repo; the map must not contradict that bar.

## Time, space, presence

- **National / local clock synchronisation** is first-class.
- Sync enables basic **trilateration** so devices know **relative physical positions** (security signal). Keep **god-view** (actual) distinct from **node belief** (estimate) — [ADR 0004](decisions/0004-world-state-supervisor.md).
- Nodes also **monitor positions / identity** of other entities (e.g. users).
- **Identity evidence framework (speculative prototype math):** continuous 4D spacetime manifold; local readings → trajectory tubes / vector fields; neighbour restrictions = projection on intersecting hypersurface; gluing for alignment; local **α / β / ω** (likelihood, confidence, weight of evidence) matched to capabilities; cohomology obstruction → **nullifier**; **Heyting** constraints (e.g. impossible speed). Start with login; later cameras, RFID, etc. — **system security capability changes over time**. Keep local (avoid N² full share).

## User crypto identity

- User given a crypto identity (issuance may be **external** to the system).
- **FIPS 202** → master seed; **HKDF** with index (`0` = real identity; `1..n` = pseudonyms).
- Produce **ML-DSA-87** keypairs; optionally blinded/wrapped with **ML-KEM** and an auditor public key.
- Custody: physical bank, **seL4 vault** (volatile), and/or dongle-style device.
- **Users never see raw keys.** Bosses/auditors may **remotely expunge** vault keys, not read them.
- Prototype promotion: [ADR 0008](decisions/0008-user-crypto-identity.md) (**accepted**, stages **1–4** in lab) — sidecar + IPFS **data** directory + Godot people; **public key as principal truth**; `{pubkey, username}` named with `did:iota`; bootstrap cap enables access. Vault and signatures later.

## Identity, intent, mutual auth

- **Identity** first (“is this the person?”); **intent** later (“is that what they wanted?”).
- System authenticates user primarily; also **reverse authentication** so the user trusts the system (e.g. launch/start process holds a challengeable secret).

## Authority and funding

- **Capability / authority:** data or information given **boss → user**; holder may **self-impose restrictions**.
- Cap carries a **single 4D ontological meaning** reference and **identity thresholds** (never 100% certain).
- Mutating state (and sometimes **maintaining** it) requires **funding ∧ capability**.
- **King** controls funding issuance; flows within an organisation / CoT; **time-limited vouchers**; optional blinding so auditors can follow flows when needed.

## Task / storage / state-change economics

For every task / storage / state change, three devices:

1. **Shared task object** (IOTA): escrow (incl. crowdfunding); list of addresses of participant **node journals**.
2. **Node journal** (seL4-local): accounting of work by this node for this task.
3. **Settler:** monitors journals for the task; reconciles (e.g. zeroes journals); **IOTA PTB** to move money; **stops work** when funds run out.

**Partition safety:** nodes watch IOTA mempool for signs of **&lt;⅔** connectivity; nodes in the same partition on the same task cooperate so they do not **overspend**.

## Data and information

- Both held on **IPFS** (AES-256-GCM, split across DAG blocks as needed).
- Naming: prefer **DID** (including an identifier for **this CoT’s IOTA**); **DIDs from the start** in this prototype ([ADR 0002](decisions/0002-ipfs-iota-did.md)) — not IINL-first.
- Lab stand-ins: **stock IPFS** + **stock IOTA** over **TCP/IP** now; **RINA overlay later** in this same prototype (ADR 0002).
- If auditor wrap is added later: **C_aud** and **ML-KEM-1024** under auditor pubkey so auditor can recover **K_DAG**.
- **Data access:** seL4 keystore/vault + **capability** check.
- **Information access:** keystore recovers **K_DAG** + **head**, checks permission, then provides crypto (user still does not see raw keys in the product story).

### K_DAG from CoT validators

- Moderate CoT: on the order of **~20 IOTA validators**.
- **Threshold secret sharing** of a master key (none holds the full key); **MPC** rotates it each **epoch** (or on demand).
- Keystore request for a name → **n-of-m** responses → **HKDF-SHA-256(master, IINL/DID)** = per-name **K_DAG**.

### Offline vault

- Local seL4 process in volatile memory holds keys **sparingly** for offline work; same expunge / no-raw-key rules.

## Wendy-links (structure)

Residue from Mar_25 Godot lab + site — keep **structure**, not the falsity harness:

- Endpoints: `{DID, optional CID}` (empty CID ⇒ live head).
- First-class edge in the commit **links** facet, not an inline hyperlink.
- Bidirectional bookkeeping when relating A↔B.
- Same permission / capability story as other information facets.

## Explicitly deferred for this repo

Implementation of hardware, RINA plant, TSS/MPC, real PQC, settler/journals, presence math, dongles, and accreditation — see [06-out-of-scope.md](06-out-of-scope.md) and backlog statuses.

Next docs step: freeze [04-vertical-slice.md](04-vertical-slice.md) against a minimal subset of the above.
