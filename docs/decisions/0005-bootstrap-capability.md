# ADR 0005: Bootstrap capability — first user on first node

- Status: accepted
- Date: 2026-09-08

## Context

The vertical slice requires **one real capability check** on the mutate path (fail closed). Programme vocabulary has **King** / boss-minted authority and residues note unfinished “King / capability bootstrap on launch.” We need a minimal bootstrap that is honest about authority without building full BBAC, guards, or revocation graphs.

Owner decision: the first capability is automatically granted to the **very first user** on the **very first node**, and it authorises **anything anywhere** — analogous to a contemporary admin / root, and aligned with the **King** bootstrap persona for this prototype.

This is distinct from the **lab supervisor** ([ADR 0004](0004-world-state-supervisor.md)): the supervisor seeds the lab and may publish god-view; it must **not** be the live holder of this mutate authority. The **user** holds the bootstrap capability; OTP **checks** it on the critical path.

## Decision

1. **Bootstrap event:** On initialisation of the first working node in a fresh lab/CoT instance, when the first user principal is established, the system **automatically mints and assigns** a single **bootstrap capability** to that user. No prior boss is required for this one mint (the process is the bootstrap).
2. **Meaning:** That capability represents authority to **do anything anywhere** in the prototype’s authority model for this CoT instance — admin/root equivalent. Narrower caps, 4D meaning refs, identity thresholds, and self-restriction remain later promotions.
3. **Check:** Advancing a DID head / mutating protected state **must** verify that the acting principal holds a capability that covers the action. For the first slice, “holds the bootstrap capability” is sufficient coverage for allowed mutates. Absence ⇒ **fail closed**.
4. **Representation:** Store the capability as durable authority data associated with the user principal (exact encoding — Move object, DID-linked record, OTP + ledger — chosen at implementation time). It must be **unforgeable in the lab’s trust model** (not a Godot-side flag, not a supervisor bypass).
5. **King alignment:** The first user is the bootstrap **King** persona for this instance (may keep the name “King” in demos). Later users receive authority only by **delegation** from a holder (out of scope for the thinnest slice beyond proving the check).
6. **Supervisor boundary:** Lab supervisor may create the first node / trigger bootstrap **mechanics**, but must not silently pass mutate calls without the capability check, and must not retain the bootstrap capability as a hidden back door in the product narrative.
7. **Funding:** First slice does **not** require the funding ∧ capability dual gate unless separately promoted; bootstrap capability alone gates the slice mutates. Programme map funding stays paper.
8. **Non-goals for this ADR:** multi-boss hierarchies, attenuation UI, revocation graphs, per-resource caps, ontological meaning URIs on the bootstrap cap (may use a single fixed “root/admin” meaning stub).

## Consequences

- Open decision “how the first capability is represented and checked” is resolved at the **policy** level; wire format is an implementation detail under this ADR.
- Vertical slice happy path: first user holds bootstrap cap → mutate succeeds. Failure path: any other principal (or missing cap) → denied.
- Eve-style tests from Mar_25 remain valid: no cap ⇒ no crypto/no advance.
- Later work attenuates from this root rather than inventing a second parallel admin channel.
- Docs must not equate lab supervisor with King capability.
