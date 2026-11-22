# Lab harness (Docker)

**Not product topology.** Disposable stand-ins for beat 0 of the vertical slice: project-private **IPFS** and a **local IOTA** network. See [ADR 0001](../docs/decisions/0001-lab-toolchain.md) and [ADR 0002](../docs/decisions/0002-ipfs-iota-did.md).

## One command

From the repo root (requires Docker + Compose, `openssl`, `curl`):

```bash
./scripts/lab-up.sh
```

Stop:

```bash
./scripts/lab-down.sh          # keep local data
./scripts/lab-down.sh --wipe   # delete lab/data (new swarm key + genesis next time)
```

## Test sessions — start clean, then wipe

**Until the owner says otherwise, runs are not coherent with each other.** Do not keep a Circle of Trust, chain id, checkpoint, identity package id, or OTP node between tests.

```bash
./scripts/session-up.sh            # wipe, lab, identity publish, OTP in the background
./scripts/session-up.sh --godot    # same, and open the windowed veneer
./scripts/session-down.sh          # stop Godot and OTP, wipe, check the ports
```

`session-up` stops anything still running, deletes `lab/data/` (IPFS swarm, IOTA genesis, identity package, node, vault), brings the harness up, publishes the Identity package for that genesis, and leaves OTP detached. Logs and pids are in `lab/run/`. The Identity Move sources stay in `lab/cache/` so the next session does not clone them again.

`session-down` confirms nothing is left: no `sep26_lab_*` containers, no Godot for this repo, no `mix run`, `lab/data/` gone, and ports **4000**, **5001**, **8080**, **9000**, **9123**, and **24567** clear. Root-owned container files are removed in Docker when the host user cannot delete them.

The lower-level commands are still `lab-up.sh`, `identity-publish.sh`, `node-up.sh`, and `lab-down.sh`.

## Status

```bash
./scripts/lab-status.sh
```

## Endpoints (localhost only)

| Service | URL |
|---------|-----|
| IPFS API | http://127.0.0.1:5001 |
| IPFS Gateway | http://127.0.0.1:8080 |
| IOTA JSON-RPC | http://127.0.0.1:9000 |
| IOTA faucet | http://127.0.0.1:9123 |

## Privacy / isolation

- **IPFS:** per-instance `lab/data/swarm.key` + `LIBP2P_FORCE_PNET=1`, bootstrap peers cleared, swarm port not published to the host. Does not join the public IPFS network.
- **IOTA:** `iota-localnet` with genesis under `lab/data/iota` — not mainnet/testnet. RPC/faucet bound for this compose project only; host publish is `127.0.0.1`.
- Compose project name: `sep26_concrete_lab`.

`lab/data/` is gitignored. `lab/cache/` (Identity Move sources) and `lab/run/` (session pids and logs) are gitignored too.

## OTP / Godot

Not started by `lab-up`. Talk to localhost ports when added.

```bash
./scripts/node-up.sh
./scripts/godot-up.sh
```

### Phase 2 — Identity package

After lab IOTA is healthy, publish the Identity Move package once per genesis:

```bash
./scripts/identity-publish.sh   # → lab/data/iota/identity_pkg_id.txt
./scripts/identity-smoke.sh     # with node-up running
```

See [docs/08-phase2-iota-identity.md](../docs/08-phase2-iota-identity.md) and [ADR 0007](../docs/decisions/0007-iota-did-head-authority.md) (Identity as name → head authority; OTP executor).
