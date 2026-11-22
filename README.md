# sep_26_concrete

A **Project CONCRETE** prototype (September 2026).

This repository starts **docs-first**: architecture, residues from prior work, vocabulary, and a vertical-slice plan. Functionality will be added iteratively once those documents are sharp enough to build against.

## Naming

| Context | Form |
|---------|------|
| This repo / paths | `sep_26_concrete` |
| Branding / presentations | **CONCRETE** / Project CONCRETE |

## Related

- Vision / socio-technical site: [BigMassive/CONCRETE](https://github.com/BigMassive/CONCRETE) · [site](https://BigMassive.github.io/CONCRETE)
- Prior lab prototype (archive, not a migration base): `mar_26_concrete` (self-hosted)

## Documents

| Doc | Purpose |
|-----|---------|
| [docs/00-intent.md](docs/00-intent.md) | Principles and prototype goal |
| [docs/01-residues.md](docs/01-residues.md) | Keep / drop from Mar_26 |
| [docs/02-vocabulary.md](docs/02-vocabulary.md) | Shared terms |
| [docs/03-architecture.md](docs/03-architecture.md) | Target model for *this* prototype |
| [docs/04-vertical-slice.md](docs/04-vertical-slice.md) | One end-to-end path |
| [docs/05-concept-backlog.md](docs/05-concept-backlog.md) | Concepts: slice / stub / paper |
| [docs/06-out-of-scope.md](docs/06-out-of-scope.md) | Explicit non-goals for this round |
| [docs/07-programme-map.md](docs/07-programme-map.md) | Owner outline (mostly paper) |
| [docs/08-phase2-iota-identity.md](docs/08-phase2-iota-identity.md) | Phase 2 Identity notes |
| [docs/09-godot-scenario-worlds.md](docs/09-godot-scenario-worlds.md) | Godot 3D worlds / console / playbooks (ADR 0009) |
| [docs/10-godot-stage1-build.md](docs/10-godot-stage1-build.md) | Implementation brief for Godot stages 1–4 |
| [docs/roadmap.md](docs/roadmap.md) | Phased plan |
| [docs/decisions/](docs/decisions/) | Architecture decision records (ADRs) |

## Cursor rules

Project rules live in [`.cursor/rules/`](.cursor/rules/). Always-on rules are sent every chat. The others apply when matching files are in play. Each rule points at the doc that holds the detail.

| Rule | When it applies | What it keeps in force |
|------|-----------------|------------------------|
| [lab-test-sessions.mdc](.cursor/rules/lab-test-sessions.mdc) | Every chat | Wipe lab state before and after a test ([lab/README.md](lab/README.md)) |
| [godot-ai.mdc](.cursor/rules/godot-ai.mdc) | Every chat | Use the Godot AI editor connection when changing the veneer ([godot/README.md](godot/README.md)) |
| [prototype-boundaries.mdc](.cursor/rules/prototype-boundaries.mdc) | Every chat | Ground truth, vocabulary, ADRs, and [out of scope](docs/06-out-of-scope.md) |
| [runtime-elixir.mdc](.cursor/rules/runtime-elixir.mdc) | `runtime/**/*.ex`, `runtime/**/*.exs` | `mix format`, focused tests, capability checks on mutates |
| [godot-veneer.mdc](.cursor/rules/godot-veneer.mdc) | `godot/**/*.gd`, `godot/**/*.tscn` | Veneer calls OTP; leave `godot/addons/godot_ai/` untouched |
| [architecture-decisions.mdc](.cursor/rules/architecture-decisions.mdc) | `docs/decisions/**/*.md` | One ADR per file, from the [decisions README](docs/decisions/README.md) template |

## Status

**Phase:** docs + lab harness (beat 0) + OTP bootstrap (beat 1). Godot UI and DID commits still pending.

## Lab environment

Per [docs/decisions/0001-lab-toolchain.md](docs/decisions/0001-lab-toolchain.md) and [lab/README.md](lab/README.md):

- **Docker Compose** lab harness — project-private **IPFS** + **local IOTA** (not product topology).
- **Godot** (OSS) on the host for the UI project (later beats).
- **Elixir / OTP** node runtime (later beats); **no Phoenix**.
- **Required tools are open source** — no paid licences. Cursor is optional.

Test runs do not keep state from the previous run. Start from a wiped `lab/data/`, and shut the stack down with a wipe afterwards. The steps are in [lab/README.md](lab/README.md#test-sessions--start-clean-then-wipe).

```bash
./scripts/session-up.sh --godot   # wipe, IPFS + IOTA, identity publish, OTP, Godot window
./scripts/beat1-smoke.sh
./scripts/lab-status.sh
./scripts/session-down.sh         # stop Godot and OTP, wipe, check ports
```


## Licence / contribution

Prototype material — expect iteration and discard of approaches that do not earn their keep. Prefer Issues/Discussions on this repo for this prototype; programme-level conversation remains on [BigMassive/CONCRETE](https://github.com/BigMassive/CONCRETE).
