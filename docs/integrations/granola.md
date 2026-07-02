# Granola integration — spike findings (M8a)

Date: 2026-07-02. Machine: Granola app 7.373.2.

## Decision: A2 (reverse-engineered app API), with the Keychain-decrypt token source

The Meeting widget will talk to Granola's app API using the WorkOS access
token Granola already stores locally. This is behind the `MeetingSource`
protocol, so A1 (official API) can replace it later without touching widget
code.

## What was verified live

- **Endpoint reachable:** `POST https://api.granola.ai/v2/get-documents`.
- **Client gate:** without Electron client headers the API returns
  `200 {"message":"Unsupported client"}`. With them it proceeds to auth. Required headers:
  ```
  Content-Type: application/json
  User-Agent: Granola/<ver> Electron/<ver>
  X-Client-Version: <ver>          # e.g. 7.373.2
  X-Client-Type: electron
  Authorization: Bearer <workos access_token>
  ```
- **Auth confirmed:** with client headers and an *expired* token the API
  returns `401 {"message":"Unauthorized"}` (not the client error) — proving
  the request shape is correct and only a valid token is missing.
- Transcript endpoint (per community reverse-engineering, to confirm with a
  live token in M8b): `POST /v1/get-document-transcript` with
  `{"document_id": "<id>"}`.

## Token sources (safety order)

1. **Plaintext `supabase.json`** — older installs kept `workos_tokens`
   (`access_token` + `refresh_token`) in cleartext. On this machine it exists
   but is **stale** (token expired 2026-05-13). No Keychain prompt, no
   rotation. Use if present and unexpired.
2. **Decrypt `supabase.json.enc`** (chosen path). Current installs keep live
   tokens encrypted. This is Electron `safeStorage` == Chromium OSCrypt:
   - Keychain item: service `Granola Safe Storage`, account `Granola Key`
     (confirmed present). Reading it triggers a **one-time** Keychain access
     prompt — run once with the user present, then macOS remembers the grant.
   - Key derivation: `PBKDF2-HMAC-SHA1(keychain_password, salt="saltysalt",
     iterations=1003, keylen=16)`.
   - Blob format: `b"v10"` prefix + AES-128-CBC, IV = 16 spaces, PKCS7 pad.
   - `storage.dek` (51 bytes, `v10…`) is likely a wrapped per-file DEK: if
     decrypting `supabase.json.enc` directly with the OSCrypt key fails,
     decrypt `storage.dek` first to get the real DEK, then use it
     (AES-256-GCM) on the `.enc` files. The spike script handles the direct
     case and prints this next step otherwise.
   - Read-only; no rotation.
3. **WorkOS refresh** (`/user_management/authenticate` with the
   `refresh_token`) — **avoid**. WorkOS rotates the refresh token, which can
   sign the Granola app out. Last resort, ideally only while Granola is closed.

## Do NOT

- Build on the old plaintext `cache-v3.json` — it no longer exists; the cache
  is `cache-v6.json.enc` (encrypted) plus a near-empty `cache-v6.json` stub.
- Refresh tokens speculatively (rotation hazard above).

## Spike artifact

`Scripts/granola-spike/granola_spike.py` — standalone, stdlib-only for the
endpoint/plaintext paths; the decrypt path needs `cryptography`
(`--decrypt` flag). Re-run before starting M8b to catch Granola app updates.

## Go / no-go for M8b

**GO.** A2 is viable end-to-end pending one interactive step: run the spike
with `--decrypt` once while the user is present to clear the Keychain prompt
and confirm the `.enc` → token → `get-documents` → `get-document-transcript`
chain against live data. If the decrypt turns out to require the `storage.dek`
two-step and that proves brittle, fall back to A1 (official API, needs a
Business-plan `grn_` key) or, failing everything, a manual paste-transcript
mode.
