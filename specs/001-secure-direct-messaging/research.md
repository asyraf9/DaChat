# Phase 0 Research: Secure Direct Messaging (Main Server)

**Feature**: `001-secure-direct-messaging` · **Date**: 2026-10-27 · **Plan**: [plan.md](./plan.md)

Each item resolves an unknown from the plan's Technical Context. Format: **Decision**, **Rationale**,
**Alternatives considered**. Items marked **⚑ Review** are decisions where the spec or blueprints left
real room. The plan proceeds on the stated decision, and the reviewer should confirm it when accepting
the plan.

---

## R1. Where cryptography and encrypted storage run: one native core

**Decision**: Build a single Rust crate, `native/dachat_core`, bound to Dart with
`flutter_rust_bridge` v2. It contains:

- the vendored, pinned `libsignal-protocol` (PQXDH, Triple Ratchet);
- the hybrid identity (X25519 + ML-DSA-87);
- seed and recovery-phrase derivation;
- the safety-code construction;
- contact-backup encryption;
- **every encrypted at-rest store**, including the libsignal store traits.

Dart never receives private keys, ratchet state, or store keys. The exception is the C15 hand-off of
the store key, covered in R4. The core exposes a narrow, task-shaped API (see
[contracts/native-core-api.md](./contracts/native-core-api.md)), not primitives.

**Rationale**:

- RQSM §18.4 requires that key bytes are not copied onto the Dart heap and stay behind the FFI
  boundary, where they can be zeroised.
- Putting the libsignal store traits in Rust removes a whole class of Dart-heap exposure. The ratchet
  state never crosses FFI.
- It also satisfies C17's intent: the store key is used only where the store is opened, and that is
  native code.
- One native core keeps a single audit surface: the binding, the store traits, and the custom
  constructions.

**Alternatives considered**:

- *Store traits in Dart (`core/security/`) over a Dart-side store*, the layout RQSM §4 sketches. It
  would move serialized session records across FFI on every message and put them on the Dart heap.
  Rejected. This deviation from RQSM §4 placement is recorded in the plan's Complexity Tracking.
- *Separate Dart crypto packages* (for example `cryptography`). They don't provide libsignal, and they
  violate C18. Rejected.

## R2. libsignal version and vendoring

**Decision**: Vendor `libsignal` as a git submodule at `native/third_party/libsignal`, pinned to the
first release tag that ships the SPQR Triple Ratchet (the latest tag at implementation start). Record
the commit hash and a SHA-256 tree digest in `native/third_party/libsignal.lock`. A CI step re-computes
the digest and fails on mismatch. Only `libsignal-protocol` (and its own `libsignal-core` dependency)
is linked. The Java, Swift, and Node bridges are not built. A `docs/security/libsignal-repin.md`
runbook defines the re-pin cadence: quarterly, and on any advisory.

**Rationale**: This follows constitution C18 and RQSM §18.2 M2. libsignal has no third-party
versioning guarantees, so the pin is the contract.

**Alternatives considered**:

- *Depending on crates.io releases*: libsignal does not publish to crates.io. Rejected.
- *Floating on `main`*. Rejected (M2).

## R3. ML-DSA-87 and recovery-phrase libraries

**Decision**:

- **ML-DSA-87**: `libcrux-ml-dsa` (Cryspen). It is formally verified in parts, from the same libcrux
  family libsignal already uses for ML-KEM, and it supports deterministic key generation from a
  32-byte seed, which R2.1 recovery needs.
- **Mnemonic**: the `bip39` crate (rust-bitcoin), 24 words (256-bit entropy), English wordlist.

Both are pinned in `Cargo.lock` and digest-verified like libsignal.

**Threat-model rationale (C8)**:

- ML-DSA closes the post-quantum account-impersonation gap (registration blueprint R2.4a).
- BIP39 gives a human-writable, checksummed phrase.

**Blast radius if compromised**:

- A bad ML-DSA implementation degrades account authentication to classical-only. It never affects
  message confidentiality, which is libsignal's.
- A bad bip39 implementation could produce weak entropy. Mitigations: entropy comes from the OS CSPRNG
  (`getrandom`), not from the crate, and KATs pin the derivation.

**Alternatives considered**:

- `pqcrypto-mldsa` (PQClean C via FFI): adds a C toolchain and is harder to zeroise.
- RustCrypto `ml-dsa`: less mature and not verified.
- `aws-lc-rs`: ML-DSA API unstable at time of writing, and a large C dependency.

