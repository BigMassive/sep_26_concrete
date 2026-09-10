#!/usr/bin/env python3
"""Lab sidecar: external-issuer stand-in for ADR 0008 (not seL4 vault).

FIPS 202 SHAKE256 master seed; HKDF-SHA3-256 → 32-byte ML-DSA-87 seed at index 0.
Prints public key only. Seed stays in CONCRETE_VAULT_DIR.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import secrets
import sys
from pathlib import Path

try:
    from dilithium_py.ml_dsa import ML_DSA_87
except ImportError:
    print(
        "missing dilithium-py — create lab/.venv and pip install -r scripts/requirements-user-identity.txt",
        file=sys.stderr,
    )
    raise SystemExit(2)

INFO_PREFIX = b"sep26.user.mldsa87.index"
SALT = b"sep26.user.master"
MASTER_LEN = 64
MLDSA_SEED_LEN = 32


def hkdf_sha3_256(ikm: bytes, salt: bytes, info: bytes, length: int) -> bytes:
    prk = hmac.new(salt, ikm, hashlib.sha3_256).digest()
    okm = b""
    block = b""
    counter = 1
    while len(okm) < length:
        block = hmac.new(prk, block + info + bytes([counter]), hashlib.sha3_256).digest()
        okm += block
        counter += 1
    return okm[:length]


def vault_dir() -> Path:
    env = os.environ.get("CONCRETE_VAULT_DIR")
    if env:
        return Path(env)
    root = Path(__file__).resolve().parent.parent
    return root / "lab" / "data" / "vault"


def user_path(vdir: Path, username: str) -> Path:
    safe = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in username)
    return vdir / f"{safe}.json"


def encode_id(pk: bytes) -> str:
    import base64

    return "mldsa87:" + base64.urlsafe_b64encode(pk).decode("ascii").rstrip("=")


def derive_index0(master: bytes) -> tuple[bytes, bytes]:
    info = INFO_PREFIX + (0).to_bytes(4, "big")
    seed = hkdf_sha3_256(master, SALT, info, MLDSA_SEED_LEN)
    if hasattr(ML_DSA_87, "key_derive"):
        pk, sk = ML_DSA_87.key_derive(seed)
    else:
        raise SystemExit("dilithium-py ML_DSA_87.key_derive missing — need dilithium-py>=1.1.0")
    return pk, sk


def onboard(username: str) -> dict:
    vdir = vault_dir()
    vdir.mkdir(parents=True, exist_ok=True)
    path = user_path(vdir, username)
    if path.exists():
        rec = json.loads(path.read_text())
        master = bytes.fromhex(rec["master_seed_hex"])
        pk, _sk = derive_index0(master)
        return {
            "username": rec.get("username", username),
            "index": 0,
            "id": encode_id(pk),
            "public_key": encode_id(pk),
        }

    raw = secrets.token_bytes(MASTER_LEN)
    master = hashlib.shake_256(raw).digest(MASTER_LEN)
    pk, _sk = derive_index0(master)
    path.write_text(
        json.dumps(
            {
                "username": username,
                "index0": 0,
                "master_seed_hex": master.hex(),
                "note": "lab vault stand-in (ADR 0008); product custody is seL4 volatile; never send to Godot",
            },
            indent=2,
        )
        + "\n"
    )
    os.chmod(path, 0o600)
    return {
        "username": username,
        "index": 0,
        "id": encode_id(pk),
        "public_key": encode_id(pk),
    }


def main() -> None:
    p = argparse.ArgumentParser(description="ADR 0008 user-identity sidecar")
    p.add_argument("cmd", choices=["onboard"])
    p.add_argument("--username", required=True)
    args = p.parse_args()
    if args.cmd == "onboard":
        out = onboard(args.username)
        json.dump(out, sys.stdout)
        sys.stdout.write("\n")


if __name__ == "__main__":
    main()
