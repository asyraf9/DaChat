# Implementation Plan: Secure Direct Messaging (Main Server)

**Branch**: `001-secure-direct-messaging` | **Date**: 2026-10-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-secure-direct-messaging/spec.md`

**Companion artifacts**:

- [research.md](./research.md): decisions R1–R23
- [data-model.md](./data-model.md)
- [contracts/](./contracts/)
- [quickstart.md](./quickstart.md)
- Gherkin `.feature` files under `test/features/*/specs/`

## Summary

This plan delivers DaChat's first slice: identifier-free, end-to-end-protected one-to-one text
messaging on the built-in main server.

**Identity and storage**:

- A **hybrid identity** (X25519 via libsignal + ML-DSA-87, dual-signed) is derived from a silently
  generated 24-word recovery phrase.
- Private keys stay in a **Rust native core** (`flutter_rust_bridge`), wrapped by a non-exportable
  hardware key.
- The native core also hosts the vendored libsignal (PQXDH + Triple Ratchet) and every encrypted
  store (SQLCipher).

**Connections**: people connect by **mutual QR** (verified) or a **single-use, 24-hour, revocable
link**. The link is not verified unless the user chose a code word, which is checked end to end with
3 attempts.

**Server**: the main server pairs **Prosody** (relay, offline-until-delivered, XEP-0191 blocking, no
archive) with a small Rust **key service**. The key service handles key-based registration, single
active device, prekey bundles, the link registry, and the opaque contact backup. Both live in
`server/`.

**Lifecycle**: restore brings back the same identity, contacts, trust, and blocks, but never history.
Restore and removal are journaled so they complete or roll back atomically.

## Technical Context

| | |
|---|---|
| **Language/Version** | Dart 3.13 / Flutter 3.47 (client). Rust stable, pinned by `rust-toolchain.toml` (native core and key service). Lua 5.4 (Prosody modules). |
| **Primary Dependencies** | Approved stack per R22: `flutter_bloc`, `get_it`+`injectable`, `freezed`, `fpdart`, `go_router`, `dio`+`retrofit`, `event_bus`, `logger`, `flutter_dotenv`, l10n. RQSM-justified: `flutter_rust_bridge`, `moxxmpp`, `connectivity_plus`, `qr_flutter`, `mobile_scanner`, `flutter_local_notifications`. Native: vendored `libsignal-protocol`, `libcrux-ml-dsa`, `bip39`, `rusqlite` (SQLCipher). |
| **Storage** | Client: three SQLCipher files in the native core (`vault.db`, `signal.db`, `data.db`), each with its own HKDF-derived key under a hardware-wrapped DEK (R4, R5). No Isar in 001. Server: PostgreSQL 17 (key service) and Prosody internal storage (blocklist, offline ≤ 30 d). |
| **Testing** | `flutter_test` + `bloc_test` + `mocktail` (unit, widget), driven by an in-repo Gherkin runner (R21). `integration_test` against the docker-compose stack (staging flavour). `cargo test` + `cargo llvm-cov` for the native core. `cargo test` for the key service. Prosody module tests with `busted`. |
| **Target Platform** | Android 10+ (API 29), iOS 16+ (primary). Linux desktop x86_64 (secondary: weaker key storage, no QR scanning, no screenshot blocking, all disclosed). |
| **Project Type** | Mobile/desktop app with a native core, plus a co-located server deliverable. |
| **Performance Goals** | SC-003: p95 ≤ 3 s online delivery, ≤ 30 s after reconnect. SC-001: first message under 3 min. SC-007: QR connect under 1 min. 60 fps in a 10k-message conversation. Cold start ≤ 2 s (R23). |
| **Constraints** | Zero server-readable content, display names, or identifiers (SC-002). No third-party egress (SC-011). Crypto config identical across `dev`/`staging`/`prod` (C6). Store keys never on the main-isolate heap (C17). Offline-tolerant onboarding (R19). |
| **Scale/Scope** | About 10k identities, 1k concurrent, 50 msg/s peak on a single-node main server (R23). 19 routes (contracts/ui-routes.md). 5 feature modules. |

All unknowns are resolved in [research.md](./research.md). **NEEDS CLARIFICATION: none.** Two
decisions are flagged **⚑ Review** for acceptance. They are listed at the end.

## Constitution Check

*GATE: checked before Phase 0 research, and re-checked after Phase 1 design.* The gate is
`.specify/memory/constitution.md` v2.1.0, which mirrors `references/flutter_constitution.md` v2.1.0.

| Principle | Gate | Pre-design | Post-design | Evidence |
|---|---|---|---|---|
| **I. Reference constitution authoritative** | Read in full. Authority order followed. No roadmap scope pulled in. | ✅ | ✅ | Sealed sender, multi-device, PIN escrow, push decryption, and mesh are all explicitly deferred (R6, R8, R15, R16). On identity and registration topics the registration blueprint wins over RQSM (R7, R11). |
| **II. Clean Architecture & DDD** | `data/domain/presentation` per feature. Pure-Dart domain. `Result<T>`. Cross-feature only via events or shared contracts. | ✅ | ✅ | Structure below. Shared value objects live in `lib/core/domain/` as a shared contract (Complexity #3). Eight domain events with their five tags (data-model §7). No feature imports another's internals. Connections uses the transport through `core/transport/` contracts (Complexity #2). |
| **III. Security & privacy (NON-NEGOTIABLE)** | C18 reuse-vetted. Key material off-heap and out of freezed, DTOs, and state. Storage tiers. Logging. No telemetry. Flavour parity. Hybrid identity. Honest claims. C20. | ✅ | ✅ | libsignal is vendored, pinned, and digest-checked (R2). Keys and stores are native-only (R1, R4, R5). The DEK is unwrapped in the crypto isolate (C15/C17). DTO bodies for crypto are opaque native bytes (C9). `AppBlocObserver` logs `runtimeType` only (C19). No FCM, no SDKs (R15, C12). M10 split stated in the privacy explainer (FR-005 copy, R6). Removal and supersede clear and close every content Cubit (C20, data-model §7). The custom crypto in audit scope is listed below. |
| **IV. Test-first, BDD (NON-NEGOTIABLE)** | `.feature` files authored now and accepted before implementation. Unit, widget, and integration layers. Coverage bars. Synthetic fixtures. | ✅ | ✅ | 10 `.feature` files, 90 scenarios and outlines, tagged by story, FR, and layer. In-repo runner (R21). 80% domain+data. 95% line+branch for `lib/core/crypto` + `lib/core/security`, **and** for `native/dachat_core` (extended, R21). KATs for all custom constructions. `// TEST ONLY` fixtures. |
| **V. Explicit, readable state** | Cubit default. Bloc only where justified. No state codegen. Thin Cubits. Page/View. Exhaustive switches. | ✅ | ✅ | Blocs exist only for security-critical flows: `ContactTrustBloc` (identity change and verification), `RestoreBloc`, `RemoveDeviceBloc`, `RedeemLinkBloc` (code-word attempts). Each records its justification in its dartdoc. Everything else is a Cubit (contracts/ui-routes.md). |
| **VI. Approved stack & vetted deps** | Only approved, or justified here with C8 for crypto. RQSM table updated in the same change. | ✅ | ✅ | All Dart packages are approved or in the RQSM table (R22). The Rust crates are justified below. The RQSM table update is a task (SQLCipher-in-native row, native-crates row). Not adopted: `isar`, `flutter_secure_storage`, `cached_network_image`, `sql_crdt` (deferred). |
| **VII. Accessible, localised, themed UI** | `AppLocalizations`, theme-only colours, `Semantics`, named spacing, adaptive layouts. | ✅ | ✅ | `privacy_baseline.feature` and per-route obligations (contracts/ui-routes.md). `DESIGN.md` does not exist yet. A task creates a minimal one before the first UI task (constitution UI rule). |

**Gate result: PASS.** The deviations are justified in Complexity Tracking.

### Crypto and native dependency justification (C8)

| Crate (native core / key service) | Threat-model rationale | Blast radius if compromised |
|---|---|---|
| `libsignal-protocol` (vendored, pinned, R2) | PQXDH plus the Triple Ratchet. Confidentiality against network, server, and harvest-now-decrypt-later adversaries. | Total loss of message confidentiality and integrity. Mitigated by pin, digest, re-pin runbook, and independent audit (RQSM §18.4). |
| `libcrux-ml-dsa` (R3) | PQ half of account authentication (R2.4a). | Authentication degrades to classical XEd25519 only. Confidentiality unaffected. |
| `bip39` (R3) | Human-writable recovery (R2.2). | Phrase-to-seed mapping errors mean a restore yields a different identity. Caught by KATs. Entropy comes from `getrandom`, not the crate. |
| `rusqlite` + bundled SQLCipher 4 (R5) | At-rest confidentiality of keys, sessions, contacts, and history against device seizure. | Plaintext at rest on a seized device. Mitigated by per-store keys (blast-radius split) and the audited SQLCipher. |
| `chacha20poly1305`, `hkdf`, `hmac`, `sha2` (RustCrypto) | Backup AEAD, key derivation, link proof, safety code. | Backup readable by the server, or forged link proofs. KATs, plus an audit of the compositions. |
| `zeroize`, `subtle`, `getrandom` | Memory hygiene, constant-time comparisons, CSPRNG. | Key residue in RAM, timing side channels, weak keys. |
| `argon2`, `secret-service` (Linux only) | Linux wrapping-key substitute (R4). | Linux at-rest protection reduced to the OS keyring or passphrase strength. Already disclosed as weaker. |
| `ciborium` (CBOR) | Deterministic payload encoding. | A parser bug in the post-decryption path. Fuzzed in CI (`cargo fuzz` target on `decrypt` payloads). |

**Custom constructions in independent-audit scope (RQSM §18.4)**: seed→key derivation (R4), the
dual-signature wrapper and prekey co-signature checks, hardware wrapping, the link proof and
code-word comparison (R9), the hybrid safety code (R10), backup AEAD and padding (R13), the
`mod_dachat_auth` token scheme (R7), the frb boundary, and the libsignal store-trait implementations.
**No production release ships before this audit.** Dev and staging use the identical stack (C6).

## Project Structure

### Documentation (this feature)

```text
specs/001-secure-direct-messaging/
├── spec.md
├── plan.md              # this file
├── research.md          # Phase 0: decisions R1–R23
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1: build + validation scenarios V1–V11
├── contracts/
│   ├── keyservice-api.md    # HTTPS API (registration, auth, prekeys, links, backup, push)
│   ├── wire-protocol.md     # QR, link, XMPP stanzas, encrypted payload kinds
│   ├── native-core-api.md   # Rust ↔ Dart facade (NativeCore)
│   └── ui-routes.md         # routes, Cubits/Blocs, protected screens, UI obligations
├── checklists/requirements.md
└── tasks.md             # Phase 2: created by /speckit-tasks, not by this command
```

### Source code (repository root)

```text
lib/
├── main_dev.dart · main_staging.dart · main_prod.dart   # flavour entry points → bootstrap()
├── bootstrap.dart              # runZonedGuarded, configureDependencies(), Bloc.observer, lifecycleResume
├── core/
│   ├── crypto/                 # ONLY importer of the native bindings
│   │   ├── bridge/             #   flutter_rust_bridge generated (never edited)
│   │   ├── native_core.dart    #   NativeCore facade (contracts/native-core-api.md)
│   │   ├── crypto_isolate.dart #   DEK unwrap → openStores (C15/C17)
│   │   └── key_wrap_channel.dart  # platform channel to the Android Keystore / iOS Secure Enclave
│   ├── security/               # IdentityService, PrekeyService, SessionOrchestrator, ConnectionCrypto,
│   │                           # TrustService, BackupCrypto, SecurityService (singleton),
│   │                           # ScreenSecurity (FLAG_SECURE / blur channel)
│   ├── transport/              # TransportDriver, TransportSwitcher (single driver), XmppTransportDriver,
│   │                           # SecureChannel contract (send/receive typed envelopes)   [Complexity #2]
│   ├── domain/                 # shared value objects: AccountAddress, PublicIdentity, DisplayName,
│   │                           # SafetyCode, MessageText                                  [Complexity #3]
│   ├── di/ · error/ · network/ (Dio + SPKI pinning interceptor) · router/ · theme/
│   ├── constants/ · extensions/ · utils/ · l10n/
│   └── state/                  # AppBlocObserver (C19), AppSessionCubit
├── features/
│   ├── identity/               # create, register, display name, recovery phrase, nudge, restore,
│   │   ├── data/ domain/ presentation/   remove from device, superseded
│   ├── connections/            # QR pairing, links (create/list/revoke/redeem), code word, handshake
│   ├── contacts/               # contact list/detail, trust + safety code, identity change, blocking,
│   │                           # blocked list, ContactBackupSyncService
│   ├── messaging/              # conversations, timeline, outbox, receipts, inbound pipeline, notifications
│   └── settings/               # settings screen, preferences, privacy disclosure, background toggle
└── l10n/app_en.arb

native/
├── rust-toolchain.toml
├── third_party/libsignal/      # git submodule, pinned  ·  libsignal.lock (commit + tree digest)
├── dachat_core/                # Rust crate: identity, sessions, stores (SQLCipher), connections,
│   ├── src/ tests/ fuzz/       #   safety code, backup; KATs in tests/kat/ (TEST ONLY vectors)
│   └── Cargo.toml
└── tool/verify_libsignal_pin.sh

android/app/src/main/kotlin/…   # KeyWrapPlugin (Keystore), ScreenSecurityPlugin, ConnectionForegroundService
ios/Runner/                     # KeyWrapPlugin (Secure Enclave), ScreenSecurity, APNs token channel
linux/                          # runner; key wrapping lives in native core (secret-service / argon2)

server/
├── docker-compose.yml          # prosody, keyservice, postgres, static /c/* page
├── prosody/
│   ├── prosody.cfg.lua         # mam OFF, in-band register OFF, offline+smacks+blocklist+cloud_notify ON
│   └── modules/                # mod_dachat_auth, mod_dachat_single_device, mod_dachat_offline_ttl (+ busted specs)
├── keyservice/                 # Rust axum service (contracts/keyservice-api.md), migrations/, tests/
├── web/                        # static install page for /c/*, assetlinks.json, apple-app-site-association
└── tools/                      # inspect_server_data.sh (SC-002), inject_bundle_mismatch.sh, race_redeem.sh

test/
├── features/{identity,connections,contacts,messaging,settings}/
│   ├── specs/                  # Gherkin .feature files (authored in this plan)
│   ├── steps/ · unit/ · widget/ · integration/
├── shared/{common_steps,support,fixtures}/   # FakeTransportDriver, FakeNativeCore, pump helpers
└── runners/gherkin_runner.dart # thin in-repo runner (R21)
integration_test/               # entry points that run the @integration scenarios on device
tool/                           # coverage_gate.sh, check_packages.sh, egress_capture.sh, log_scan.sh,
                                # generate_event_registry.dart
docs/events/                    # generated event registry (never edited)
docs/security/                  # libsignal-repin.md, security-disclosure.md (M10 split, residuals)
```

**Structure decision**: a single Flutter app following FFCA + DDD, with five bounded contexts. A
`native/` Rust workspace hosts all cryptography and encrypted storage behind one facade. A `server/`
directory holds the main-server deliverable, because 001 cannot be validated (SC-002, SC-005,
FR-034) without the server modules, and the wire contracts must be reviewed alongside the client.

### `.feature` files (accepted with this plan)

| File | Scope |
|---|---|
| `test/features/identity/specs/create_identity.feature` | US1-1..3, FR-001–007, R19 |
| `test/features/identity/specs/recovery_phrase.feature` | US3-1..5, FR-025–028, FR-031, FR-045, backup edge cases |
| `test/features/identity/specs/device_lifecycle.feature` | US3-6/7, FR-029–031, C20 |
| `test/features/connections/specs/qr_connection.feature` | US1-4, FR-008, QR edge cases, Linux |
| `test/features/connections/specs/link_connection.feature` | US2-1..5, FR-009–013, SC-005, link edge cases |
| `test/features/contacts/specs/trust_verification.feature` | US2-6..8, FR-014–017, SC-006, R11 |
| `test/features/contacts/specs/blocking.feature` | US4-1..6, FR-033–038, SC-010 |
| `test/features/messaging/specs/direct_messaging.feature` | US1-5..8, FR-018–022, SC-002–004, storage edge case |
| `test/features/messaging/specs/notifications.feature` | FR-023/024, R15 |
| `test/features/settings/specs/privacy_baseline.feature` | FR-039–044, SC-011/012 |

### Build order (RQSM §20, adapted to R1)

1. `native/` pin and verification.
2. `dachat_core`, built in this order:
   1. stores;
   2. identity and dual signatures, with KATs;
   3. libsignal store traits and sessions;
   4. connections and safety code;
   5. backup.
3. The frb facade and `FakeNativeCore`.
4. The key service and Prosody modules, with the docker-compose stack.
5. `core/` (error, DI, network pinning, transport plus `FakeTransportDriver`, security services, router,
   theme, l10n, observer).
6. Features in priority order: identity (US1 parts), then connections QR, then messaging (MVP = US1),
   then links and trust (US2), then recovery and lifecycle (US3), then blocking (US4), then settings and
   baseline.

Each story is independently testable at the end of its phase.

## Complexity Tracking

| # | Violation / deviation | Why needed | Simpler alternative rejected because |
|---|---|---|---|
| 1 | libsignal store traits and all encrypted stores live in the Rust native core, not in Dart `core/security/` as RQSM §4 lays out. Dart `core/security/` holds orchestration facades only. | Keeps ratchet state and store keys off the Dart heap and behind the FFI boundary entirely (RQSM §18.4, C17 intent). It also gives one audit surface. | Dart-side store traits would serialise session records across FFI on every message and expose them on the Dart heap. Isar has no encryption, and `sqflite_sqlcipher` lacks Linux support (R1, R5). |
| 2 | New `core/transport/` subdirectory (constitution: a new `core/` subdirectory needs a rationale). RQSM places the transport in `features/messaging/data/transports/`. | Connections (handshakes), contacts (XEP-0191 block), and messaging all need the one XMPP session. Cross-feature imports are forbidden, so the shared `SecureChannel` contract and driver must be in `core/`. | Keeping it in messaging would force connections and contacts to import messaging internals (bounded-context violation), or to duplicate an XMPP connection, which breaks single-session-per-device (R8). |
| 3 | New `core/domain/` subdirectory for shared value objects. | `AccountAddress`, `PublicIdentity`, `DisplayName`, `SafetyCode`, and `MessageText` are the shared contract between identity, connections, contacts, and messaging (constitution: "shared contracts"). | Duplicating the value objects per feature invites divergent validation of security-relevant types. |
| 4 | `server/` directory in a Flutter-app repo (Rust key service, Lua Prosody modules). | The custom server modules are named deliverables (RQSM §7.2, privacy blueprint §2.2). SC-002, SC-005, and FR-029/034 can't be validated without them, and the wire contracts change in lockstep with the client. | A separate repo splits the contract review, and stock Prosody can't do key-based auth, single-device, or the link registry. |
| 5 | Coverage gate extended to `native/dachat_core` (≥ 95% line+branch via `cargo llvm-cov`). | C13's bar targets the code that does the crypto. In this design most of it is Rust, not `lib/core/crypto`. | Gating only the thin Dart facade would leave the highest-risk code below the bar. |
| 6 | In-repo Gherkin runner instead of a package. | The constitution requires a BDD runner (`test/runners/`). No approved package exists. | `bdd_widget_test` and `flutter_gherkin` are unapproved, and the latter is unmaintained (R21). |

## ⚑ Decisions flagged for review when accepting this plan

1. **R11: what "identity change" means.** With no stable identifier, an identity change is either
   (a) a key mismatch at a known contact's address, or (b) a user-confirmed "this new connection
   replaces <contact>". Display-name matching is never used to infer a replacement. This keeps
   FR-015 and FR-016 testable without inventing a server-held identifier.
2. **R15: background delivery.** Android uses an opt-out foreground service (no FCM). iOS uses
   content-free APNs alerts through a self-hosted gateway. Linux delivers only while running. The
   alternative is FCM on Android, which brings Google metadata and a Firebase SDK.

Also note: the spec's `Status: Draft` should change to `Accepted` together with acceptance of this
plan and the `.feature` files.