Re-evaluate at pin time. The choice is behind `IdentitySigner` inside the core, so a swap is local.

## R4. Key hierarchy and hardware wrapping

**Decision**:

```text
OS CSPRNG ──► 256-bit recovery entropy ──► BIP39 phrase (24 words)
                         │
                   BIP39 seed (PBKDF2, empty passphrase)
                         │ HKDF-SHA-512, domain-separated labels
     ┌───────────────────┼────────────────────────┬──────────────────────┐
"dachat/v1/id/x25519" "dachat/v1/id/mldsa87"  "dachat/v1/backup/key" "dachat/v1/backup/id"
 libsignal IdentityKeyPair  ML-DSA-87 keygen ξ   contact-backup AEAD key  backup locator

Hardware wrapping key (HWK, non-exportable, in secure element / keystore)
        └─ wraps ─► Device Encryption Key (DEK, random 256-bit, per install)
                        └─ HKDF ─► vault.db key · signal.db key · data.db key   (C15: derived, never persisted)
```

- **Android**:
  - An AES-256-GCM key in Android Keystore, StrongBox-backed when available, otherwise TEE.
  - `setUserAuthenticationRequired(false)`, so background message decryption keeps working.
- **iOS**:
  - A Secure Enclave P-256 key with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
  - The DEK is wrapped with `SecKeyCreateEncryptedData`, using
    `eciesEncryptionCofactorVariableIVX963SHA256AESGCM`.
- **Linux**:
  - The DEK is stored in the Secret Service (libsecret / GNOME Keyring / KWallet) through the Rust
    `secret-service` crate.
  - If no Secret Service is available, the fallback is a user passphrase, run through Argon2id (Rust
    `argon2`, m=64 MiB, t=3, p=1) to make a KEK.
  - Both cases are disclosed as weaker (FR-003, edge case).
- The wrapped DEK blob lives in the app-support directory, excluded from backup.
- At cold start, a dedicated Dart **crypto isolate** calls the platform channel through
  `BackgroundIsolateBinaryMessenger` to unwrap the DEK. It passes the bytes directly to
  `NativeCore.openStores`, then zero-fills the `Uint8List`. The DEK never touches the main-isolate
  heap.
- Inside the core, the master private keys and the recovery entropy are stored in `vault.db` and are
  re-encrypted per record under a vault sub-key. They are decrypted only for the duration of a signing
  or phrase-display call, then zeroised (`zeroize` crate).

**Rationale**:

- R2.1 and R2.1b say the master key is derived in software from the seed, never generated in the
  secure element, and wrapped by a hardware key.
- Mobile secure elements don't support X25519 or ML-DSA, so they wrap a symmetric DEK instead.
- Separate store keys follow RQSM §5.4 blast-radius isolation.

**Alternatives considered**:

- *Wrapping each master key directly with the HWK*: iOS Secure Enclave can only do ECIES to P-256, so
  this ends up equivalent with more platform calls. Rejected for simplicity.
- *`flutter_secure_storage` for the DEK*: C2 forbids it for hardware-protected material. Rejected.
- *Requiring biometric unlock per use*: it breaks background receipt, and app lock is out of scope.
  Deferred.

## R5. Encrypted at-rest store engine

**Decision**: SQLCipher 4 via `rusqlite` with the `bundled-sqlcipher-vendored-openssl` feature, inside
the native core. There are three database files, each with its own HKDF-derived key:

| File | Contents |
|---|---|
| `vault.db` | Identity record (per-record encrypted master keys and recovery entropy), local settings |
| `signal.db` | libsignal store traits: identity, session, prekey, signed prekey, Kyber prekey; sender-key is unused in 001 |
| `data.db` | Contacts, block entries, connection links, conversations, messages, outbox, sync markers |

All three are created with `PRAGMA cipher_memory_security = ON` and are excluded from OS backup
(R14). **Isar is not used in feature 001.**

**Rationale**:

- RQSM §5.4 caveat: stable Isar 3.x has no at-rest encryption, and the community fork doesn't either.
  Contacts, display names, and history must not be on disk in plaintext (FR-022).
- SQLCipher is audited and works on Android, iOS, and Linux from one Rust build.
- RQSM's conditional `sqflite_sqlcipher` justification covers SQLCipher as the engine. Hosting it in
  Rust instead of `sqflite_sqlcipher` avoids `sqflite`'s missing Linux support and keeps store keys
  native.

