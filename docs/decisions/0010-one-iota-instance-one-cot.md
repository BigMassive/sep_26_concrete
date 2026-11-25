# ADR 0010: One IOTA instance, one Circle of Trust

- Status: accepted
- Date: 2026-11-25
- Relates: [ADR 0002](0002-ipfs-iota-did.md) (this CoT’s IOTA instance), [ADR 0007](0007-iota-did-head-authority.md) (name → head on that instance), [11](../11-helen-alice-cot-beats.md) (**G**)

## Context

[ADR 0002](0002-ipfs-iota-did.md) makes a Circle of Trust’s IOTA instance that CoT’s ledger. Names this lab publishes are `did:iota:<chain id>:<identity object id>`. The chain id is `iota_getChainIdentifier` for that genesis, so two instances do not share names. ADR 0002 also says that when the instance itself needs a name, that name is a DID, not only the chain id.

**G** is the CoT’s first-among-equals information DID and the start of the walk to D1–D5. The lab remembers G’s DID in the OTP CoT index. The chain does not yet refuse a second root on the same localnet.

The programme has many CoTs, and some may sit inside others. That plurality is many instances. It is not several CoTs on one genesis.

## Decision

1. **One IOTA instance holds one Circle of Trust.** Another CoT is another IOTA instance. A node that joins an existing CoT uses that CoT’s instance. It does not open a new one.
2. **The instance is uniquely identified by its chain id** (`iota_getChainIdentifier`). Object names on it are `did:iota:<chain id>:<identity object id>`. When a name for the instance itself is required, it is a DID ([ADR 0002](0002-ipfs-iota-did.md)), not a second chain id. The lab records the chain id. It does not yet publish that instance DID.
3. **G is the single root of that CoT on that instance.** The same instance still holds the CoT’s other information and data names (D1–D5, workspaces, later objects). Those names are not further CoTs.
4. **Genesis creates that root once.** A later attempt to create another root on the same instance fails. A member finds G by dialing their instance and resolving its root. Membership lists are not the lookup key. D1, D2, and capabilities still decide who may act after G is resolved.
5. **The root is visible to any caller who can reach the instance.** Seeing G is not admission. A capability check is what admits a principal.
6. **An embedded CoT is another instance**, named from the outer CoT by a DID that refers to the inner instance. It is not a second G on the outer chain.

## Consequences

- OTP’s `g_did` index stays a cache until genesis enforces a single on-chain root. This ADR does not delete that cache and does not add the refusal.
- Helen → Alice stays one node on one instance. A later box of this CoT uses this same instance and does not write the remote D2 itself ([11](../11-helen-alice-cot-beats.md)).
- “Many CoTs” in the programme map means many instances.
- [ADR 0007](0007-iota-did-head-authority.md) is unchanged: heads on this instance remain Identity `ContentHead` values. The frozen Phase 1 acceptance list is unchanged.
