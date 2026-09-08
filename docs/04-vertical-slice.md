# Vertical slice

One end-to-end path. Everything we build should serve this path until it is real.

## Proposed slice (draft — refine before coding)

> A user **creates a named info object**, a **capability is checked** once, a **commit advances**, and the **UI reflects backend state only**.

### Acceptance criteria (draft)

1. An info object exists with a durable **DID** and a **commit head** (Blob←Tree←Commit on IPFS).
2. Advancing the head requires passing **one** explicit authority/capability check (fail closed). For the first instance, the **bootstrap capability** (auto-granted to the first user on the first node — do-anything/admin) satisfies this when present ([ADR 0005](decisions/0005-bootstrap-capability.md)).
3. Reading the current head and payload does not invent UI-only state; refresh from backend.
4. Demo path is documented; lab harness (if any) is labelled as harness.
5. A principal **without** the bootstrap capability (or any covering cap) cannot advance the head.

### Non-goals for the slice

- Multi-boss hierarchies, revocation graphs, guards
- Attenuation / delegation UI beyond proving the check
- Encryption beyond placeholders (unless needed for the check)
- Funding ∧ capability dual gate (funding remains paper)
- Full mesh membership politics
- Production security of secrets on the wire
- RINA overlay (comes later in this prototype; first path is TCP/IP — [ADR 0002](decisions/0002-ipfs-iota-did.md))
- Treating stock IPFS/IOTA as the final CONCRETE fabric

## Status

**Draft → ready to freeze pending owner sign-off.** Lab stack and bootstrap capability ADRs are in place. Fill scenario sketch, then mark frozen.

## Scenario sketch

Godot physical veneer + OTP nodes ([ADR 0001](decisions/0001-lab-toolchain.md), [ADR 0004](decisions/0004-world-state-supervisor.md)):

- Actors: **King** (first user on first node, holds bootstrap capability); a second user without that cap; working OTP node(s); optional labelled lab supervisor
- Happy path: King creates/advances an info object (DID → IPFS head); capability check passes; Godot refreshes from OTP
- Failure path (capability denied): second user attempts the same mutate → fail closed; Godot shows backend denial, not a local success
- Note: Godot may later show **god-view** vs **node belief** markers; not required for first freeze
