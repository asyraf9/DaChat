# Contract: `dachat-keyservice` HTTP API (v1)

**Base URL**: `https://<main-domain>/v1`. The domain is built into the app per flavour (FR-002).

The client pins the server's TLS key (SPKI pins, R7). TLS 1.3 only. All bodies are JSON (UTF-8).
Binary fields are base64url without padding.

**Authentication**: endpoints marked 🔐 require `Authorization: DaChat <session_token>`. A
`session_token` is obtained from `POST /auth/verify` and is valid for 5 minutes. It is the same token
used for XMPP SASL (R7). Every master-identity signature is a **dual signature**:

```json
{ "ed": "<XEd25519 signature, 64 B>", "pq": "<ML-DSA-87 signature, 4627 B>" }
```

The server rejects the request unless **both** signatures verify (R2.4a).

**Errors**: `{ "code": "<opaque_code>" }` only. There is never any detail, echo of input, or stack
trace (C3). Clients map `code` to an `AppFailure` subtype.

**Rate limits**: per source IP, held in memory only, never logged with the IP (C5):

- 10 registrations per hour;
- 60 challenges per minute;
- 30 link redemptions per hour.

**Logging**: the server logs neither IP addresses nor addresses (the account identifiers) nor
request bodies. Access logs carry route, status, and latency only.

---

## Registration & auth

### `POST /accounts` — register (idempotent upsert, R5.6)

The request:

```json
{
  "x25519_pub": "…33B…", "mldsa_pub": "…2592B…",
  "nonce": "…from /auth/challenge…",
  "device_epoch": 1,
  "sig": { "ed": "…", "pq": "…" }
}
```

The signature is over `"dachat/v1/register" ‖ domain ‖ nonce ‖ x25519_pub ‖ mldsa_pub ‖ u32be(device_epoch)`.
The server derives `address` (R7) and doesn't trust a client-supplied one.

| Status | Body / code | Meaning |
|---|---|---|
| 201 / 200 | `{ "address": "…", "device_epoch": 1 }` | Created, or already existed with these keys (an idempotent repeat). |
| 409 | `epoch_conflict` | An epoch at or below the current one was presented by a different registration attempt. |
| 400 | `bad_signature` · `bad_key` | |

`device_epoch > current` (restore, R8) is accepted only with a valid dual signature. It increments
the epoch, which supersedes the older device.

### `POST /auth/challenge`

The request is `{ "address": "…" }`. The response is
`200 { "nonce": "…32B…", "expires_in": 60 }`. Unknown addresses still get a nonce, so the endpoint
does not reveal whether an account exists.

### `POST /auth/verify`

The request is `{ "address", "nonce", "device_epoch", "sig" }`. The signature is over
`"dachat/v1/auth" ‖ domain ‖ nonce ‖ u32be(device_epoch)`.

| Status | Body / code |
|---|---|
| 200 | `{ "session_token": "…", "expires_in": 300, "xmpp_jid": "<address>@<domain>" }` |
| 409 | `superseded`: the presented epoch is older than the account's. The client wipes (R8, FR-029). |
| 401 | `bad_signature` · `nonce_expired` |

---

## Prekeys (RQSM §5.6)

### `PUT /prekeys` 🔐 — publish or replace the signed prekey, Kyber prekey, and one-time pools

The request:

```json
{
  "signed_prekey":  { "id": 1, "public": "…", "sig": "<libsignal XEd25519 sig>", "pq_cosig": "<ML-DSA>" },
  "kyber_prekey":   { "id": 1, "public": "…1568B…", "sig": "…", "pq_cosig": "…" },
  "one_time_ec":    [ { "id": 101, "public": "…" } ],
  "one_time_kyber": [ { "id": 201, "public": "…", "sig": "…", "pq_cosig": "…" } ]
}
```

Each `pq_cosig` is ML-DSA over `"dachat/v1/prekey" ‖ kind ‖ u32be(id) ‖ public`. The server verifies
every signature before storing anything.

The response is `204`. The body is built natively and passed to Dio as opaque bytes (C9). The Dart
side has no DTO for it.