**Alternatives considered**:

- *`sqflite_sqlcipher`* (Dart): no Linux support, and the key passes through the Dart heap. Rejected.
- *Isar plus app-layer AEAD per field*: queries over encrypted fields are impractical, and indexes
  leak. Rejected.
- *Isar for non-sensitive data only*: almost nothing in 001 is non-sensitive. Theme follows the
  device, and nudge timestamps go in `vault.db`. Not worth a second engine.

## R6. Server stack, and the server deliverable in this repository

**Decision**: The main server is two co-deployed components in `server/` in this repository:

1. **Prosody 13** (XMPP), for message relay, offline storage, blocking, and push hooks. It runs stock
   modules plus three small custom Lua modules:
   - **Stock modules**: `mod_offline` (store until delivered), `mod_smacks` (XEP-0198 acks), and
     `mod_blocklist` (XEP-0191). `mod_mam` and `mod_register` (in-band registration) are disabled.
     `mod_cloud_notify` (XEP-0357) is enabled.
   - **Custom `mod_dachat_auth`**: SASL PLAIN over TLS that accepts a short-lived HMAC-signed token
     issued by the key service.
   - **Custom `mod_dachat_single_device`**: one bound resource per account. A newer device epoch kicks
     the older session with a `superseded` condition.
   - **Custom `mod_dachat_offline_ttl`**: purges undelivered offline messages after 30 days.
2. **`dachat-keyservice`** (Rust, `axum` + PostgreSQL 17), over HTTPS, handling:
   - key-based registration with dual-signature challenge–response;
   - XMPP token issuance;
   - device epochs (single active device);
   - prekey bundles and one-time prekey pools;
   - the connection-link registry (single-use, 24 h, revocable);
   - the encrypted contact-backup blob;
   - the APNs push gateway.

   It reuses `libsignal-core` and `libcrux-ml-dsa` from the same pins to verify signatures.

`server/docker-compose.yml` brings up the whole stack for local and staging tests. The SC-002
inspection script (`server/tools/inspect_server_data.sh`) dumps everything both components store.

**Rationale**:

- Prosody is Lua and cannot verify ML-DSA without native code. A small Rust service reuses the exact
  crypto pins the client uses, so both sides verify identically.
- Stock Prosody modules already provide offline delivery, acknowledgements, and blocking.
- Feature 001 is Default Chat mode. Per the privacy blueprint §2.1, the main server may observe sender
  and recipient identities, so **libsignal sealed sender and the custom Prosody sealed-sender module
  are not needed in 001**. That also keeps XEP-0191 server-side blocking possible (FR-034).
- Keeping the server in the same repository keeps the wire contracts in one reviewable place.

**Alternatives considered**:

- *ejabberd*: Erlang has the same ML-DSA gap, and the blueprints call Prosody and ejabberd
  interchangeable. Prosody's module API is smaller. ejabberd parity is deferred to roadmap A1.
- *Do everything in the Rust service with no XMPP*: this contradicts the constitution's "XMPP
  (`moxxmpp`) is the primary transport" and the server-driver model. Rejected.
- *Sealed sender now*: out of 001's disclosed threat model, and it blocks server-side blocking.
  Deferred to roadmap A1 (private-server mode).

## R7. Account address (JID) and authentication

**Decision**:

- **Address**: the JID localpart is `base32lower(SHA-256("dachat/v1/addr" ‖ X25519_pub ‖ MLDSA87_pub))`,
  truncated to 26 characters (130 bits), at the main-server domain. It is deterministic from the
  recovery seed, so a restore needs no stored address. It carries no human-readable data. The
  libsignal `ProtocolAddress` is `(localpart, device_id = 1)`.
- **Registration**: an idempotent upsert on the public-key pair (R5.6). The request contains both
  public keys and a dual signature over a server-issued nonce.
- **Sign-in**:
  1. `POST /v1/auth/challenge` returns a nonce.
  2. The client dual-signs `("dachat/v1/auth" ‖ domain ‖ nonce ‖ device_epoch)`.
  3. The key service verifies both signatures and issues a 5-minute XMPP token.
  4. The client authenticates to Prosody with SASL PLAIN (JID, token) over TLS 1.3.
- **Certificate pinning**: the app embeds SPKI SHA-256 pins (primary plus backup) for the main
  server's TLS key, per flavour. They are applied to both the Dio client and the XMPP socket.

