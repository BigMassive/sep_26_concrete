# Vertical slice

One end-to-end path. Everything we build should serve this path until it is real.

## Proposed slice (draft — refine before coding)

> A user **creates a named info object**, a **capability is checked** once, a **commit advances**, and the **UI reflects backend state only**.

### Acceptance criteria (draft)

1. An info object exists with a durable **name** and a **commit head** (Blob←Tree←Commit).
2. Advancing the head requires passing **one** explicit authority/capability check (fail closed).
3. Reading the current head and payload does not invent UI-only state; refresh from backend.
4. Demo path is documented; lab harness (if any) is labelled as harness.

### Non-goals for the slice

- Multi-boss hierarchies, revocation graphs, guards
- Encryption beyond placeholders (unless needed for the check)
- Full mesh membership politics
- Production security of secrets on the wire

## Status

**Draft.** Concepts are outlined in [07-programme-map.md](07-programme-map.md) and triaged in [05-concept-backlog.md](05-concept-backlog.md). **Freeze acceptance criteria next** — do not expand this slice to the whole programme map.

## Scenario sketch (optional later)

Placeholders for scenario scripts / Godot (or other) scenes once docs freeze:

- Actors:
- Happy path:
- Failure path (capability denied):
