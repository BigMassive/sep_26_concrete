# Architecture decision records

Add one Markdown file per decision, e.g. `0001-runtime.md`.

Suggested template:

```markdown
# ADR NNNN: Title

- Status: proposed | accepted | superseded
- Date:

## Context

## Decision

## Consequences
```

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-lab-toolchain.md) | Lab toolchain — Docker Compose + Godot (OSS) | accepted |
| [0002](0002-ipfs-iota-did.md) | Stock IPFS + IOTA, DID naming, TCP/IP then RINA | accepted |
| [0003](0003-runtime-beam.md) | Runtime — Elixir / Erlang (BEAM) | accepted |
| [0004](0004-world-state-supervisor.md) | World state, lab supervisor, Godot veneer | accepted |
| [0005](0005-bootstrap-capability.md) | Bootstrap capability — first user on first node | accepted |
| [0006](0006-lab-did-until-iota-identity.md) | Interim lab DID until IOTA Identity publish | superseded by 0007 |
| [0008](0008-user-crypto-identity.md) | User cryptographic identity — external seed; ML-DSA-87 pubkey as truth | accepted |
| [0009](0009-godot-scenario-worlds.md) | Godot scenario worlds — first-person veneer, node console, playbook bots | accepted |

Further open questions are listed in [03-architecture.md](../03-architecture.md).