**Rationale**: This satisfies R2.3, R2.4, and R2.4a (dual signatures, both required) and M5
(pinning). Deriving the address from the keys means a server can't silently rebind an address to
other keys.

**Alternatives considered**:

- *A random account ID*: it would have to be backed up separately, and it breaks the
  "restore from phrase alone" property. Rejected.
- *Custom SASL mechanism in Lua*: no ML-DSA in Lua. Rejected.

## R8. Single active device (FR-029)

**Decision**:

- The key service keeps an `active_device_epoch` per account. Restore runs on the new device and
  registers with `epoch + 1`, signed by the master key.
- Tokens embed the epoch. `mod_dachat_single_device` rejects tokens whose epoch is older and kicks
  any bound session that has an older epoch.
- When the old device next connects, the challenge response is `409 superseded`. The old device then
  shows the explanation and runs the same atomic wipe as "Remove from this device" (R12), except that
  it does not delete the server-side contact backup.
- The new device publishes fresh prekeys. For each restored contact, it sends a libsignal PreKey
  message carrying a `session_reset` control payload, so contacts move to the new session. The
  identity key is unchanged, so no warning is shown.
- Messages that contacts sent to the old session and that are undecryptable trigger libsignal
  `DecryptionErrorMessage` resend requests.

**Rationale**: This gives one active device without preventing multi-device later: `device_id` is
reserved and epochs extend to per-device certificates (R3.5–R3.7).

**Alternatives considered**:

- *Leave the old device untouched*: violates FR-029.
- *Remote wipe push*: there is no push to Linux or Android in 001, and the device must connect anyway.

## R9. Connections: QR, link, code word, and handshake

**Decision**: This decision has five parts.

**QR payload** (binary, base45-encoded in an alphanumeric QR):

```text
version(1) ‖ x25519_pub(33) ‖ sha256(mldsa_pub)(32) ‖ pairing_nonce(16)
```

- 82 bytes before encoding. It fits QR version 10 at error-correction level M with a large margin.
- The QR does not carry a display name. Display names travel only E2EE (FR-006, R1.9).
- The full ML-DSA public key is fetched with the prekey bundle and must match the hash (RQSM §16).
- A mutual scan is needed. Each side, after scanning, sends a `connection_hello` (below) quoting the
  nonce it scanned.
- Each side marks the contact **verified** once it has both scanned the peer's QR and received the
  peer's hello that quotes the nonce from its own QR.
- If only one side scanned, that side shows "Ask them to scan your code too".

**Link** (`https://<main-domain>/c/<link_id>#<fragment>`):

- `link_id` is 128-bit random and is registered with the key service:
  `{creator address, expires_at = +24h, status}`.
- The fragment carries `version ‖ x25519_pub ‖ sha256(mldsa_pub) ‖ link_secret(32) ‖ requires_code_word(1)`.
- URL fragments are never sent to a server. Neither the key service nor the web page that serves
  `/c/*` can see the creator's keys or the secret.

**Redemption**:

1. Before the recipient taps to confirm, they see the creator's safety-code preview and the link's
   rules.
2. `POST /v1/links/{id}/redeem` atomically moves `active → reserved(redeemer address)`. A second
   redeemer gets `410 used`. Expired links return `410 expired`, and revoked links return
   `410 revoked`. The atomic transition is a single PostgreSQL `UPDATE … WHERE status='active' AND
   expires_at > now()`.
3. The redeemer fetches the creator's bundle and sends a `connection_hello` whose proof is
   `HMAC-SHA-256(link_secret, "dachat/v1/link-proof" ‖ redeemer_x25519 ‖ redeemer_mldsa_hash)`.

**Code word**:

- If the link requires one, the hello also carries the entered code word. Inside the PQXDH-encrypted
  message, only the creator's device sees it.
- The creator's device compares it in constant time. A correct word means `accept`, and the contact
  is verified on both sides. A wrong word means `reject(attempts_left)`.
- After 3 rejections, the creator's device calls `POST /v1/links/{id}/resolve` with
  `outcome: exhausted`, and the link is dead.
- The code word is never sent to the server, so offline brute force is impossible. Only the
  redeemer's 3 online attempts exist.

**Handshake**:

- `connection_hello` and `connection_accept` are the first libsignal messages of the session
  (PreKey messages). Their plaintext is a typed control payload (see
  [contracts/wire-protocol.md](./contracts/wire-protocol.md)).
