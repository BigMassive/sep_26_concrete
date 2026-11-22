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

Before each test:

1. Stop anything still running from a previous run (Godot, the OTP `mix`/`beam` process, lab containers).
2. `./scripts/lab-down.sh --wipe` so `lab/data/` is gone (IPFS swarm, IOTA genesis, identity package, node, vault).
3. `./scripts/lab-up.sh`
4. `./scripts/identity-publish.sh` — a new IOTA genesis needs a new package.
5. `./scripts/node-up.sh` on that empty data dir.
6. Then the test (smoke script and/or Godot).

After each test:

1. Stop Godot.
2. Stop the OTP process started by `./scripts/node-up.sh`.
3. `./scripts/lab-down.sh --wipe`
4. Confirm nothing is left: no `sep26_lab_*` containers, no Godot, no `mix run`, and ports **4000**, **5001**, **8080**, **9000**, **9123**, and **24567** are clear.

Status:

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

`lab/data/` is gitignored.

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
