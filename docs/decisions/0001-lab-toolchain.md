# ADR 0001: Lab toolchain — Docker Compose + Godot (OSS)

- Status: accepted
- Date: 2026-09-08

## Context

`sep_26_concrete` should be easy for others to clone and run without paid tooling (Cursor is optional for the owner). The UI direction is **Godot**. Prior labs used Docker Compose for IPFS/IOTA-style services; product topology must not be confused with that harness.

Constraints:

- Required tools for contributors: **open source**, no licence cost.
- Prefer a **dockerised** lab so service versions are pinned and reproducible.
- Godot is a GUI editor; running the full editor *inside* Docker is fragile across Linux/macOS/Windows (display forwarding).

## Decision

1. **Lab packaging:** Docker Compose is the default way to bring up backend/lab services for this prototype. Compose files and containers are labelled as **lab harness**, not product node architecture (see [03-architecture.md](../03-architecture.md)).
2. **UI:** **Godot** (MIT) is the planned thin UI veneer for the vertical slice demos.
3. **Godot installation (v1):** Contributors install the **Godot editor on the host** (official OSS build / distro package). The Godot *project* lives in this repo and talks to services on localhost ports published by Compose. Revisit a containerised Godot/editor desktop only if host install proves a barrier.
4. **Required toolchain (no cost):** Git, Docker Engine + Compose, Godot Editor, and whatever OSS language toolchain the runtime ADR selects. Optional: VSCodium, Neovim, etc. **Cursor is not required.**
5. **Clone-and-go bar:** README documents a short path: clone → install Godot → `docker compose up` → open the Godot project. No proprietary accounts required for that path.
6. **Do not** revive Mar_26’s multi-container-per-node habit by default; add Compose services only when the frozen slice names a need.

## Consequences

- Open decision “UI technology” is resolved toward Godot; runtime language remains open.
- Docs and demos must keep “harness” wording when supervisors or privileged containers appear.
- CI (when added) can use Godot headless / export templates (OSS) without the GUI.
- Contributors on locked-down machines without Docker will need an alternate path later (not defined yet).