- The payload carries:
  - the full ML-DSA public key;
  - a dual signature binding `(own keys ‖ peer keys ‖ nonce or link proof)`;
  - the encrypted display name;
  - for link connections, the `connection_method`.
- The creator's device auto-accepts a valid link hello, because creating the link was the creator's
  consent. The tap by the redeemer is the redeemer's consent (R1.6).

**Rationale**:

- This follows R1.5 through R1.8.
- Single use is enforced server-side, atomically (SC-005).
- The ID-confirmation secret stays end-to-end. A forwarded link without the code word fails.
- A server that sees only `link_id` cannot redeem the link meaningfully, because it lacks
  `link_secret` and the creator would reject the proof.

**Alternatives considered**:

- *Server-side code-word check against a hash*: the server could brute-force a low-entropy code
  word. Rejected.
- *PAKE (CPace)*: stronger, but it is custom crypto beyond what RQSM enumerates (C18). The E2EE
  comparison with 3 attempts gives the same online-only guessing bound. Rejected for 001.
- *Display name in the QR*: it would be visible to bystanders and cameras. Rejected.

## R10. Safety code

**Decision**: The safety code reuses libsignal's *numeric fingerprint construction* (version 2,
5200 SHA-512 iterations, 30 digits per party, 60 digits total, displayed as 12 groups of 5). Its
input per party is `x25519_pub ‖ mldsa87_pub` instead of the classical key alone. The QR form is
`version ‖ local_fingerprint(32) ‖ remote_fingerprint(32)`, compared in constant time. The
implementation is about 40 lines in the native core, and KATs pin it.

**Rationale**: RQSM §16 requires the code to cover both halves. Reusing Signal's well-studied
construction minimises novel crypto. The input change is the only difference, and it is in audit
scope.

**Alternatives considered**:

- *libsignal fingerprint over the classical key only*: a future quantum adversary could swap the
  ML-DSA half unnoticed. Rejected.

## R11. Identity change: what it means without a stable identifier **⚑ Review**

**Decision**: There is no username or phone number, and the address is derived from the keys (R7). A
legitimate "same person, new identity" therefore can't arrive at the same address. Feature 001
treats an **identity change** as either of two events, and both run the same Bloc-driven flow
(FR-015, FR-016):

1. **Key mismatch** (attack or malfunction) at a known contact's address. Examples:
   - a prekey bundle whose identity keys differ from the pinned ones;
   - a bundle whose ML-DSA co-signature fails;
   - an inbound PreKey message carrying a different identity key, which libsignal's
     `is_trusted_identity` reports.

   Such a bundle or message is never used.
2. **User-confirmed replacement**. A new identity connects (QR or link), and the user chooses
   "This is <existing contact> with a new identity". This happens after the person lost their phone
   without the phrase. The app offers the choice only as an explicit action on the new connection's
   confirmation screen. It never infers it, including from a matching display name.
   - The old contact entry is retired, and the history stays attached to the conversation.
   - The new identity takes its place with the trust the new connection earned.
   - If the old contact was **verified**, a blocking warning is shown and must be acknowledged
     before sending. Queued messages are held until it is acknowledged.
   - If the old contact was **not verified**, a visible notice is shown instead.
   - A contact replaced over a link is always not verified (FR-015).

**Rationale**: This keeps FR-015 and FR-016 meaningful and testable (US2 scenarios 7–8, SC-006)
without inventing a stable identifier, which would contradict R2.3. The app never silently re-trusts.

**Alternatives considered**:

- *A stable random account ID*: either the server holds identity continuity (a PII-free but
  server-trusted rebinding, which R4.8/R1.8 reject), or it must be backed up (it's already
  seed-derived). Rejected.
- *Display-name heuristic prompts*: they invite spoofing. Rejected.

## R12. Atomic restore and removal (FR-031)

**Decision**: Both operations are journaled state machines persisted in a tiny unencrypted marker
file, `lifecycle.json`, that holds the operation and step only, no data:

- **Restore** steps:
  1. Derive the keys.
  2. Register (epoch + 1).
  3. Fetch and decrypt the contact backup.
  4. Write `vault.db`, `signal.db`, and `data.db` into a staging directory.
  5. Publish prekeys.
  6. Atomically rename the staging directory to live.
  7. Clear the marker.

  On launch, a marker in steps 1–5 means the staging directory is deleted and the restore restarts
  from phrase entry. Nothing is usable until step 6.