### `GET /prekeys/{address}` 🔐 — fetch a bundle (consumes one-time prekeys)

The response:

```json
{
  "identity": { "x25519_pub": "…", "mldsa_pub": "…" },
  "registration_id": 12345, "device_id": 1,
  "signed_prekey": { … }, "kyber_prekey": { … },
  "one_time_ec": { … } | null,  "one_time_kyber": { … } | null
}
```

- The one-time entries are `null` when the pool is exhausted. The session still establishes, with
  reduced first-message protection (edge case).
- The **client** rejects the bundle if `identity` differs from the identity pinned at connection, or
  if any `pq_cosig` fails (R11, key mismatch).
- `404 not_found` returns the same timing as a hit.

### `GET /prekeys/count` 🔐

The response is `{ "one_time_ec": n, "one_time_kyber": m }`. The client replenishes to 100 of each
when a pool falls below 20.

---

## Connection links (R9, FR-009–FR-012)

### `POST /links` 🔐 — register a link

- **Request**: `{ "link_id": "…16B…" }`. The client generates the id. The server stores
  `expires_at = now + 24h`.
- **Response**: `201 { "expires_at": "RFC3339" }`.
- **Errors**: `409 duplicate_id`, after which the client regenerates the id.

### `DELETE /links/{link_id}` 🔐 — revoke (creator only)

- **Response**: `204`.
- **Errors**: `404` if the link is not the caller's. `409 not_revocable` if it is already terminal.

### `POST /links/{link_id}/redeem` 🔐 — reserve for the caller (atomic, single use)

| Status | Body / code |
|---|---|
| 200 | `{ "creator_address": "…", "expires_at": "…" }` |
| 410 | `used` · `expired` · `revoked` · `exhausted` |
| 404 | `not_found` (same timing as a hit) |
| 409 | `own_link` (FR edge case: redeeming your own link) |

The server enforces the single-use transition with one statement:
`UPDATE links SET status='reserved', reserved_by=$caller WHERE link_id=$id AND status='active' AND expires_at>now() RETURNING …`.
Exactly one of N concurrent redeemers succeeds (SC-005). A redeemer that is blocked by the creator
still reserves the link. Their hello is then silently dropped by Prosody (R18).

### `POST /links/{link_id}/resolve` 🔐 — creator records the outcome

- **Request**: `{ "outcome": "connected" | "exhausted" }`.
- **Response**: `204`. After this, the link is terminal.
- **Housekeeping**: a link left `reserved` past `expires_at` becomes `expired`.

### `GET /links` 🔐 — the creator's own links with statuses (for the link list view)

---

## Contact backup (R13, FR-045)

### `GET /backup` 🔐

- **Response**: `200 { "counter": n, "blob": "…" }`.
- **Errors**: `404 not_found`, which means restore proceeds with identity only (edge case).

### `PUT /backup` 🔐

- **Request**: `{ "expected_counter": n, "counter": n+1, "blob": "…" }`. The blob is padded to a
  4 KiB bucket, and its maximum size is 1 MiB.
- **Response**: `204`.
- **Errors**:
  - `409 counter_conflict`: the client re-fetches, merges (its local state wins, because it is the
    single active device), and retries.
  - `413 too_large`.

---

## Push (iOS only, R15)

### `PUT /push/apns` 🔐

The request is `{ "token": "…", "environment": "production" | "sandbox" }`, and the response is
`204`. Prosody's `mod_cloud_notify` calls the internal `POST /internal/push/{address}`, which is not
exposed publicly. That sends an APNs alert with the fixed localised key `NEW_ACTIVITY` and no other
fields, coalesced to at most one per 60 s.

### `DELETE /push/apns` 🔐

The response is `204`. It is called on removal and on wipe.

---

## Account removal hook

### `DELETE /session` 🔐

This ends the XMPP session and unregisters push. It is called by "Remove from this device" (FR-030).
**It does not delete the account or the backup**: the identity can be restored with the phrase, and
FR-030 keeps the backup.
