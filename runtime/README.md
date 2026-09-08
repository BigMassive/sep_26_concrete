# Node runtime (Elixir / OTP)

Lab **ground truth** for `sep_26_concrete` — not Phoenix, not Godot. See [ADR 0003](../docs/decisions/0003-runtime-beam.md), [ADR 0005](../docs/decisions/0005-bootstrap-capability.md).

## Beat 1 — bootstrap

On first start (empty `lab/data/node/`), creates **node-1**, principal **King**, and the **bootstrap/do-anything** capability held by King.

```bash
# Optional: lab IPFS/IOTA (needed from beat 2+)
./scripts/lab-up.sh

./scripts/node-up.sh          # terminal A — http://127.0.0.1:4000
./scripts/beat1-smoke.sh      # terminal B
```

## HTTP

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Liveness |
| GET | `/v1/bootstrap` | Node, King, bootstrap cap, principals |
| POST | `/v1/principals` | `{"display_name":"Eve"}` — extra user **without** bootstrap cap |
| POST | `/v1/capability/check` | `{"principal_id":"…","action":"mutate"}` — allow/deny |

State file: `lab/data/node/bootstrap.json` (gitignored under `lab/data/`).
