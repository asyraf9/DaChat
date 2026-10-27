# Data Model: Secure Direct Messaging (Main Server)

**Feature**: `001-secure-direct-messaging` · **Date**: 2026-10-27 · **Research**: [research.md](./research.md)

This document defines the domain model (pure Dart, `lib/features/*/domain/`), where each item is
persisted (native core stores, R5), and what the server holds.

Throughout:

- "Native-only" means the value never crosses into Dart.
- Domain entities are `freezed` unless marked **[C1 manual]**.
- No domain entity holds private key material. Public keys appear only as opaque `PublicIdentity`
  value objects.

---

## 1. Value objects (shared contract, `lib/core/domain/`)

These are shared across bounded contexts. They are pure Dart and `freezed` (value equality).

| Value object | Fields | Validation |
|---|---|---|
| `AccountAddress` | `localpart: String` | Exactly 26 chars of `[a-z2-7]` (base32 lower). Derived in native code, never user-entered (R7). |
| `PublicIdentity` | `x25519: Uint8List(33)`, `mldsaHash: Uint8List(32)`, `mldsa: Uint8List?(2592)` | Lengths exact. `mldsa`, when present, must hash to `mldsaHash` (checked natively). Public material only. `toString()` prints the length only. |
| `DisplayName` | `value: String` | Trimmed, 1–64 Unicode grapheme clusters, no control characters. NFC-normalised. |
| `SafetyCode` | `digits: String(60)`, `scannable: Uint8List(65)` | 60 decimal digits. Shown as 12 groups of 5. `scannable` = `version ‖ fp_local ‖ fp_remote`. |
| `MessageText` | `value: String` | 1–4,096 UTF-16 code units after trimming. Not blank (spec assumption). |
| `CodeWord` | `value: String` | 1–64 characters. Compared case-insensitively after NFKC normalisation and whitespace collapse. Never persisted after a link is resolved. |

`AccountAddress`, `PublicIdentity`, and `SafetyCode` are on the C5/C10 sensitive list. They are never
logged, never put in an `AppFailure`, and never in a domain-event payload. Events carry the opaque
`contactId` instead.

---

## 2. Identity context (`lib/features/identity/`)

### 2.1 `Identity` (aggregate root, entity)

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | Constant `self`. There is one identity per install. |
| `address` | `AccountAddress` | Deterministic from the seed (R7). |
| `publicIdentity` | `PublicIdentity` | Own public keys. |
| `displayName` | `DisplayName?` | Null until it is set during onboarding. |
| `lifecycle` | `IdentityLifecycle` | See state machine below. |
| `keyProtection` | `KeyProtectionLevel` | `hardwareStrongBox` · `hardwareTee` · `secureEnclave` · `osKeyring` · `passphrase`. The last two are disclosed as weaker (FR-003). |
| `createdAt` | `DateTime` | Drives the nudge (R20). |
| `deviceEpoch` | `int` | Single-active-device counter (R8). |

**Native-only, held in `vault.db` with per-record encryption**: the X25519 private key, the ML-DSA-87
seed ξ, the recovery entropy, and the backup key.

**`IdentityLifecycle` state machine**:

```text
            create (keys generated offline)
   none ──────────────────────────────────► pendingRegistration
     │                                          │ registration + prekeys published (R19)
     │ restore(phrase) ─► restoring ──┐         ▼
     │                    (journaled  └──────► active ◄──────┐
     │                     R12)                │  │           │ (no transition back)
     │                                         │  └─ superseded (server 409, R8) ─► wiping ─► none
     └──────────────────────────────── removing (journaled R12) ◄── user confirms removal
                                                │
                                                └────────────────────────────────► none
```

- `restoring` fails cleanly back to `none` if it is interrupted before commit (FR-031).
- `removing` always runs to `none`.
- `superseded` shows the explanation (US3-6) and then wipes everything local. The server backup is
  kept.

### 2.2 `RecoveryStatus` (entity, part of the Identity aggregate)

| Field | Type | Notes |
|---|---|---|
| `phraseConfirmed` | `bool` | True after the re-entry check passes (FR-026). |
| `remindersEnabled` | `bool` | Default true. The user can turn reminders off. |
| `lastNudgeAt` | `DateTime?` | |
| `nextNudgeDueAt` | `DateTime` | `createdAt + 24h`, then `+7d` (R20). |