- **Remove** steps:
  1. Write the marker.
  2. Delete the HWK from the keystore. This is the crypto-erase point: the stores become
     unrecoverable.
  3. Delete the store files.
  4. Clear the marker.

  On launch, a marker means the remaining steps are completed before any UI.

**Rationale**: Crypto-erase by destroying the HWK makes removal effectively atomic even if file
deletion is interrupted. The staging-plus-rename pattern makes restore all-or-nothing.

**Alternatives considered**:

- *Deleting files first*: it leaves a usable partial identity if interrupted. Rejected.

## R13. Contact backup (FR-045)

**Decision**:

- **Plaintext**: a versioned, deterministic CBOR document holding contacts (address, both public
  keys, display name, trust state, connection method, ID-confirmed flag) and block entries.
- **Encryption**:
  - XChaCha20-Poly1305 (`chacha20poly1305` crate) under the seed-derived backup key.
  - A random 24-byte nonce.
  - The associated data is `"dachat/v1/backup" ‖ version ‖ monotonic counter`.
- **Padding**: padded to the next 4 KiB bucket, so the server sees only a coarse size.
- **Storage**: `PUT /v1/backup` stores it under the authenticated account, with compare-and-swap on
  the counter. Uploads are debounced by 5 s after any change. Pending uploads persist in `data.db` and
  retry on reconnect.
- **Restore**: fetches the latest blob. Three outcomes:
  - **Stale** (local "last synced" counter unknown): the user is told recent changes may be missing.
  - **Missing or undecryptable**: the identity is restored, and the user is told contacts must be
    re-connected.
  - **Otherwise**: full restore (SC-008).

**Rationale**: This follows FR-045 and the edge cases. The server cannot read the blob or tell which
identities it holds. Counter-bound AD prevents rollback to an older blob by the server being
accepted silently, because the client warns when the counter goes backwards.

**Alternatives considered**:

- *AES-GCM*: nonce-misuse risk with random 96-bit nonces over many uploads. XChaCha's 192-bit nonce
  avoids it.
- *No padding*: it leaks the contact count. Rejected.

## R14. Platform hardening

**Decision**: Platform hardening is implemented with in-repo platform code, with no new packages:

- **Android**:
  - `android:allowBackup="false"`, plus `dataExtractionRules` excluding everything.
  - `FLAG_SECURE` toggled through a `dachat/screen_security` method channel on the QR, safety-code,
    and recovery-phrase routes (FR-039). `go_router` route metadata drives it.
- **iOS**:
  - `isExcludedFromBackupKey` is set on the app-support directory.
  - A blur overlay covers the window on `sceneWillResignActive` for protected routes.
  - Screen capture is detected with `UIScreen.capturedDidChangeNotification`, and the protected
    content is hidden while capture is active. A screenshot itself cannot be blocked on iOS. This is
    disclosed.
- **Linux**: no screenshot prevention is possible. This is disclosed on the protected screens.

**Rationale**: This covers FR-022, FR-039, and RQSM §18.5.

**Alternatives considered**: `flutter_windowmanager` and `screen_protector` are not approved, and the
code is about 30 lines per platform. Rejected.

## R15. Background delivery and notifications (FR-023, FR-024)

**Decision**:

- **Android**: no FCM. An in-repo Kotlin foreground service keeps the process, and the cached Flutter
  engine's XMPP connection, alive. It shows an ongoing "DaChat is connected" notification. It is on by
  default, the user can turn it off in Settings, and its battery cost is disclosed. Because no push
  provider is involved, FR-024's push disclosure doesn't apply on Android.
- **iOS**:
  - APNs, through an in-repo Swift channel that obtains the device token. No Firebase.
  - Prosody `mod_cloud_notify` pings the key-service push gateway, which sends a content-free alert
    ("New activity in DaChat") with no sender information. The server can't know display names.
  - FR-024 is disclosed during setup and in Settings: Apple sees timing, not content.
  - Pushes are coalesced to at most one per 60 s per device.
- **Linux**: messages arrive while the app runs.
- **Local notifications** use `flutter_local_notifications`, which RQSM already justifies.
  - When the app is running, a notification shows "New message from <display name>". It never shows
    content.
  - Android lock-screen visibility is `VISIBILITY_PRIVATE`, with a redacted public version
    ("New message").
  - Messages from blocked contacts are discarded before any notification (FR-034).

**Rationale**: This follows the privacy blueprint §2.6 and C12. FCM's SDK brings Firebase
installation and telemetry plumbing, which C12 rules out for a privacy-goal project.

