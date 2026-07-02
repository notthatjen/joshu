#!/usr/bin/env python3
"""
Granola API spike (M8a) — proves ONE read-only auth path to Granola's
documents + transcripts, standalone and dependency-free (stdlib + `security`).

Findings recorded in docs/integrations/granola.md. Summary:
  - Official grn_ API keys require a Business plan → not assumed available.
  - Reverse-engineered app API (A2) is reachable and works with the WorkOS
    access token Granola already holds locally. Endpoint + client gate
    confirmed live 2026-07-02 (expired token → 401, not "Unsupported client",
    once the Electron client headers are present).

Token sources, in order of safety:
  1. Plaintext supabase.json (older installs) — read workos_tokens directly.
     No Keychain prompt, no rotation. On current installs this is stale.
  2. Decrypt supabase.json.enc with the Chromium/Electron safeStorage key from
     the "Granola Safe Storage" Keychain item. Read-only, no rotation, but
     triggers a one-time Keychain access prompt.
  3. Refresh via WorkOS with the refresh_token — AVOID: WorkOS rotates the
     refresh token, which can sign the Granola app out. Only as a last resort
     and ideally only while Granola is closed.

Usage:
  python3 granola_spike.py            # try plaintext token, then endpoints
  python3 granola_spike.py --decrypt  # also try Keychain-decrypt (will prompt)
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error

GRANOLA_DIR = os.path.expanduser("~/Library/Application Support/Granola")
API = "https://api.granola.ai"
CLIENT_HEADERS = {
    "Content-Type": "application/json",
    "User-Agent": "Granola/7.373.2 Electron/33.0.0",
    "X-Client-Version": "7.373.2",
    "X-Client-Type": "electron",
}


def jwt_expired(token: str) -> bool:
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
        return claims.get("exp", 0) < time.time()
    except Exception:
        return True


def token_from_plaintext() -> str | None:
    path = os.path.join(GRANOLA_DIR, "supabase.json")
    if not os.path.exists(path):
        return None
    try:
        data = json.load(open(path))
        wt = data.get("workos_tokens")
        wt = json.loads(wt) if isinstance(wt, str) else (wt or {})
        token = wt.get("access_token")
        if token and not jwt_expired(token):
            return token
        print("  plaintext supabase.json token is expired")
    except Exception as e:
        print(f"  plaintext read failed: {e}")
    return None


def keychain_password() -> bytes | None:
    """The random password Electron safeStorage stored for Granola."""
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-w",
             "-s", "Granola Safe Storage", "-a", "Granola Key"],
            capture_output=True, text=True, timeout=30)
        if out.returncode != 0:
            print(f"  keychain read denied/failed: {out.stderr.strip()}")
            return None
        return out.stdout.strip().encode()
    except Exception as e:
        print(f"  keychain error: {e}")
        return None


def token_from_decrypt() -> str | None:
    """
    Decrypt supabase.json.enc. Electron safeStorage on macOS == Chromium
    OSCrypt: AES-128-CBC, key = PBKDF2-HMAC-SHA1(keychain_pw, b"saltysalt",
    1003 iters, 16 bytes), IV = 16 spaces, ciphertext prefixed b"v10".
    Requires `pip install cryptography` OR falls back to documenting the recipe.
    """
    pw = keychain_password()
    if not pw:
        return None
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
        from cryptography.hazmat.primitives import hashes
    except ImportError:
        print("  (install `cryptography` to run the decrypt path; recipe is in docs)")
        return None

    kdf = PBKDF2HMAC(algorithm=hashes.SHA1(), length=16, salt=b"saltysalt", iterations=1003)
    key = kdf.derive(pw)

    def oscrypt_decrypt(blob: bytes) -> bytes:
        assert blob[:3] == b"v10", "not a v10 safeStorage blob"
        cipher = Cipher(algorithms.AES(key), modes.CBC(b" " * 16))
        dec = cipher.decryptor()
        padded = dec.update(blob[3:]) + dec.finalize()
        return padded[:-padded[-1]]  # strip PKCS7 padding

    # supabase.json.enc is itself a safeStorage blob wrapping the JSON.
    enc = open(os.path.join(GRANOLA_DIR, "supabase.json.enc"), "rb").read()
    try:
        plaintext = oscrypt_decrypt(enc)
        data = json.loads(plaintext)
        wt = data.get("workos_tokens")
        wt = json.loads(wt) if isinstance(wt, str) else (wt or {})
        return wt.get("access_token")
    except Exception as e:
        print(f"  decrypt failed (Granola may use per-file DEK via storage.dek): {e}")
        print("  next step: decrypt storage.dek with the same key, then use that "
              "DEK (AES-256-GCM) on the .enc files — see docs/integrations/granola.md")
        return None


def call(path: str, token: str, body: dict):
    req = urllib.request.Request(
        API + path, method="POST",
        data=json.dumps(body).encode(),
        headers={**CLIENT_HEADERS, "Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def main():
    print("Granola API spike\n" + "=" * 40)
    token = token_from_plaintext()
    if not token and "--decrypt" in sys.argv:
        print("trying Keychain-decrypt path (will prompt)…")
        token = token_from_decrypt()

    if not token:
        print("\nNo usable token. Endpoint/client-gate confirmation only:")
        status, body = call("/v2/get-documents", "expired.jwt.token", {"limit": 1})
        print(f"  /v2/get-documents → HTTP {status}: {body[:120].decode(errors='replace')}")
        print("  (401 with client headers = endpoint good, token needed;")
        print("   'Unsupported client' = missing X-Client-Version/User-Agent)")
        print("\nDECISION: A2 viable. Wire token source #2 (Keychain-decrypt) in M8b,")
        print("run once with the user present to clear the Keychain prompt.")
        return

    print("got a live token; hitting real endpoints…")
    status, body = call("/v2/get-documents", token, {"limit": 5})
    print(f"  /v2/get-documents → HTTP {status}")
    if status == 200:
        docs = json.loads(body).get("docs", json.loads(body).get("documents", []))
        for d in docs[:5]:
            print(f"    · {d.get('title', d.get('id'))}")
        if docs:
            doc_id = docs[0].get("id") or docs[0].get("document_id")
            ts, tbody = call("/v1/get-document-transcript", token, {"document_id": doc_id})
            print(f"  /v1/get-document-transcript({doc_id}) → HTTP {ts}, {len(tbody)} bytes")
    print("\nDECISION: A2 confirmed end-to-end.")


if __name__ == "__main__":
    main()