The phrase itself is native-only. It is revealed to the UI only as `List<String>` (24 words) inside a
`RecoveryPhraseView` **[C1 manual]** with a sentinel `toString()`. That view is held only by the
phrase screen's widget-local state, never in Cubit state, and is wiped (list cleared) on dispose.

### 2.3 `LifecycleOperation` (infrastructure record, `lifecycle.json`)

`{op: restore|remove|wipe, step: int, startedAt}`. It holds no data, so it is safe to leave
unencrypted (R12).

---

## 3. Connections context (`lib/features/connections/`)

### 3.1 `ConnectionLink` (entity, own links only)

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | 128-bit random `link_id`, base64url. |
| `createdAt`, `expiresAt` | `DateTime` | `expiresAt = createdAt + 24h` (FR-009). |
| `requiresCodeWord` | `bool` | The creator chose this explicitly, or it came from the saved personal default (FR-011). |
| `status` | `LinkStatus` | `active` · `reserved` · `connected` · `revoked` · `expired` · `exhausted`. |
| `failedAttempts` | `int` | 0–3. At 3 the link becomes `exhausted` (FR-012). |
| `url` | `Uri` | Includes the fragment. Shown to the creator only while `active`. |

**Native-only**: `link_secret`, and the code word, which is held only until the link is resolved.

```text
active ──redeemed──► reserved ──valid hello (no code word / correct code word)──► connected
  │                     │ wrong code word ×3 ──────────────────────────────────► exhausted
  ├── revoke ──► revoked │ (creator revokes while reserved) ──────────────────► revoked
  └── 24h ────► expired ◄┘ (reservation not completed before expiresAt)
```

Every state except `active` and `reserved` is terminal. The key service holds the authoritative
`active → reserved` transition, which is atomic (SC-005).

### 3.2 `ConnectionPreferences` (value object, personal setting)

| Field | Default (R1.7a) | Notes |
|---|---|---|
| `suggestedMethod` | `qr` | |
| `linkCodeWordDefault` | `unset` | `unset` · `alwaysOn` · `alwaysOff`. While `unset`, the creator **must** choose yes or no for every link (FR-011). Turning confirmation on uses the `codeWord` type, the only type in 001. |

### 3.3 `PairingSession` (entity, transient, QR)

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | |
| `ownNonce` | native-only | Encoded in this device's QR. |
| `scannedPeer` | `PublicIdentity?` + native nonce | Set after this device scans the peer. |
| `peerHelloReceived` | `bool` | Set when the peer's hello quotes `ownNonce`. |
| `expiresAt` | `DateTime` | 10 minutes. The QR is regenerated after that. |

The session completes, producing a **verified** `Contact`, when `scannedPeer != null &&
peerHelloReceived`. Each nonce is used once.

### 3.4 `IncomingConnection` (entity, recipient side of a link before the tap)

This entity is parsed from the link fragment. It holds `linkId`, `creator: PublicIdentity` (hash
only), `requiresCodeWord`, and a safety-code preview. Nothing is sent until the user taps confirm
(FR-009).

---

## 4. Contacts context (`lib/features/contacts/`)

### 4.1 `Contact` (aggregate root, entity)

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | Opaque local UUID. This is what events and routes carry. |
| `address` | `AccountAddress` | |
| `identity` | `PublicIdentity` | Pinned at connection (RQSM §5.6). Bundles must match it. |
| `displayName` | `DisplayName` | Self-asserted by the contact. Updated by their E2EE `profile_update`. |
| `trust` | `TrustState` | `verified` · `notVerified`. |
| `connectedVia` | `ConnectionMethod` | `qr` · `link` · `linkWithCodeWord`. |
| `connectedAt` | `DateTime` | |
| `block` | `BlockEntry?` | Null means not blocked. |
| `pendingIdentityChange` | `IdentityChangeNotice?` | Non-null while a warning or notice is unacknowledged. |
| `status` | `ContactStatus` | `active` · `retired`. A contact is retired when a user-confirmed replacement happens (R11). A retired contact stays readable and cannot be messaged. |

**Invariants** (enforced in the aggregate, unit-tested):

- `trust == verified` requires one of:
  - `connectedVia == qr`;
  - `connectedVia == linkWithCodeWord`;
  - a `SafetyCodeVerified` record.

  Trust persists until the identity changes (FR-017).
- Address uniqueness: at most one `active` contact per `address`. Connecting to an already-connected
  identity keeps the existing contact (edge case "already connected").