**Alternatives considered**:

- *FCM data messages*: adds a third-party SDK and Google metadata. Rejected.
- *UnifiedPush*: not approved and an unusual dependency for users. Deferred.
- *iOS Notification Service Extension that decrypts*: it needs the native core and stores inside an
  app extension (shared container and keychain-access group). Deferred to roadmap A8.

## R16. XMPP client library

**Decision**: `moxxmpp`, as RQSM §1 justifies, wrapped by `XmppTransportDriver` behind the
`TransportDriver` interface. Used features:

- TLS with pinned SPKI;
- SASL PLAIN;
- stream management (XEP-0198), for "sent";
- message delivery receipts (XEP-0184), for "delivered";
- the blocking command (XEP-0191);
- push registration (XEP-0357).

The message body is a custom `<dc xmlns="urn:dachat:msg:1">` element carrying the base64 libsignal
ciphertext. It replaces the OMEMO wire format: 001 is single-device, and there is no device-list PEP
node. The OMEMO-2-adapted shape returns with multi-device (roadmap A11).

Only `XmppTransportDriver` is implemented. `TransportSwitcher` is a single-driver passthrough, so the
mesh drivers (B1) slot in later.

**Rationale**: It's the transport the constitution and RQSM approve. The interface keeps the domain
transport-agnostic.

**Risk**: `moxxmpp` is maintained by a small team. **Fallback of record**: replace the driver with an
XMPP client in the native core (`tokio-xmpp`). That change is confined to one class.

**Alternatives considered**:

- *Hand-written XMPP over `dart:io`*: reinventing a protocol stack. Rejected.

## R17. Delivery states (FR-019, SC-004)

**Decision**:

| State | Set when |
|---|---|
| `pending` | Written to the outbox in `data.db` before any send attempt. A cold start re-queues it. |
| `sent` | The server acknowledged the stanza (XEP-0198 `<a h=…>` covering it). |
| `delivered` | A XEP-0184 receipt arrives. The receipt carries the message id only, which the server already sees in the stanza. |
| `failed` | 5 attempts with exponential backoff (2 s → 32 s) were all refused by the server, or the item is still unacknowledged after 24 h of connectivity. The user can retry. |

- The recipient sends a receipt only after the decrypted message is committed to `data.db`. The
  storage-full edge case means no receipt and an in-app warning.
- A blocked sender's message gets no receipt (FR-036/US4 scenario 3: it stays "not delivered").
- Order is preserved per sender: XMPP in-order delivery plus a per-conversation monotonic sequence in
  the encrypted payload. A message received out of order is held up to 10 s for gap fill, then shown.

**Rationale**: State reflects real events only (SC-004). No read receipts or typing (spec
assumption).

**Alternatives considered**:

- *An encrypted delivery ack inside libsignal*: it hides nothing extra in Default Chat mode, and it
  costs a ratchet step per message. Deferred. It is useful in private-server mode (A1).

## R18. Blocking (FR-033 to FR-038)

**Decision**:

- **Block**:
  1. Write the `BlockEntry` locally (immediate effect on device).
  2. Send XEP-0191 `<block>` for the contact's JID, so Prosody drops their stanzas, including
     connection hellos, server-side.
  3. Schedule a backup sync.
- **Inbound pipeline**: the block check runs on the sender address **before decryption**. A blocked
  sender's stanza is discarded without advancing the ratchet, without a receipt, and without a
  notification.
- **Blocked person's view**: Prosody's blocklist returns no error to the blocked sender (configured
  silent), so their messages stay "sent".
- **Unblock**: send `<unblock>`. Messages sent during the block were dropped server-side and are
  never delivered (FR-037).
- **Session continuity**: blocking does not touch libsignal sessions with other contacts (FR-038).
  The blocked contact's own session is kept, so unblocking needs no re-connection.

**Rationale**: Enforcement is both server-side and on-device, as the spec input requires. Silent
drops satisfy FR-036.

**Alternatives considered**:

- *Deleting the session on block*: it forces re-connection on unblock. Rejected.

## R19. Onboarding without connectivity

**Decision**: Key generation happens immediately and offline. Registration and prekey publication
are queued as a `pending_registration` lifecycle state. The UI says setup will finish when
connectivity returns. QR display and link creation are disabled until registration succeeds,
because a peer would fetch a bundle that doesn't exist yet. Nothing is published before
connectivity returns.

## R20. Recovery nudge schedule

**Decision**:

