# Contract: Native Core API (`native/dachat_core` ↔ Dart), v1

The core is bound with `flutter_rust_bridge` v2 (R1). The generated bindings live in
`lib/core/crypto/bridge/` and are imported **only** by `lib/core/crypto/` (RQSM §4 import rule).
Everything else depends on the hand-written Dart facade `NativeCore`, an abstract class in
`lib/core/crypto/native_core.dart`. Tests replace it with `FakeNativeCore`.

## Contract rules

- **No private key, ratchet state, store key, recovery entropy, link secret, or code word is ever
  returned to Dart.** The one exception is the `RecoveryPhraseView` words, described below.
- Inputs that are secrets (the DEK, the phrase being restored, a code word) are passed in as
  `Uint8List` or `String`. Dart zero-fills the buffers after the call, on a best-effort basis
  (C15/C20 caveat).
- **Errors**: every method returns `Result<T>` on the Dart side. Rust errors map to
  `CryptoFailure(CryptoErrorCode)` or `RatchetFailure(RatchetErrorCode)` and carry the opaque code
  only (C3).
- **Threading**: calls are async on frb's Rust thread pool. The stores are opened only through
  `openStores`, which is called from the crypto isolate (R4).
- **Logging**: the native side writes no logs in release builds. In debug builds it emits only
  `error_code` and operation name to the Dart `AppLogger`, under the C5 blocklist.

## Lifecycle and stores

| Method | Purpose |
|---|---|
| `openStores(dek: Uint8List) → Result<StoreStatus>` | Derives three store keys (HKDF) and opens `vault.db`, `signal.db`, and `data.db` (SQLCipher). Returns `empty`, `ready`, or `corrupt`. **Must** be called from the crypto isolate. |
| `closeStores() → Result<void>` | Zeroises in-memory keys and closes the stores. |
| `lifecycleResume() → Result<LifecycleStep?>` | Reads `lifecycle.json` and completes or rolls back an interrupted operation (R12). |
| `wipeAll() → Result<void>` | Deletes the store files and the journal. The caller deletes the HWK first (crypto-erase). |

## Identity (`identity` feature through `core/security/IdentityService`)

| Method | Purpose |
|---|---|
| `createIdentity() → Result<IdentitySummary>` | Generates entropy, derives keys (R4), and persists them to `vault.db`. Returns `address`, `PublicIdentity`, and `createdAt`. |
| `beginRestore(phrase: String) → Result<IdentitySummary>` | Validates the BIP39 checksum and derives keys into the **staging** directory. Errors: `invalidPhrase`, `wrongWordCount`, and `unknownWord(index)`, so the user can correct the phrase without starting over (US3-5). |
| `commitRestore() → Result<void>` | The atomic rename from staging to live (R12). |
| `abortRestore() → Result<void>` | |
| `signRegistration(nonce, epoch) → Result<Uint8List>` | Returns the full `POST /accounts` body bytes, dual-signed. |
| `signAuth(nonce, epoch) → Result<Uint8List>` | Returns the `POST /auth/verify` body bytes. |
| `revealRecoveryPhrase() → Result<RecoveryPhraseView>` | **[C1 manual]** class. It has a `toString()` sentinel. `words` is cleared by `dispose()`. |
| `checkPhraseWords(Map<int,String>) → Result<bool>` | Constant-time check of the re-entered words (FR-026). |

## Prekeys and sessions (`core/security/PrekeyService`, `SessionOrchestrator`)

| Method | Purpose |
|---|---|
| `buildPrekeyUpload(countEc, countKyber) → Result<Uint8List>` | Generates prekeys into `signal.db` and returns the `PUT /prekeys` body. |
| `processBundle(contactRef, bundleJson: Uint8List) → Result<BundleCheck>` | Verifies the pinned identity and the ML-DSA co-signatures, then runs libsignal `process_prekey_bundle`. Returns `ok`, or `identityMismatch` / `badCosignature` (R11). |
| `encrypt(contactRef, payload: EnvelopeInput) → Result<Ciphertext>` | CBOR-encodes, pads, and encrypts the payload with libsignal. `Ciphertext` holds `{type, bytes}` (opaque). |
| `decrypt(senderAddress, type, bytes) → Result<DecryptedEnvelope>` | Returns a typed envelope (text, hello, accept, …), or `identityMismatch` / `duplicate` / `invalid`. |
| `buildDecryptionErrorResend(…)` | libsignal `DecryptionErrorMessage` (R8). |

`contactRef` is an opaque handle that maps to a `ProtocolAddress` inside the core. It is never
logged (C14).

## Connections (`core/security/ConnectionCrypto`)

| Method | Purpose |
|---|---|
| `newPairingQr() → Result<PairingQr>` | Returns `{sessionId, qrText}`. The nonce stays native. |
| `parseConnectionQr(text) → Result<ScannedPeer>` | Returns the peer's `PublicIdentity` and a native handle for the nonce. Errors: `ownCode`, `expired`, `malformed`. |
| `newLink(requiresCodeWord, codeWord?) → Result<NewLink>` | Returns `{linkId, url}`. The secret and code word stay native. |
| `parseLink(url) → Result<IncomingLink>` | Returns `{linkId, creator: PublicIdentity, requiresCodeWord, safetyPreview}`. |
| `buildHello(…) / verifyHello(…) / buildAccept(…)` | Payloads per the wire protocol §5. Code-word comparison runs inside `verifyHello`, in constant time. |

## Trust and backup (`core/security/TrustService`, `BackupCrypto`)

| Method | Purpose |
|---|---|
| `safetyCode(contactRef) → Result<SafetyCode>` | 60 digits plus the scannable bytes (R10). |
| `compareScannedSafetyCode(contactRef, text) → Result<bool>` | Constant-time comparison. |
| `sealContactBackup(counter) → Result<Uint8List>` | Reads `data.db` and returns the padded XChaCha20-Poly1305 blob (R13). |
| `openContactBackup(blob, counter) → Result<BackupRestoreReport>` | Writes into the staging `data.db`. Returns `{contacts, blocks, rolledBack: bool}`. |

## Local data (`data.db`)

These calls are used by each feature's `data/datasources/local/` through the facade.

- **Records**: typed CRUD and paged queries for contacts, block entries, links, conversations,
  messages, the outbox, and settings.
- **Return types**: frb-generated plain Dart record classes. The data layer maps them to domain
  entities at the repository boundary (DTOs never leave `data/`).
- **Allowed in records**: decrypted message text and display names. These are user content, not key
  material, and are permitted in the data layer.
- **Never in records**: key material of any kind.