- A contact whose `pendingIdentityChange.severity == blocking` cannot send (FR-015). Queued outbox
  items for it are held.
- `block != null` means the contact cannot send, and inbound messages are discarded (FR-034, FR-035).

**`TrustState` transitions** (driven by `ContactTrustBloc`, the security-critical auditable log):

```text
                  connected via QR / link+code word
            ┌──────────────────────────────────────────┐
            ▼                                          │
notVerified ──safety code match (compare or scan)──► verified
     ▲                                                 │
     └───────── identity change (R11) ─────────────────┘   + blocking warning
notVerified ── identity change ──► notVerified              + visible notice
```

A safety-code mismatch leaves the state unchanged and shows the explanation (US2-6).

### 4.2 `BlockEntry` (entity within the Contact aggregate)

`{blockedAt: DateTime}`. Blocking and unblocking touch only this contact (FR-038). The server-side
mirror is the XEP-0191 list (R18). The entry is part of the contact backup.

### 4.3 `IdentityChangeNotice` (value object)

| Field | Type | Notes |
|---|---|---|
| `severity` | `blocking` · `notice` | `blocking` if the contact was verified (FR-015), else `notice` (FR-016). |
| `cause` | `keyMismatch` · `userReplacement` | R11. |
| `detectedAt` | `DateTime` | |
| `acknowledgedAt` | `DateTime?` | Acknowledging clears the send block and releases held messages. |

The notice also appears as a system item in the conversation timeline.

### 4.4 `ContactBackupState` (entity, singleton)

| Field | Type | Notes |
|---|---|---|
| `counter` | `int` | Monotonic. Bound into the AEAD associated data (R13). |
| `lastSyncedAt` | `DateTime?` | |
| `dirty` | `bool` | Set on any contact, trust, display-name, or block change. Cleared after a successful `PUT`. |

The ciphertext is produced natively. Dart sees opaque bytes only, and they go straight to Dio.

---

## 5. Messaging context (`lib/features/messaging/`)

### 5.1 `Conversation` (aggregate root, entity)

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | One per contact (1:1). |
| `contactId` | `String` | A cross-aggregate reference by ID. |
| `lastActivityAt` | `DateTime` | Chat-list ordering. |
| `unreadCount` | `int` | Local only. No read receipts (spec assumption). |
| `nextOutboundSeq` | `int` | Monotonic per conversation (R17). |

`Conversation` holds the timeline through repository queries, paged 50 at a time. It never loads all
messages.

### 5.2 `Message` (entity)

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | UUIDv4. Also the XMPP stanza id, and the XEP-0184 receipt reference. |
| `conversationId` | `String` | |
| `direction` | `outgoing` · `incoming` · `system` | `system` is used for identity-change notices and "connected" markers. |
| `text` | `MessageText` | Decrypted content. It lives in `data.db` (encrypted at rest) and in presentation state while visible (C20). |
| `sentAt` | `DateTime` | The sender's clock, carried in the encrypted payload. |
| `receivedAt` | `DateTime?` | |
| `seq` | `int` | The sender's per-conversation sequence. |
| `delivery` | `DeliveryState?` | Outgoing only. |

**`DeliveryState` transitions** (FR-019, R17):

```text
pending ──server ack (XEP-0198)──► sent ──receipt (XEP-0184)──► delivered
   │                                 
   └── 5 refusals / 24h online without ack ──► failed ──user retry──► pending
```

- `delivered` is the furthest state (no read receipts).
- `sent` never regresses.
- A message to a blocked-by-recipient contact stays `sent` forever (FR-036).

### 5.3 `OutboxItem` (entity, persisted)

| Field | Type | Notes |
|---|---|---|
| `messageId` | `String` | |
| `attempts` | `int` | 0–5. |
| `nextAttemptAt` | `DateTime` | Backoff from 2 s to 32 s. |
| `heldReason` | `none` · `identityChangeUnacknowledged` · `contactBlocked` · `offline` | A held item is not attempted. |

The ciphertext is produced at send time, natively, never earlier. A held item therefore doesn't
consume ratchet state.

### 5.4 Inbound processing order (invariant, unit-tested)

The order matters. Blocking is checked before decryption, and nothing is acknowledged before it is
committed.

