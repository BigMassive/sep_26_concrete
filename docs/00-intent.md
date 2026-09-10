# Intent

## Programme

Project CONCRETE seeks minimal digital foundations that people and organisations can co-adopt: security, data, information, computation, and resource management — with self-determination and teamwork both first-class. The long narrative lives on [BigMassive/CONCRETE](https://github.com/BigMassive/CONCRETE).

## This prototype

`sep_26_concrete` is the next **working mock** after `mar_26_concrete`. It exists to:

1. Express foundation ideas in an **implementable** architecture (not only site prose).
2. Prove a **single vertical slice** end-to-end before growing platform surface.
3. Stay disposable: explore, learn, discard what does not pay rent.

## Principles for this repo

1. **Backend is ground truth** — any UI is a thin veneer. For **name → head**, that backend is **IOTA Identity** plus **IPFS** content ([ADR 0007](decisions/0007-iota-did-head-authority.md)); OTP orchestrates and is not a second ledger for the head.
2. **Docs before platform** — no four-container-per-node default until the slice needs it.
3. **One capability path** — at least one real “nothing without authority” check on the critical path, or call the capability story paper.
4. **Small vocabulary, shared meanings** — see [02-vocabulary.md](02-vocabulary.md).
5. **Link, don’t fork the site** — vision and socio-technical breadth stay on BigMassive/CONCRETE; this repo holds decision density for *this* iteration.

## Success for the docs phase

- Residues from Mar_26 are explicit (keep / drop).
- Vertical slice has acceptance criteria.
- New concepts are triaged: slice / stub / paper.
- Out of scope is written down so it is not silently re-imported.
