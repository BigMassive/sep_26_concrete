#!/usr/bin/env python3
"""Pack/unpack IOTA DID method v2 state metadata (JSON, no compression).

Lab harness helper — matches identity.rs StateMetadataDocument packing:
  [b'DID'][version u8=1][encoding u8=0][payload_len u16le][json]

Payload uses placeholder DID did:0:0. ContentHead serviceEndpoint is ipfs://<cid>.
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone

MARKER = b"DID"
VERSION = 1
ENCODING_JSON = 0


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def pack(head_cid: str | None = None, created: str | None = None, updated: str | None = None) -> bytes:
    ts = created or _now()
    updated = updated or ts
    doc: dict = {"id": "did:0:0"}
    if head_cid:
        doc["service"] = [
            {
                "id": "did:0:0#head",
                "type": "ContentHead",
                "serviceEndpoint": f"ipfs://{head_cid}",
            }
        ]
    payload = {"doc": doc, "meta": {"created": ts, "updated": updated}}
    raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    if len(raw) > 0xFFFF:
        raise SystemExit("document too large for u16 length prefix")
    return MARKER + bytes([VERSION, ENCODING_JSON]) + len(raw).to_bytes(2, "little") + raw


def unpack(packed: bytes) -> dict:
    if packed[:3] != MARKER:
        raise ValueError("missing DID marker")
    if len(packed) < 7:
        raise ValueError("truncated header")
    version, encoding = packed[3], packed[4]
    if version != VERSION or encoding != ENCODING_JSON:
        raise ValueError(f"unsupported version/encoding {version}/{encoding}")
    n = int.from_bytes(packed[5:7], "little")
    blob = packed[7 : 7 + n]
    if len(blob) != n:
        raise ValueError("truncated payload")
    return json.loads(blob)


def head_cid_of(payload: dict) -> str | None:
    for svc in (payload.get("doc") or {}).get("service") or []:
        if svc.get("type") != "ContentHead":
            continue
        ep = svc.get("serviceEndpoint") or ""
        if isinstance(ep, str) and ep.startswith("ipfs://"):
            return ep[len("ipfs://") :]
        if isinstance(ep, str) and ep:
            return ep
    return None


def _bytes_from_hex(s: str) -> bytes:
    s = s.strip()
    if s.startswith("0x") or s.startswith("0X"):
        s = s[2:]
    return bytes.fromhex(s)


def hex_to_vec_lit(hex_str: str) -> str:
    packed = _bytes_from_hex(hex_str)
    return "[" + ",".join(str(b) for b in packed) + "]"


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    pk = sub.add_parser("pack", help="print lowercase hex of packed DID document")
    pk.add_argument("--head-cid", default=None)
    pk.add_argument("--created", default=None)
    pk.add_argument("--updated", default=None)

    un = sub.add_parser("unpack", help="decode packed hex to JSON")
    un.add_argument("hex")

    vec = sub.add_parser("vec", help="print PTB vector<u8> literal from packed hex")
    vec.add_argument("hex")

    args = p.parse_args()
    if args.cmd == "pack":
        packed = pack(head_cid=args.head_cid, created=args.created, updated=args.updated)
        sys.stdout.write(packed.hex())
        return
    if args.cmd == "vec":
        sys.stdout.write(hex_to_vec_lit(args.hex))
        return
    payload = unpack(_bytes_from_hex(args.hex))
    json.dump(
        {"payload": payload, "head_cid": head_cid_of(payload)},
        sys.stdout,
        indent=2,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
