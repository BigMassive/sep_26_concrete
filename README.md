# sep_26_concrete

A **Project CONCRETE** prototype (September 2026).

This repository is the working prototype: the docs and ADRs, a Docker lab (private IPFS and local IOTA), an Elixir/OTP node, and a Godot veneer. Programme narrative stays on the BigMassive/CONCRETE site.

## Naming

| Context | Form |
|---------|------|
| This repo / paths | `sep_26_concrete` |
| Branding / presentations | **CONCRETE** / Project CONCRETE |

## Related

- Vision / socio-technical site: [BigMassive/CONCRETE](https://github.com/BigMassive/CONCRETE) · [site](https://BigMassive.github.io/CONCRETE)
- Prior lab prototype (archive, not a migration base): `mar_26_concrete` (self-hosted)

## Fresh machine

`./scripts/session-up.sh` runs `./scripts/check-host.sh` before it wipes anything. Install these, then open a new shell so group membership applies:

- **Docker Engine** and the **Compose v2 plugin**. `docker compose version` must work without `sudo`. If the socket says permission denied: `sudo usermod -aG docker "$USER"`, then open a new shell.
- **Elixir 1.17** or newer (this repo is developed on 1.18 / OTP 27).
- **Godot 4.7** on `PATH` as `godot` or `godot4`, or set `GODOT_BIN`.
- **Python 3.11** or newer, with `python3 -m venv` working (`python3-venv` on Debian/Ubuntu). `./scripts/node-up.sh` creates `lab/.venv` and installs `scripts/requirements-user-identity.txt`.
- `openssl`, `curl`, and `git`.

The first Godot launch imports the project when `godot/.godot/` is missing. That directory is gitignored.

## Run it

A test starts clean and ends wiped. The steps are in [lab/README.md](lab/README.md#test-sessions--start-clean-then-wipe).

```bash
./scripts/session-up.sh --godot          # wipe, IPFS + IOTA, identity publish, OTP, Godot window
./scripts/session-down.sh                # stop Godot and OTP, wipe, check ports
```

The scripted Helen → Alice console beat needs port 24567 free, so do not pass `--godot` on that up:

```bash
./scripts/session-up.sh
./scripts/godot-scenario.sh helen-alice  # headless; prints one JSON result
GODOT_SCENARIO_WINDOW=1 ./scripts/godot-scenario.sh helen-alice
```

That script is a **host scenario** (one process, both personas). It is not the joining playbook, which is still a known red path. PINs from a successful run are in `lab/run/scenario-pins.txt`. Play notes are in [godot/README.md](godot/README.md). OTP is [runtime/README.md](runtime/README.md).

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
| [docs/11-helen-alice-cot-beats.md](docs/11-helen-alice-cot-beats.md) | Helen → Alice storyboard |
| [docs/12-helen-alice-build.md](docs/12-helen-alice-build.md) | Coding brief for that play |
| [docs/roadmap.md](docs/roadmap.md) | Phased plan |
| [docs/decisions/](docs/decisions/) | Architecture decision records (ADRs) |

## Cursor rules

Project rules live in [`.cursor/rules/`](.cursor/rules/). Always-on rules are sent every chat. The others apply when matching files are in play. Each rule points at the doc that holds the detail.

| Rule | When it applies | What it keeps in force |
|------|-----------------|------------------------|
| [lab-test-sessions.mdc](.cursor/rules/lab-test-sessions.mdc) | Every chat | Wipe lab state before and after a test ([lab/README.md](lab/README.md)) |
| [godot-ai.mdc](.cursor/rules/godot-ai.mdc) | Every chat | Godot AI editor connection, and host scenarios such as `./scripts/godot-scenario.sh helen-alice` ([godot/README.md](godot/README.md)) |
| [prototype-boundaries.mdc](.cursor/rules/prototype-boundaries.mdc) | Every chat | Ground truth, vocabulary, ADRs, and [out of scope](docs/06-out-of-scope.md) |
| [runtime-elixir.mdc](.cursor/rules/runtime-elixir.mdc) | `runtime/**/*.ex`, `runtime/**/*.exs` | `mix format`, focused tests, capability checks on mutates |
| [godot-veneer.mdc](.cursor/rules/godot-veneer.mdc) | `godot/**/*.gd`, `godot/**/*.tscn` | Veneer calls OTP; leave `godot/addons/godot_ai/` untouched |
| [architecture-decisions.mdc](.cursor/rules/architecture-decisions.mdc) | `docs/decisions/**/*.md` | One ADR per file, from the [decisions README](docs/decisions/README.md) template |

## Status

**Phase:** lab session (`session-up` / `session-down`), OTP on `:4000` with IOTA Identity heads, and the Godot room and node console (personas, W0–W2, Exit to menu). The host scenario `helen-alice` runs genesis through Alice login. Discovery and W2 stay on the console. `./scripts/godot-playbook.sh` is still a known red path. Signed HTTP, payments, real seL4, and a second node stay later.

## Lab environment

Per [docs/decisions/0001-lab-toolchain.md](docs/decisions/0001-lab-toolchain.md) and [lab/README.md](lab/README.md):

- **Docker Compose** lab harness — project-private **IPFS** + **local IOTA** (not product topology).
- **Godot 4.7** on the host for the veneer (`godot/`). The project icon and in-world mark are `godot/images/concrete_icon_200.png`, taken from the March prototype.
- **Elixir / OTP** node runtime (`runtime/`); **no Phoenix**.
- **Required tools are open source** — no paid licences. Cursor is optional.

Test runs do not keep state from the previous run. Start from a wiped `lab/data/`, and shut the stack down with a wipe afterwards. Use the commands under **Run it**. `./scripts/lab-status.sh` reports the harness. `./scripts/beat-smoke.sh` checks Helen → Alice over HTTP and does not drive Godot.


## Licence / contribution

Prototype material — expect iteration and discard of approaches that do not earn their keep. Prefer Issues/Discussions on this repo for this prototype; programme-level conversation remains on [BigMassive/CONCRETE](https://github.com/BigMassive/CONCRETE).
