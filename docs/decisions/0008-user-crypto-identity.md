# ADR 0008: User cryptographic identity — external seed, ML-DSA-87 public key as truth

- Status: **accepted**
- Date: 2026-09-10
- Relates: [ADR 0005](0005-bootstrap-capability.md) (bootstrap cap = anything/everywhere; gates **data** access), [ADR 0004](0004-world-state-supervisor.md) (Godot models people; OTP checks), [ADR 0007](0007-iota-did-head-authority.md) (`did:iota:…` **ContentHead** is **information** name → head; user-directory records are **data** that may still be named with `did:iota:…`)

## Context

Today a lab principal is an OTP-minted string (`principal-…`) plus `display_name`. Capability checks and commit authorship use that string. Username is not cryptographic identity.

The programme map already specifies: issuance **outside** the system; **FIPS 202** master seed; **HKDF** with an index (`0` = main identity; `1..n` = pseudonyms); **ML-DSA-87** keypairs; custody in an **seL4 vault** (volatile) so users never see raw keys ([07-programme-map.md](../07-programme-map.md)).

Owner direction (2026-09-10): model those **external** users in **Godot** and in an **OTP sidecar**; onboarding notionally issues the master seed once; **current code should treat the index-0 public key as truth**; new users publish **public key / username** pairs on **IPFS**, named with an **IOTA DID**, as **data** (not information).

The **person** is the ML-DSA-87 public key. That is not the same object as an info-object DID. A directory **record** may still have a `did:iota:…` as its durable name.

## Decision

1. **Issuance is outside CONCRETE.** The node does not invent a user’s master seed. Lab may *simulate* an external issuer (sidecar) so Godot/OTP can run without a bank/dongle.
2. **Master seed** is FIPS 202 material, issued **once** at onboarding. Product custody is a **seL4 vault in volatile memory**. Lab stand-in: sidecar process, seed not in Godot and not in `bootstrap.json`.
3. **Derivation:** HKDF(master_seed, index) → ML-DSA-87 keypair. **Index 0** is reserved for the user’s main identity. Higher indices are pseudonyms (later).
4. **Truth for “who”:** the **index-0 ML-DSA-87 public key**, encoded as `mldsa87:` plus URL-safe Base64 (no padding) of the public-key bytes. `display_name` / username is an alias, not the principal id. OTP `authorize` and commit `author_principal_id` use that encoding, not `principal-…`.
5. **Directory records are data, not information.** When a user is added, persist `{public_key, username}` on **IPFS** and name that blob with a **`did:iota:…`**. This is **data**: access is gated by **capability** (the bootstrap **anything/everywhere** cap covers it). Do **not** attach information machinery — no commit graph, no content/read/write/links facets, no per-object read/write rights. OTP may index DID → CID; the pair is not an info object and is not ADR 0007 head authority for plaques.
6. **Godot** models people in the physical veneer (avatars, King/Eve) **with** crypto identity (show truncated pubkey). It still talks only to OTP HTTP ([ADR 0004](0004-world-state-supervisor.md)). It must not hold the master seed.
7. **OTP sidecar** (labelled lab, or later seL4 vault) performs seed custody and HKDF/ML-DSA. The node runtime remains executor: cap check, IPFS directory write, HTTP for Godot.
8. **Bootstrap cap (ADR 0005)** stays a membership check until a later ADR moves caps on-ledger. The **holder** becomes the first user’s index-0 public key, not a random `principal-` id. That cap is what **enables access** to user-directory **data** (and other do-anything paths). No extra ACL on the pair.
9. **Users never see raw keys** in the product story. Lab UI may show public keys only.

## Out of this ADR (do not couple)

- seL4 / CHERI / TPM as the real vault (lab sidecar first)
- Signed HTTP mutates / challenge–response (pubkey as id can land before signatures)
- Pseudonym indices `1..n`, ML-KEM wrap, remote expunge
- On-ledger caps, ControllerCap = King (still named gap)
- Replacing IOTA Identity for **information** heads, or treating the person’s ML-DSA pubkey as an info-object `did:iota`

## Implementation stages

| Stage | Intent | Status |
|-------|--------|--------|
| **0** | This ADR + backlog/roadmap | done |
| **1** | Sidecar: FIPS 202 seed, HKDF index 0, ML-DSA-87; export pubkey only | done |
| **2** | OTP principals keyed by pubkey; King/Eve onboarding; cap holder = King’s pubkey | done |
| **3** | IPFS **data** `{public_key, username}` + `did:iota` name; access = bootstrap cap only | later |
| **4** | Godot: model external users; plaque/status use pubkey as actor id | later |
| **5** | Optional later: sign mutate requests; vault stand-in closer to seL4 | later |

## Consequences

- Slice beats that send `principal_id` must switch to pubkey encoding once 2 lands.
- Existing `lab/data/node/bootstrap.json` ids become leftovers (migrate or reset lab data).
- Directory records are **data** (DID + IPFS bytes). They are **not** info objects and do not use plaque/advance/facet rights (ADR 0007 still applies to **information**).
- Until stages 3–4 land, directory is not on IPFS yet; Godot still talks :4000 with pubkey as `principal_id`.