- **First nudge**: the first app launch at least 24 h after setup.
- **Repeats**: every 7 days until the phrase is confirmed or reminders are turned off.
- **Confirmation**: re-enter 3 randomly chosen word positions out of 24.
- **Storage**: the nudge state is kept in `vault.db` settings.
- **Visibility**: never shown while a blocking identity-change warning is open.

## R21. Gherkin execution and test infrastructure

**Decision**:

- **BDD runner**: an in-repo thin runner, `test/runners/gherkin_runner.dart`, about 200 lines. It
  parses `.feature` files (Feature / Background / Scenario / Scenario Outline / Examples / Given /
  When / Then / And / But / tags) and dispatches steps to regex-registered Dart step functions in
  `test/features/<feature>/steps/` and `test/shared/common_steps/`. Unmatched steps fail the run.
- **Test layers**: unit and widget scenarios run under `flutter test`. Integration scenarios run
  under the SDK `integration_test` package against the docker-compose server, using the staging
  flavour.
- **Native core**: Rust tests run with `cargo test`. Coverage is gated with `cargo llvm-cov` at
  ≥ 95% line and branch for `native/dachat_core` (extending C13 to the code that now hosts the crypto
  and security logic). KAT vectors use synthetic material marked `// TEST ONLY` (C11).
- **Fakes**: `FakeTransportDriver` (RQSM §19.2) and `FakeNativeCore` live in `test/shared/support/`
  before any widget test.

**Rationale**: No unapproved packages are needed. `bdd_widget_test` and `flutter_gherkin` would need
justification, and `flutter_gherkin` is unmaintained.

**Alternatives considered**: `bdd_widget_test`, which uses code generation and isn't approved.
Rejected.

## R22. Dependency set for 001

The approved-stack packages used are:

| Category | Packages |
|---|---|
| Navigation, networking | `go_router`, `dio`, `retrofit` |
| State | `flutter_bloc`, `bloc`, `bloc_concurrency`, `flutter_hooks` (widget-local controllers only) |
| Code generation | `freezed`, `freezed_annotation`, `json_serializable`, `injectable`, `injectable_generator`, `build_runner` |
| Core infrastructure | `fpdart`, `get_it`, `event_bus`, `logger`, `flutter_dotenv` |
| Localisation | `flutter_localizations`, `intl` |
| Assets | `flutter_gen_runner` (app icon and illustration accessors) |
| Lint, test, coverage | `very_good_analysis`, `mocktail`, `bloc_test`, `coverage` |

Not used in 001: `isar` (R5), `flutter_secure_storage` (R4: nothing in 001 belongs to that tier),
and `cached_network_image` (no media).

Non-standard packages, all already in RQSM's justification table:

| Package | Why |
|---|---|
| `flutter_rust_bridge` | R1 |
| `moxxmpp` | R16 |
| `connectivity_plus` | Reachability for the outbox and onboarding |
| `qr_flutter` + `mobile_scanner` | R9. `mobile_scanner` has no Linux camera support: on Linux the app can show its QR and use links, but cannot scan. This is disclosed. |
| `flutter_local_notifications` | R15 |

Rust crates (native core and key service) are governed by C8 and listed in the plan with their
blast-radius statements:

- `libsignal-protocol` (vendored)
- `libcrux-ml-dsa`
- `bip39`
- `rusqlite` + SQLCipher
- `chacha20poly1305`
- `hkdf`, `sha2`, `hmac`
- `zeroize`
- `subtle`
- `argon2` and `secret-service` (Linux only)
- `getrandom`
- `ciborium`

**RQSM table update required in the same change**:

- The `sqflite_sqlcipher` row becomes "SQLCipher, hosted in the native core via `rusqlite`".
- A row is added for the native-core crates.

## R23. Scale and performance targets

Assumed for the main server at 001 launch:

- 10,000 registered identities and 1,000 concurrently connected;
- a peak of 50 messages per second;
- a single Prosody node and a single key-service node.

The client targets are the spec's SC-001/003/007:

- delivery to an online recipient within 3 s at p95 (internal budget: send→server ack ≤ 500 ms,
  server→recipient ≤ 1 s, decrypt + commit ≤ 200 ms);
- delivery within 30 s of reconnect;
- 60 fps scrolling in a conversation of 10,000 messages (paged queries of 50 from `data.db`);
- cold start to the conversation list ≤ 2 s on a mid-range Android device (store open + DEK unwrap
  ≤ 300 ms).