1. **Sender is blocked**: drop. No decrypt, no receipt, no notify (FR-034).
2. **Sender unknown and the payload is not a connection hello**: drop (no directory, FR-007).
3. **Decrypt natively**. An identity mismatch triggers an `IdentityChangeNotice` with cause
   `keyMismatch`, and the message is not shown.
4. **Commit to `data.db`**. If it fails (for example, storage full): no receipt, warn the user.
5. **Send the XEP-0184 receipt**.
6. **Notify** with content-free text (FR-023).

---

## 6. Settings context (`lib/features/settings/`)

`AppPreferences` (value object, `vault.db`):

| Field | Notes |
|---|---|
| `themeMode` | `system` (default, FR-043). |
| `backgroundConnection` | Android only, default on (R15). |
| `connectionPreferences` | §3.2. |
| `remindersEnabled` | Mirrors §2.2. |

---

## 7. Cross-context domain events (`domain/events/`, all with the five dartdoc tags)

| Event | Dispatcher | Consumers | Payload | Security-critical (C4) |
|---|---|---|---|---|
| `IdentityActivated` | `CompleteRegistrationUseCase`, `RestoreIdentityUseCase` | `AppSessionCubit`, `ContactBackupSyncService` | `activatedAt` | yes |
| `IdentityRemoved` | `RemoveFromDeviceUseCase`, `HandleDeviceSupersededUseCase` | `AppSessionCubit`, `ConversationListCubit`, `ChatCubit`, `ContactListCubit` (each clears and closes, C20) | `reason (removed / superseded)`, `removedAt` | yes |
| `ContactConnected` | `CompleteConnectionUseCase` | `ConversationListCubit`, `ContactBackupSyncService` | `contactId`, `method`, `connectedAt` | no |
| `ContactTrustChanged` | `VerifySafetyCodeUseCase`, `HandleIdentityChangeUseCase` | `ChatCubit`, `ContactBackupSyncService` | `contactId`, `trust`, `changedAt` | yes |
| `ContactIdentityChanged` | `HandleIdentityChangeUseCase` | `ContactTrustBloc`, `ChatCubit`, `OutboxService` | `contactId`, `severity`, `cause`, `detectedAt` | yes |
| `ContactBlockChanged` | `BlockContactUseCase`, `UnblockContactUseCase` | `ChatCubit`, `ConversationListCubit`, `InboundMessageService`, `ContactBackupSyncService` | `contactId`, `blocked (bool)`, `changedAt` | no |
| `MessageReceived` | `InboundMessageService` | `ConversationListCubit`, `ChatCubit`, `NotificationService` | `conversationId`, `messageId`, `receivedAt` | no |
| `DeliveryStateChanged` | `OutboxService`, `ReceiptService` | `ChatCubit` | `messageId`, `state`, `changedAt` | no |

No event carries an address, public key, display name, or text (C10, C14). Consumers re-read by ID
through their own use cases.

---

## 8. Server-side data (key service, PostgreSQL), for SC-002 inspection

| Table | Columns | What the operator can learn |
|---|---|---|
| `accounts` | `address`, `x25519_pub`, `mldsa_pub`, `device_epoch`, `registered_at`, `last_auth_at` | That an identity exists, plus its public keys. No PII. |
| `signed_prekeys`, `kyber_prekeys` | `address`, `key_id`, `public`, `dual_sig`, `uploaded_at` | Public prekeys. |
| `one_time_prekeys` | `address`, `key_id`, `kind (ec/kyber)`, `public` | Pool size. Rows are deleted when served. |
| `links` | `link_id`, `creator_address`, `expires_at`, `status`, `reserved_by`, `updated_at` | That an identity created a link and who redeemed it. No keys and no secret. Rows are purged 7 days after a terminal state. |
| `contact_backups` | `address`, `counter`, `blob (padded)`, `updated_at` | An opaque blob and its 4 KiB-bucketed size (FR-045). |
| `push_tokens` | `address`, `apns_token`, `updated_at` | iOS only. Disclosed (FR-024). |
| `auth_challenges` | `nonce`, `expires_at` | Ephemeral. Purged after 60 s. |

Prosody stores only:

- the XEP-0191 blocklist (`address → blocked addresses`);
- offline messages (ciphertext plus the stanza routing attributes `from`/`to`/`id`) until delivery,
  or 30 days at most;
- the `mod_cloud_notify` registrations.

There is no MAM, roster, vCard, or PEP data. Display names never reach the server in plaintext.
