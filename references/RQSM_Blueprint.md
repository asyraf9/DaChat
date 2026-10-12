# RQSM — Resilient Quantum-Signal Mesh
### Secure Communication Blueprint · v7

<!--
  Change log
  ==========
  | Version | Change                                                            |
  |---------|-------------------------------------------------------------------|
  | v3      | Baseline: PQX3DH, Double Ratchet, sealed sender, transport mesh.   |
  | v4      | Added §1.1 Adversary Model; §5.6 async prekey establishment;       |
  |         | §5.7 group sender-keys; §5.8 message history at rest; §6.4 block + |
  |         | pairwise-keyed discovery revocation; §18.4 crypto assurance; §18.5 |
  |         | platform hardening. Corrected secure-element language, HLC-derived |
  |         | recipient IDs for store-and-forward, MAM scope, injectable         |
  |         | samples, revocation contradiction, and cross-reference errors.     |
  | v5      | Adopted `libsignal-client` (Signal's own Rust implementation, via  |
  |         | `flutter_rust_bridge`) for session establishment, PQXDH            |
  |         | (ML-KEM-1024), the Double Ratchet, group Sender Keys, and          |
  |         | classical Curve25519 identity/signatures — replacing the v3/v4     |
  |         | custom protocol implementation AND the ML-DSA layer (dropped;      |
  |         | authentication is now classical, matching Signal). Custom          |
  |         | cryptography is confined to what libsignal does not provide: P2P   |
  |         | sealed sender (Blind Trust Token — no certificate authority        |
  |         | exists in the mesh scenarios), the RQSM envelope/MAC, and the      |
  |         | discovery-beacon HMAC layer. §18.4 rewritten to a reuse-vetted-    |
  |         | first policy reflecting the narrowed audit burden.                 |
  | v6      | Aligned to Constitution v2.0.0: state management moved from   |
  |         | Riverpod to `flutter_bloc` (Cubit-first). §14 rewritten;           |
  |         | `TransportNotifier` → `TransportCubit`, `MessagingNotifier` →      |
  |         | `MessagingCubit`; `get_it` is the single DI container. Consistency |
  |         | fixes: ratchet-store wording follows the §5.4 encryption caveat;   |
  |         | §18.1 session-reference rule matches C14; §19.5/§19.8 state the    |
  |         | C13 crypto coverage bar; §20 EventBus dispatch matches C16;        |
  |         | `SecurityService` described as a singleton infrastructure service  |
  |         | (it owns the store handle), not a stateless domain service;        |
  |         | conditional `sqflite_sqlcipher` justification added; Page/View     |
  |         | split for `ChatPage`; `FakeTransportDriver` member order fixed.    |
  |         | File renamed to the version-free `RQSM_Blueprint.md`.              |
  | v7      | Aligned to `registration-migration-blueprint.md` v1.1:             |
  |         | hybrid master identity (Curve25519 + ML-DSA-87, dual signatures,   |
  |         | derived from a recovery seed, hardware-wrapped) replaces classical-|
  |         | only authentication; libsignal Triple Ratchet (SPQR) adopted from  |
  |         | v1; connection-first contact establishment (QR / single-use link)  |
  |         | replaces username lookup and server-first prekey trust; §9         |
  |         | registration is open and key-based (verification-method table     |
  |         | withdrawn); MAM removed in all modes (no server archive); §5.5     |
  |         | device loss uses recovery-phrase restore; §16 rewritten; M10 and   |
  |         | §18.4 audit scope updated. Roadmap §7 (ML-DSA) adopted.            |
-->

> **Constitution:** Flutter Constitution v2.1.0 (default resolution for all conflicts); identity and registration topics follow `registration-migration-blueprint.md`
> **Architecture:** Feature-First Clean Architecture + Domain-Driven Design (FFCA + DDD)
> **State management:** `flutter_bloc` — Cubit by default; Bloc only for event concurrency or security-critical auditable flows. No state-management code generation
> **UI convention:** Class-based widgets only (`StatelessWidget` / `StatefulWidget`, or `HookWidget` for widget-local controllers) bound to state via `BlocBuilder` / `BlocSelector` / `BlocListener` — no functional widgets
> **Platforms:** Android · iOS · Linux
> **Result type:** `fpdart` `Either<Failure, T>` via `Result<T>` typedef
> **DI:** `get_it` + `injectable` — the single container; it constructs Cubits/Blocs, and `BlocProvider` only scopes their lifetime in the widget tree
> **Events:** `EventBus` singleton via `get_it` — cross-feature communication only
> **Security priority:** Security rules take precedence over constitution defaults where they conflict.
>   Constitution v1.4.0 absorbed these rules as C1–C11 (later versions extend the series through C20), so the constitution is now the single
>   source of authority. The **[SECURITY OVERRIDE]** markers below are retained as *citations* of
>   the relevant C-rule, not as competing overrides — where a marker appears, it restates a
>   constitution rule in project-specific terms rather than contradicting one.

---

## 1. System Overview & Tech Stack

| Concern | Choice | Notes |
|---|---|---|
| Framework | Flutter | — |
| Architecture | FFCA + DDD | Feature-First, bounded contexts |
| State management | `flutter_bloc` | Cubit-first; see §14 |
| Primary protocol | XMPP via `moxxmpp` | Self-hosted Prosody or ejabberd |
| Fallback protocols | WiFi Direct → BLE Mesh → Ultrasound → LoRa/SDR | Priority-ordered |
| Security | `libsignal-client` (PQXDH · ML-KEM-1024, Triple Ratchet = Double Ratchet + SPQR, Sender Keys) + hybrid identity (Curve25519 + ML-DSA-87, dual-signed) | Session/ratchet/group crypto and authentication via libsignal; custom layer confined to the P2P sealed sender and the envelope/discovery HMAC — see §4, §18.4 |
| CRDT sync storage | `sql_crdt` | Justified addition — see §7.3 |
| Ratchet state storage | Dedicated isolated encrypted store | Separate from the main app store. Isar only if the pinned version provides at-rest encryption; otherwise SQLCipher or app-layer AEAD — see §5.4 caveat |
| History storage | Encrypted local store (hardware-derived key) | Readable history at rest — see §5.8 |
| Error typing | `fpdart` — `Either<Failure, T>` as `Result<T>` | — |
| DI container | `get_it` + `injectable` | Single container; constructs Cubits/Blocs (`@injectable`) |
| Cross-feature events | `event_bus` | One singleton; no direct feature imports |
| Secure storage | Platform-channel hardware keystore | Long-term wrapping key hardware-resident; derived keys are ephemeral in the Dart heap — see §5.4 |

### Non-Standard Package Justifications

The following packages are not in the constitution's approved stack and are justified here:

| Package | Justification |
|---|---|
| `libsignal-client` (vendored, pinned; bound via `flutter_rust_bridge`) | Signal's own Rust implementation of PQXDH (ML-KEM-1024 + X25519), the Triple Ratchet (Double Ratchet + SPQR), Sender Keys, sealed sender, and Curve25519 (XEd25519) signatures. Replaces the former custom protocol stack and `mlkem_native`. **Not supported for third-party reuse and has no official Dart binding**, so it is vendored at a pinned commit and bound via `flutter_rust_bridge`; the pin is digest-verified per §18.2 M2. Reuse-vetted-first rationale in §18.4. |
| ML-DSA implementation (vetted; chosen in the plan, bound through the same native boundary) | ML-DSA-87 keypair and dual signatures for the hybrid master identity (§5.1, registration blueprint R2.1a/R2.4a). libsignal provides no ML-DSA. Must be an audited implementation; it is never hand-written (C18). |
| BIP39-style mnemonic / seed derivation (vetted) | Recovery seed and mnemonic from which the master identity is derived (registration blueprint R2.1, R2.2, R3.1). |
| `moxxmpp` | XMPP client library. Required for the primary transport protocol. No approved-stack alternative. |
| `connectivity_plus` | Network reachability signal feeding `TransportSwitcher` and the `SignalQuality` observer (§3, §7). No approved-stack alternative. |
| QR generate + scan (e.g. `qr_flutter` + `mobile_scanner`) | Level 0 out-of-band pairing and safety-number verification (§16). Camera-scanned QR is core to the verified-contact upgrade path. |
| Local notifications (e.g. `flutter_local_notifications`) | Delivery of the privacy blueprint's granular notification controls. Content stays local; see §18.5 push-metadata caveat. |
| `sqflite_sqlcipher` (conditional) | SQLCipher-backed encrypted store for the ratchet (§5.4), history (§5.8), and possibly CRDT (§7.3) stores, **only if** the pinned Isar version lacks at-rest encryption. Decide and record in the plan before the ratchet store is trusted. |
| `flutter_rust_bridge` | FFI bridge binding `libsignal-client` (Rust) into Dart. Also the boundary that keeps key material in native memory where it can be zeroised (§18.4) — the Dart GC cannot. Digest-pinned per §18.2 M2. |
| `sql_crdt` | SQLite-backed CRDT store with Hybrid Logical Clock semantics. Isar has no CRDT primitive; CRDT is a core architectural requirement for offline-first sync. |
| `nearby_connections` | WiFi Direct / Multipeer Connectivity for Scenario 2 transport. No approved-stack alternative. |
| `flutter_reactive_ble` | BLE GATT peripheral + central for Scenario 3 transport. No approved-stack alternative. |
| `flutter_pcm_sound` + `fftea` | PCM audio I/O and FFT for Scenario 4 acoustic transport. No approved-stack alternative. |
| `usb_serial` (Android) | USB-OTG serial for Scenario 5 SDR link on Android. No approved-stack alternative. |
| `flutter_libserialport` (Linux) | Serial port for Scenario 5 SDR link on Linux. No approved-stack alternative. |

### 1.1 Adversary Model

RQSM's guarantees are stated against named adversaries. A measure is "adequate" only relative to the adversary it targets; **no single measure in this document defends against all of them**, and several adversaries have deliberate residual exposure.

| Adversary | Capabilities assumed | What RQSM defends | Residual exposure |
|---|---|---|---|
| **Malicious main-server operator** | Reads all data and metadata the main server touches; logs, correlates, retains indefinitely | Sender identity and content of sealed traffic; external-server address/credentials in invitations | Recipient account identity, delivery events, approximate timing and payload size (§2) |
| **Malicious external-server operator** | Same, for chats routed to that server | Content (E2EE) and sender identity (sealed sender) | Recipient identity, delivery metadata |
| **Relay peer (mesh / sneakernet)** | Stores and forwards opaque envelopes; may drop, delay, duplicate, inspect | Content, sender identity, ratchet material | Envelope size, relay timing, coarse graph position; CRDT metadata at rest (§7.3) |
| **Passive radio observer** | Sniffs BLE / WiFi / acoustic / LoRa airtime near the device | Sender identity — discovery beacons are per-contact HMACs (§6, §6.4) | Presence of *a* device; traffic volume and timing |
| **Ex-contact (post-block)** | Retains any per-contact discovery secret shared before revocation | Future discovery once blocked — the pairwise secret is deleted (§6.4) | Observations already made before the block |
| **Device thief / forensic extraction** | Full read of storage at rest; cannot use the hardware secure element without unlock | Ratchet keys and history at rest (hardware-derived encryption; §5.4, §5.8) | Anything decrypted in RAM at seizure time; OS backups if not disabled (§18.5) |
| **Push infrastructure (APNs / FCM)** | Sees push-relay traffic when a push proxy is used | Content | Message-timing metadata to Apple / Google (§18.5) |
| **Global passive network observer** | Sees all network flows | Content and sender identity | Existence and timing of communication events |

RQSM explicitly does **not** provide: anonymity of the *recipient* from a delivering server, traffic-analysis resistance, or protection of key material resident in RAM during an unlocked-device seizure. Users whose threat model requires any of these MUST be told so plainly (§2, §18).

---

## 2. Infrastructure Privacy Modes

The application operates across three distinct infrastructure privacy modes. The RQSM layer behaves differently in each. All modes use libsignal (PQXDH session establishment + Double Ratchet) and the `EncryptedEnvelope` pattern for content encryption.

| Mode | Data Lives On | Main Server Observes | Identity |
|---|---|---|---|
| **Default Chat** | Main XMPP server | Message routing metadata; sender and recipient identities (as identity public keys, never human-readable names) | Master identity key |
| **Private Server Chat** | External XMPP server | An opaque sealed blob was delivered **to a known recipient account**; approximate timing and payload size. Sender identity and content are blind. | Same master identity key; channel is opaque |
| **Pure E2EE** | No server-side persistence | An opaque sealed blob was delivered **to a known recipient account**; approximate timing and payload size | Same master identity key |

> **"Zero knowledge" qualification:** "Private Server Chat" and "Pure E2EE" modes are *sender-anonymous and content-blind* — not event-blind and not recipient-anonymous. Any server that *delivers* a message must know the recipient account to route to it: the XMPP `to` attribute remains even when `from` is replaced by a relay token (§7.2, Scenario 1). Sealed sender conceals the sender and the content; it does not conceal that a delivery to a given recipient occurred, nor its timing and size. Users whose threat model requires concealing the existence of a communication channel should treat sealed sender as a content protection mechanism, not a traffic concealment mechanism.

> **Layer 2 signal availability:** In Pure E2EE mode, server-relayed presence signals — read receipts, typing indicators, online status — are unavailable. There is no relay mechanism for short-lived signals without server-side state. This is an accepted trade-off of the pure mode. Users should be informed at the point of selecting this mode.

---

## 3. Core Design Patterns

| Pattern | Role |
|---|---|
| **Strategy Pattern** | Encapsulates each transport protocol into an interchangeable `TransportDriver` |
| **Driver-Plugin Architecture** | `MessagingRepository` delegates to a `TransportSwitcher` that holds an ordered list of `TransportDriver` implementations and selects the highest-priority available driver |
| **Repository Pattern** | Abstracts the active transport (XMPP vs. P2P Mesh) from the Domain layer |
| **Observer Pattern** | `ConnectivityPlus` + custom `SignalQuality` stream feed `TransportSwitcher`; driver changes propagate as domain events via `EventBus` to `TransportCubit` |
| **Clean Architecture** | Domain `Message` entities are immutable, transport-agnostic, and pure Dart |
| **Event-Driven** | Significant state changes emit domain events via `EventBus`; no direct cross-feature imports |

### 3.1 Canonical Class Names

The following names are authoritative throughout this document and in all generated code. No abbreviations or aliases.

| Concept | Canonical Name |
|---|---|
| Holds driver list; selects active driver | `TransportSwitcher` |
| Security service (`core/security/`, `get_it` singleton); orchestrates libsignal (PQXDH, Double Ratchet, Sender Keys) + custom P2P sealed sender | `SecurityService` |
| Publishes/fetches libsignal prekey bundles; async session establishment (§5.6) | `PrekeyService` |
| Wraps libsignal Sender Keys — distribution, rotation (§5.7) | `GroupSessionService` |
| Owns per-contact discovery secrets; blocking/revocation (§6.4) | `DiscoveryService` |
| Encrypted readable-history persistence (§5.8) | `HistoryStore` |
| Manages CRDT sync on peer discovery | `SyncEngine` |
| Cubit exposing transport state to the UI | `TransportCubit` |
| Cubit exposing conversation/message state to the UI | `MessagingCubit` |
| XMPP driver | `XmppTransportDriver` |
| WiFi Direct driver | `WifiDirectTransportDriver` |
| BLE Mesh driver | `BleMeshTransportDriver` |
| Acoustic/Ultrasound driver | `AcousticTransportDriver` |
| LoRa/SDR driver | `ExternalRadioTransportDriver` |

### 3.2 EventBus Integration

The `EventBus` singleton is registered in `core/di/event_bus_module.dart` before any feature module initialises. Transport and security events are dispatched from use cases, domain services, or **infrastructure services registered in `get_it`** (e.g. `TransportSwitcher`, which lives in `data/transports/`) — never from presentation code. `TransportSwitcher` is an infrastructure service, not a domain service, so its dispatch of `TransportDriverSwitched` is explicitly permitted under the amended constitution EventBus rule (the intent of that rule is to keep dispatch out of the UI, not to bar infrastructure). Consumers are Cubits/Blocs or domain services.

```dart
// core/di/event_bus_module.dart
@module
abstract class EventBusModule {
  /// Registers the application-wide [EventBus] singleton.
  @singleton
  EventBus get eventBus => EventBus();
}
```

Consumers subscribe in their constructor and cancel in `close()` — see `TransportCubit` in §14.

---

## 4. Module Boundaries: `core/crypto/` vs `core/security/`

These two modules have strictly distinct responsibilities. The boundary is absolute.

### `lib/core/crypto/` — libsignal FFI Bindings & Raw Primitives

No business logic. No Flutter imports. No `freezed`. Pure Dart only.

- `libsignal-client` FFI bindings (via `flutter_rust_bridge`) — the sole home of the protocol
  implementation: PQXDH (ML-KEM-1024 + X25519), the Double Ratchet, Sender Keys, sealed sender, and
  Curve25519 (XEd25519) identity/signatures. **These protocols are NOT reimplemented in Dart.**
- Any remaining glue primitives NOT provided by libsignal and required by the custom P2P layer:
  HMAC-SHA-256 (envelope MAC and discovery beacons) and HKDF-SHA-256 for the discovery secret.

> **No swap-to-custom:** the crypto core *is* the vetted `libsignal-client` implementation, held in
> native (Rust) memory where it can be zeroised — the Dart GC cannot reliably clear key material
> (§18.4). Any future swap is between *vetted* implementations, never a hand-rolled reimplementation
> of a protocol libsignal already provides (§18.4, constitution C18).

> **Import rule:** `libsignal-client` bindings and all raw crypto primitives may only be imported
> inside `lib/core/crypto/`. Any import of these packages outside `core/crypto/` is a constitution
> violation.

### `lib/core/security/` — High-Level Security Constructs

Built on top of `core/crypto/`. Orchestrates protocols. No Flutter imports. Pure Dart only.

- `EncryptedEnvelope` — RQSM envelope model, serialisation, layer assembly (custom — not libsignal)
- `SessionOrchestrator` — drives libsignal PQXDH session establishment and the Double Ratchet
- `GroupSession` — drives libsignal Sender Keys (distribution, rotation)
- `SealedSender` — **split**: libsignal sealed sender in server-backed XMPP mode; the custom
  `BlindTrustToken` path in P2P/mesh where no certificate authority exists (§5.3, §7.2)
- `SecurityService` — coordinates the above. It owns the isolated ratchet-store handle (§5.4), so it is a `get_it` singleton infrastructure service, **not** a stateless domain service under the constitution's DDD rules; it holds no key material on the Dart heap (§18.4)
- libsignal **store-trait implementations** (`SessionStore`, `IdentityKeyStore`, `PreKeyStore`,
  `SignedPreKeyStore`, `KyberPreKeyStore`, `SenderKeyStore`) backed by the encrypted store (§5.4)
- `RatchetSessionRepository` interface — session-state persistence contract (implementation in `data/`)

### 4.1 `freezed` Carve-Out — **[SECURITY OVERRIDE]**

The constitution mandates `freezed` for all data classes. **This rule does not apply to classes that hold raw key material or ratchet chain state.** `freezed` auto-generates `toString()` that serialises all fields. A class holding key bytes that is passed to a logger, stored in a crash report, or printed in a stack trace becomes a key exfiltration vector.

**Rule:** Classes in `core/crypto/` or `core/security/` that hold raw key material — private keys, shared secrets, ratchet root keys, chain keys, or message keys — must be implemented manually with the following constraints:

- `toString()` returns the sentinel string `'[SecuritySensitive — contents withheld]'` — no exceptions, no debug modes.
- `==` and `hashCode` compare only a stable, opaque identifier field (e.g. a session reference UUID), never key bytes.
- `copyWith()` is implemented manually if required.
- No `toJson()` or `fromJson()` methods. No JSON serialisation of key material under any circumstances.

Classes that hold only ciphertext (opaque bytes, already encrypted) may use `freezed` with caution. Verify that the generated `toString()` does not expose ciphertext in a format useful to an attacker.

### 4.2 No DTO Rule for Security-Sensitive Classes

`data/models/` DTOs are for transport-layer serialisation via `json_serializable`. No DTO may be created for any class in `core/crypto/` or `core/security/`. There is no legitimate serialisation path for raw cryptographic material through the DTO layer.

---

## 5. Security Architecture — The "Armor"

### 5.1 Hybrid Post-Quantum Key Agreement (PQXDH via libsignal)

Session establishment uses **libsignal's PQXDH** — Signal's own hybrid handshake — **not a
reimplementation**. Every new session derives a shared secret combining classical and
post-quantum key exchange, orchestrated by `SessionOrchestrator` (§4) over the libsignal binding:

```
SS = libsignal PQXDH( X25519 leg ∥ ML-KEM-1024 leg )
```

A quantum computer breaking X25519 cannot recover `SS` — the ML-KEM-1024 layer independently
maintains secrecy. Both legs must be compromised simultaneously. **Do not hand-write this
construction**; call libsignal.

- **Classical leg:** X25519 Diffie-Hellman (libsignal)
- **PQ leg:** ML-KEM-1024 (libsignal's PQXDH parameter — do not deviate from the vetted set)
- **Ratchet:** libsignal **Triple Ratchet**: the Double Ratchet plus the Sparse Post-Quantum Ratchet
  (SPQR), mixed by KDF, initialised from `SS` and enabled from v1 (registration blueprint §2.1 scope
  note). Use libsignal's implementation; never hand-write SPQR.
- **Identity / signatures — hybrid [v7]:** the master identity is a **Curve25519 (XEd25519) keypair
  plus an ML-DSA keypair**, both derived from the user's recovery seed (registration blueprint
  R2.1–R2.1b). Every signature made with the master identity MUST be a **dual signature** (XEd25519 +
  ML-DSA over the same payload), and verifiers MUST require both (registration blueprint R2.4a). In
  RQSM this covers:
  - account authentication to a server (challenge–response);
  - device authorization and migration triggers;
  - signed-prekey and Kyber-prekey signatures — each prekey bundle carries an ML-DSA co-signature
    that the client verifies *before* handing the bundle to libsignal;
  - the identity material exchanged in a connection QR/link (§16), so verification covers both public
    keys.
- **ML-DSA parameter set:** ML-DSA-87 (NIST category 5, matching ML-KEM-1024) unless the plan
  justifies ML-DSA-65 for size. The ML-DSA implementation MUST be a vetted library bound through the
  same native boundary as libsignal (C8, C18). The dual-signature *wrapper* is RQSM code and in audit
  scope (§18.4).

> **Post-quantum scope (v7):** handshake confidentiality is PQ (ML-KEM-1024 in PQXDH). Ongoing
> confidentiality and post-compromise recovery are PQ via SPQR in the Triple Ratchet.
> **Account-level authentication** (server sign-in, device authorization, migration, prekey bundle
> co-signatures) is hybrid and requires forging *both* XEd25519 and ML-DSA. **Residual:** libsignal's
> internal per-message and sealed-sender sender authentication still rests on Curve25519. A future
> quantum adversary could therefore forge a *live* sealed-sender sender certificate, but cannot
> substitute a contact's identity, because identity keys are bound by the dual-signed connection and
> prekey material. State this residual honestly (§18.2 M10).

> **Isolate / native-memory note:** libsignal holds session key material in native (Rust) memory,
> off the Dart heap, which satisfies the bulk of the "minimise key lifetime in the main heap"
> requirement directly. The remaining Dart-side concern is the **encrypted store**: the isolated
> ratchet store (§5.4) is opened and accessed inside a dedicated crypto Isolate so its
> hardware-derived encryption key never surfaces on the main thread heap. See §18.4.

### 5.2 The Encrypted Envelope Pattern

The `EncryptedEnvelope` is the **custom RQSM wrapper** used for P2P/mesh transport (libsignal's
own sealed sender is used instead in server-backed XMPP mode — see §5.3, §7.2). Every message is
wrapped before being handed to any `TransportDriver`. The driver receives only an opaque byte
sequence — it has no access to plaintext, sender identity, or ratchet material. The payload inside
is a libsignal ciphertext (Double Ratchet or Sender Key message); RQSM only adds the outer/inner
headers and MAC.

```
┌──────────────────────────────────────────────────┐
│ Outer Header (unencrypted — transport-visible)   │
│   Ephemeral Recipient ID: HMAC(IK_recipient,     │
│     SlotOf(HLC_created)) truncated to 4 bytes     │
│   HLC creation timestamp (needed for slot + sync) │
│   MAC over the entire envelope                    │
├──────────────────────────────────────────────────┤
│ Inner Header (encrypted for recipient only)      │
│   Sealed Sender Certificate (or session token)   │
│   Sender's long-term Public Key (first msg only) │
├──────────────────────────────────────────────────┤
│ Payload (encrypted for recipient only)           │
│   Message content                                │
│   libsignal Double Ratchet / Sender Key headers  │
└──────────────────────────────────────────────────┘
```

The outer header is the only part visible to any transport layer or relay. It reveals nothing about sender identity. The recipient ID is an HMAC value — indistinguishable from random bytes to any observer without the recipient's identity key.

> **Store-and-forward recognition:** the recipient ID is keyed on `SlotOf(HLC_created)`, the hourly slot derived from the envelope's own HLC creation timestamp — **not** wall-clock time. A sneakernet envelope relayed days later (§7.3) still matches, because the recipient recomputes the slot from the carried HLC timestamp. The HLC timestamp is already unencrypted metadata used by the CRDT sync, so this exposes nothing new; the cost is that recognition is bound to that visible timestamp. (Live BLE presence discovery in §6 is unaffected — it uses current-slot beacons with a ±1 tolerance window because presence is inherently real-time.)

> **Envelope MAC:** the outer-header MAC is `HMAC-SHA-256` under a dedicated MAC key `HKDF(session_root, "rqsm-envelope-mac")`, separate from any encryption key. It authenticates the entire envelope (outer header ∥ inner header ∥ payload) and is verified before any decryption attempt.

> **PQ object sizes vs bandwidth — session-token scheme:** the per-message sealed-sender certificate stays *small* (libsignal's Curve25519 sender certificates: 32-byte keys, 64-byte signatures). The v7 hybrid identity's ML-DSA-87 keys (~2.6 KB) and co-signatures (~4.6 KB) travel only with connections and prekey bundles, never per message. The large post-quantum objects are the **ML-KEM-1024** encapsulation key and ciphertext exchanged during **session establishment** (PQXDH prekey handshake, §5.6) — on the order of ~1.5 KB each — not per message. So the bandwidth pressure is concentrated at establishment over BLE (§7.2 Scenario 3) and acoustic (Scenario 4), and the session cannot be established over the lowest-bandwidth links. The **session-token scheme** still applies per-message: the sender's identity key and certificate are sent only on the first message of a session; subsequent messages carry a short opaque **session token**. Bandwidth-cost analysis per transport remains a required output of the driver specs (§7.2).

### 5.3 Sealed Sender

> **Sealed sender is split.** In server-backed XMPP mode, RQSM uses **libsignal's own sealed
> sender** (server-issued sender certificates). The Blind Trust Token below is the **P2P/mesh** path
> only, where no certificate authority exists — libsignal's sealed sender cannot serve it (§7.2).

#### 5.3.1 P2P Sealed Sender — Blind Trust Token

In P2P mode there is no central server to verify sender certificates. Sealed Sender in P2P uses a **Blind Trust Token (BTT)** exchanged at Level 0 pairing (QR scan). The BTT lets the recipient confirm the sender's validity without the transport layer learning the sender's identity.

The BTT is a **dual signature** by the sender's master identity (§5.1, registration blueprint R2.4a):
`XEd25519_Sign ∥ ML-DSA_Sign (sender_master_private, recipient_IK_public ∥ nonce)`. It is exchanged once
at pairing, so its ML-DSA size does not affect per-message bandwidth.

On receipt, the recipient verifies the BTT against the sender's public key recovered from the Inner Header after decryption. The transport layer never sees either key.

> **BTT nonce lifecycle and purpose:** the `nonce` is a 128-bit single-use random value, persisted by the recipient after first acceptance; any BTT replaying a seen nonce is silently rejected. Binding to `recipient_IK_public` makes the token non-transferable — it proves to *this* recipient that the holder controls `sender_IK_private`, without exposing the sender's identity to the transport. In P2P there is no server certificate to fall back on, so the BTT is the sole sender-authenticity proof; its security reduces to the unforgeability of *both* XEd25519 and ML-DSA, and the secrecy of the sender's master identity key. Authentication here is hybrid post-quantum (§18.2 M10).

#### 5.3.2 Private Channel Establishment via Sealed Sender

When two users wish to move a conversation to an external XMPP server, the invitation handshake is performed without the main server learning the sender's identity or the invitation's content.

The invitation payload must contain all of the following — none are optional:

| Field | Purpose |
|---|---|
| `nonce` | 128-bit random value — single-use, invalidated after first use |
| `expiry` | UTC timestamp — invitation invalid after 24 hours from creation |
| `recipientKeyFingerprint` | `SHA-256(recipient_IK_public)` — binds invitation to Bob only; non-transferable |
| `externalServerAddress` | Encrypted to the recipient using the **hybrid KEM** (ML-KEM-1024 + X25519) via libsignal PQXDH, not X25519 alone — these are among the most sensitive fields and must retain PQ confidentiality |
| `externalServerCredentials` | Encrypted to the recipient using the **hybrid KEM** (ML-KEM-1024 + X25519) |
| `senderSignature` | Dual signature (XEd25519 + ML-DSA, §5.1) by the sender's master identity over `nonce ∥ expiry ∥ recipientKeyFingerprint ∥ encrypted_address ∥ encrypted_credentials` |

**Handshake sequence:**

1. Alice constructs the invitation payload, signs it, wraps it in an `EncryptedEnvelope` addressed to Bob using sealed sender.
2. The main server receives an opaque sealed blob. It observes: a delivery event occurred, approximate timestamp, approximate payload size. It does not observe: sender identity, content, or the existence of an external server invitation.
3. Bob's client decrypts the Inner Header to recover Alice's public key, verifies the Curve25519 signature, checks expiry and nonce freshness, and confirms `recipientKeyFingerprint` matches Bob's own `IK`.
4. If all checks pass, Bob's client surfaces the invitation. Bob accepts; the private channel is established on the external server.
5. The nonce is persisted in Bob's local store. Any replay of the same invitation is silently rejected.

### 5.4 Ratchet State Persistence

libsignal's Double Ratchet generates per-message ephemeral keys and expects the consumer to persist protocol state by implementing its **store traits** — `SessionStore`, `IdentityKeyStore`, `PreKeyStore`, `SignedPreKeyStore`, `KyberPreKeyStore`, and `SenderKeyStore`. RQSM implements these traits over a dedicated encrypted store; the ratchet *logic* is libsignal's, the *persistence and at-rest encryption* are RQSM's. This state must survive app restarts. The honest guarantee is: the long-term **wrapping key never leaves the hardware secure element**, and the derived store key is **ephemeral in memory and never persisted**. Session key material handled by libsignal lives in native memory (§5.1); the store's derived encryption key unavoidably exists as bytes in app memory while opening the store — no pure-Dart design can prevent that (§18.4). "Never leaves the secure element" applies only to the long-term wrapping key.

- **Storage:** A **dedicated, isolated encrypted store** opened exclusively by `SecurityService`, inside the crypto Isolate (§5.1), separate from the main application store. It backs the libsignal store-trait implementations (session, identity, prekey, signed-prekey, Kyber-prekey, and sender-key state).
  - **Encryption-availability caveat:** stable Isar 3.x does **not** ship a built-in at-rest encryption option — that capability was only in unreleased Isar 4 work. Do **not** assume "Isar encryption on" without verifying it against the pinned Isar version. If the pinned version lacks native encryption, use a SQLCipher-backed store (`sqflite_sqlcipher`) or application-layer AEAD over the collection instead. This must be resolved before the ratchet store is trusted.
- **Encryption key:** Derived fresh on every cold start via a **platform-channel call** to the hardware keystore. The derived key opens the store inside the platform-channel response handler / crypto Isolate, minimising its lifetime in the main heap. **The derived key is never persisted** and never passed to `flutter_secure_storage` — it is re-derived each session from the hardware-resident wrapping key.
  - **Android / iOS:** Android Keystore / iOS Secure Enclave hold the non-exportable wrapping key.
  - **Linux:** desktop Linux generally has **no secure element**. Use the OS Secret Service (`libsecret` / GNOME Keyring / KWallet) to hold the wrapping key where available; where it is not, fall back to a passphrase-derived KEK via a memory-hard KDF (Argon2id). The Linux key-storage guarantee is explicitly weaker than mobile and MUST be disclosed to Linux users.
- **On restart:** `SecurityService` derives the store key via platform channel, opens the isolated store, and loads ratchet session state before the messaging feature initialises. Sessions with missing or corrupted state are flagged as `RatchetErrorCode.sessionBroken` and the `RatchetStateBroken` domain event is dispatched.
- **Ratchet gate:** The `SyncEngine` must confirm `RatchetState.ready` before decrypting any incoming bundle or encrypting any queued outbound message.
- **Blast-radius isolation:** A compromise of the main application store does not expose ratchet state. The stores have separate encryption keys and separate database files. See §5.8 for readable history, which is a separate store with its own key.

### 5.5 Key Rotation and Revocation

- **Discovery rotation:** each per-contact discovery beacon `HMAC(DS_ab, TimeSlot)` (§6.4) rotates automatically each UTC hour. `TimeSlot = floor(UTC_epoch_seconds / 3600)`. No manual action required.
- **Blocking a single contact:** deleting the pairwise discovery secret `DS_ab` revokes that one contact's ability to discover the device, with no effect on other contacts and no re-pairing (§6.4).
- **Device loss (identity not compromised):** the user restores the master identity from the recovery phrase (registration blueprint R3.1). The identity keys are unchanged, so contacts see no identity change. Sessions are re-established from fresh prekeys, and message history is not restored.
- **Identity compromise, or no recovery phrase:** the user creates a new identity (new recovery seed) and re-connects. Contacts see an identity change and must re-verify. On the re-pairing device, the old identity key is removed from all contact lists and every Blind Trust Token and discovery secret derived from it is deleted **locally**.
- **No automatic revocation propagation:** There is no server push for identity revocation. A *contact's* device continues to trust the old identity key — including any BTT it already holds — until that contact re-verifies. The local deletion above does not propagate; only per-contact blocking (deleting `DS_ab`) is immediate, and it revokes discovery, not a contact's already-cached trust in the old key. This asymmetry is a known limitation of the serverless model and must appear in the app's security disclosure.

### 5.6 Connection-First Session Establishment — Connections + Prekey Bundles [v7]

There is **no username directory and no server-side lookup** (registration blueprint §1.1). Two people
first establish a **connection** that exchanges their identity public keys directly. Only then does the
initiator fetch the other person's prekey bundle from the server and run PQXDH. The bundle is located by
identity key, not by any human-readable handle.

- **Connection (identity exchange):** by **in-person QR scan** (mutual, visual) or a **shareable link**
  that is single-use, expires (default 24 h), and is revocable (registration blueprint R1.5, R1.5a). The
  QR/link carries both identity public keys (or a binding hash of the ML-DSA key where QR capacity
  requires it; see §16) plus an end-to-end-encrypted, self-asserted display name (R1.9).
- **Published per user (libsignal `PreKeyBundle`):** the Curve25519 identity key (`IK`), a signed prekey
  (`SignedPreKey`, rotated periodically), a **Kyber prekey** (ML-KEM-1024 encapsulation key), and a pool
  of one-time prekeys (classical and Kyber) replenished by the client. Every prekey signature is dual
  (XEd25519 + ML-DSA, §5.1). The client rejects any bundle whose identity keys differ from those received
  in the connection, or whose ML-DSA co-signature fails.
- **Distribution:** the user's server hosts the bundle. A session can be initiated while the contact is
  offline.
- **Trust states:**
  - QR connection → `verified` (in-person, mutual visual confirmation).
  - Link connection → `unverified`, unless the initiator required **ID confirmation** (code word or
    video call, registration blueprint R1.6–R1.7a) and it succeeded. A later safety-code comparison
    (§16) can also upgrade it.
  - A contact whose identity later changes MUST trigger a hard warning (if `verified`) or a visible
    notice (if `unverified`) — never a silent re-trust.
- **One-time prekey exhaustion:** if the one-time pool is depleted, the server serves a bundle without a
  one-time prekey; libsignal still establishes the session, with reduced first-message forward secrecy.
  Clients replenish eagerly.

> **Trust-anchor note (v7):** because identity keys arrive out of band in the connection, the server
> can no longer substitute a contact's identity by swapping a bundle — the client pins the identity
> from the connection. The residual MITM surface moves to the **link channel**: whoever intercepts or is
> forwarded a link can complete that one connection. Single-use links bound that to one connection, and
> optional ID confirmation is the defence (adversary "malicious main-server operator" is reduced to
> delivery-metadata observation, §1.1).

> **Future work — "super-secure" QR-only contacts:** a per-contact or per-user policy that accepts only
> QR connections. Deferred to a later revision.

### 5.7 Group Messaging — Sender-Keys

The privacy blueprint's group features (folders of group chats, moderators, membership-change briefings, pile-on threat framing) require group cryptography. Pairwise fan-out does not scale over BLE mesh or acoustic transports. RQSM uses **libsignal Sender Keys** (`SenderKeyStore`, `GroupSessionBuilder`) — not a reimplementation.

- **Per-sender key:** each group member holds a libsignal sender key — a symmetric chain key advanced by a hash ratchet per message (no DH), plus a Curve25519 signing key (libsignal) for in-group message authentication.
- **Key distribution:** a member distributes its `SenderKeyDistributionMessage` to every other member over the existing **pairwise libsignal sessions** (§5.1). New members receive current sender keys pairwise on join.
- **Sending:** libsignal encrypts a message once under the sender's current sender-key state and signs it; the single ciphertext is delivered to all members via the active transport, wrapped in the P2P `EncryptedEnvelope` (§5.2) on mesh transports.
- **Membership management:** group membership is an explicit, signed, ordered list. **On member removal, every remaining member rotates its sender key** (distributing a fresh `SenderKeyDistributionMessage` pairwise) so the removed member cannot read future messages. Additions do not force rotation; the joiner receives no history (sender keys are forward-only).
- **Authentication:** libsignal's per-message Curve25519 signatures prevent one member forging another's messages; there is no shared group signing secret.
- **Forward secrecy / PCS limits:** the hash-ratchet sender key provides forward secrecy but **weaker post-compromise security than pairwise Double Ratchet** — a compromised sender key stays valid until the next membership-driven rotation. This is the accepted trade-off for P2P/mesh viability.

> **Future work — MLS:** if realistic group sizes grow large (dozens+), migrate to MLS (RFC 9420) for logarithmic-cost membership changes and stronger PCS. MLS's near-simultaneous-online requirement fits intermittent mesh/sneakernet transports poorly, so it is deferred until group scale justifies it. libsignal Sender Keys is the v5 approach.

> **Layer 3 dependency:** every group-scoped feature in the privacy blueprint (moderator trusted-tier, membership-change briefings, group-add controls) depends on this section. Group features MUST NOT ship before sender-keys is implemented and audited (§18.4).

### 5.8 Message History at Rest

Double Ratchet forward secrecy deletes a message key after use, making the stored `EncryptedEnvelope` ciphertext **permanently undecryptable**. Readable chat history therefore CANNOT be reconstructed from the CRDT ciphertext store. Scroll-back history must be persisted **decrypted-then-re-encrypted under a local storage key**.

- **Store:** a dedicated local history store (subject to the §5.4 encryption-availability caveat), separate from the ratchet store and the CRDT sync store.
- **Encryption:** encrypted at rest under a **hardware-derived local storage key** using the same platform-keystore mechanism as the ratchet store (§5.4) — never a hardcoded or `flutter_secure_storage`-held key.
- **Lifecycle:** on receipt, an envelope is decrypted once (the ratchet advances), the plaintext is written to the encrypted history store, and the ratchet ciphertext may be discarded. Auto-delete timers and Pure-E2EE retention policy operate on this store.
- **Blast radius:** compromising the CRDT sync store exposes only metadata (§7.3), not readable history; compromising the history store exposes decrypted content and is the highest-value at-rest target — hence hardware-derived keying and OS-backup exclusion (§18.5) are mandatory.

> This resolves where readable history lives, a question the prior revision left open. It also means "message deletion" (privacy blueprint §3.5) must delete from this store, not merely from the UI.

---

## 6. Hybrid Discovery Model — Trust & Stealth

| Level | Method | Privacy | Description |
|---|---|---|---|
| **Level 0 — Verified** | Out-of-band QR scan | Maximum | Exchanges PQ long-term identity keys. No radio activity until pairing is confirmed. Gates access to all subsequent stealth discovery. |
| **Level 1 — Stealth** | HMAC BLE advertising | High | Per-contact `HMAC(DS_ab, TimeSlot)` truncated to 4 bytes (§6.4). Rotates hourly. Indistinguishable from random noise to non-contacts and revocable per contact. |
| **Level 2 — Public (Panic Mode)** | mDNS / BLE beacon | Low | Emergency broadcast only. Reveals device presence. See §6.3. |

### 6.1 HMAC TimeSlot Definition

`TimeSlot = floor(UTC_epoch_seconds / 3600)` — one slot per UTC hour.

Each device pre-calculates expected values for `TimeSlot - 1`, `TimeSlot`, and `TimeSlot + 1` for each known contact — using that contact's pairwise discovery secret `DS_ab` (§6.4), not the raw identity key. This gives a ±1 hour clock-skew tolerance window without meaningful privacy degradation.

> **Extended-offline clock drift:** the ±1 hour window assumes roughly synchronised clocks. During a multi-week internet/GNSS blackout with no NTP, device clocks can drift beyond one hour, causing live discovery to miss. Clients that detect prolonged offline operation widen the live-discovery match window adaptively (trading a small amount of matching cost for resilience) and resynchronise opportunistically from any peer's HLC on contact. Store-and-forward envelope recognition is unaffected because it derives its slot from the carried HLC timestamp (§5.2), not the local clock.

### 6.2 Stealth BLE Handshake

1. The app broadcasts, per active contact, `HMAC(DS_ab, TimeSlot)` truncated to 4 bytes in the BLE advertisement "Manufacturer Specific Data" field. Each value is indistinguishable from random noise to any observer without that pairwise discovery secret. See §6.4 for how the advertiser bounds airtime when many contacts are active.
2. A contact's device computes expected values for its known contacts across the ±1 tolerance window and initiates a GATT connection only on a match.
3. Sender identity is never present in the advertisement. It is revealed only inside the established E2EE tunnel, after the `EncryptedEnvelope` Inner Header is decrypted.

### 6.3 Panic Mode (Level 2)

Panic Mode enables emergency broadcast when stealth is no longer the priority. It is a deliberately degraded privacy mode for crisis scenarios.

- **Trigger:** 3-second hold on a dedicated panic button, followed by a confirmation tap. Two-gesture activation prevents accidental triggering.
- **Broadcast content:** An ephemeral one-time public key and a public room ID. No long-term identity key is ever broadcast.
- **Capability:** Broadcast-only. Private messages cannot be sent or received while Panic Mode is active.
- **UI:** A persistent red banner with localised copy from `AppLocalizations`. The banner cannot be dismissed without deactivating Panic Mode. All other UI is accessible but the banner remains above all content.
- **Auto-deactivation:** a configurable window (default **5 minutes**), or immediately on user dismissal. The prior 60-second default is likely shorter than a realistic BLE scan/discovery cycle for a nearby responder, defeating the emergency-broadcast purpose; the window is a named constant in `core/constants/`, not a magic number.
- **First-launch warning:** Users must see and acknowledge the privacy implication — that Panic Mode reveals device presence to all nearby observers — at first launch, not only at activation time. Surfacing this warning only at activation is insufficient because a user in a crisis situation may not read it.

### 6.4 Contact Blocking & Discovery Revocation

Stealth discovery MUST support per-contact revocation. A beacon keyed on the single identity key `IK` is computable by every past contact forever, so blocking one contact would otherwise require re-pairing all of them (§5.5). RQSM therefore uses **pairwise-keyed discovery**.

- **Per-contact discovery secret:** at pairing (QR) or first session establishment, both sides derive a dedicated discovery secret `DS_ab = HKDF(shared_secret, "rqsm-discovery")`, distinct from message keys and unique per contact pair.
- **Beacon:** the advertiser emits, per known contact, `HMAC(DS_ab, TimeSlot)` truncated to 4 bytes. A device already precomputes expected values per contact (§6.1), so recipient-side cost is unchanged; the advertiser now emits one short beacon per active contact instead of one shared beacon.
- **Airtime trade-off:** per-contact beacons increase BLE advertising airtime roughly linearly in the number of *active* contacts. Clients cap the count of simultaneously advertised contacts (most-recent / favourites first) and rotate through the remainder across advertising intervals. This bounds airtime at the cost of slightly slower discovery for rarely-contacted peers.
- **Blocking:** blocking contact *b* deletes `DS_ab` and stops emitting and matching *b*'s beacon — effective immediately, with no re-pairing of other contacts. A blocked sender's inbound envelopes are dropped before decryption where the outer header allows, and immediately after decryption otherwise.
- **Reporting:** in server-backed modes, a report bundles opaque abuse evidence (message references, never plaintext) to the server operator per that server's policy. In serverless modes, reporting is local-only (block plus optional local evidence export). See the privacy blueprint's Blocking & Reporting section (§3.7 there).

> **Residual limit:** a contact who recorded your presence *before* being blocked keeps those past observations (adversary "ex-contact", §1.1). Pairwise keying prevents *future* tracking by a blocked contact; it cannot retract past airtime. Identity-key rotation (§5.5) remains the only defence against a contact who has already deanonymised you.

---

## 7. Transport Strategy — Scenario Fallback Chain

`TransportSwitcher` (an infrastructure service in `data/transports/`; its state is surfaced to the UI by `TransportCubit`, §14) monitors `ConnectivityPlus` and a custom `SignalQuality` stream. Drivers are evaluated in priority order; the first driver where `isAvailable == true` is activated. Driver switches emit a `TransportDriverSwitched` domain event via `EventBus`.

### 7.1 Platform Support Matrix

| Driver | Android | iOS | Linux |
|---|---|---|---|
| `XmppTransportDriver` | ✅ | ✅ | ✅ |
| `WifiDirectTransportDriver` | ✅ | ⚠️ Uses Multipeer Connectivity — not true WiFi Direct; background mode restricted by OS | ✅ |
| `BleMeshTransportDriver` | ✅ | ⚠️ Background scanning requires `bluetooth-central` + `bluetooth-peripheral` entitlements; OS may suspend | ✅ |
| `AcousticTransportDriver` | ✅ | ✅ Requires microphone permission | ✅ |
| `ExternalRadioTransportDriver` | ✅ `usb_serial` | ❌ No USB-OTG host mode | ✅ `flutter_libserialport` |

### 7.2 Driver Specifications

> **Sealed-sender split across scenarios:** Scenario 1 (server-backed XMPP) uses **libsignal's own
> sealed sender**. Scenarios 2–5 are serverless P2P/mesh — no certificate authority exists — so they
> use the **custom** RQSM `EncryptedEnvelope` + Blind Trust Token path (§5.2, §5.3.1). All scenarios
> use libsignal for the session, ratchet, and group layers; only the sealed-sender/envelope wrapper
> differs.

---

**Scenario 1 — Full Internet → `XmppTransportDriver`**

- **Libraries:** `moxxmpp`, `libsignal-client`
- **Mechanism:** XMPP over TLS. Session, ratchet, group, and **sealed sender** are handled by **libsignal** (§5.1) — the app does not reimplement them. Only the RQSM envelope/MAC and relay-token addressing are custom (§5.2, §18.4).
- **Protocol:** OMEMO 2 (XEP-0384 adapted). In this server-backed mode, RQSM uses **libsignal's own sealed sender** (server-issued sender certificates) rather than the P2P Blind Trust Token (§5.3). The sender's true identity is sealed inside the payload and is invisible to the server. The `from` attribute in the XMPP XML stream is replaced by an ephemeral relay token — this requires a **server-side module** on Prosody/ejabberd (see server-component note below); it is not achievable with a stock server.
  - **No server archive [v7]:** Message Archive Management (MAM) is **not used in any mode**. The server holds an encrypted message only until it is delivered to the recipient's device (offline storage), then deletes it. Chats are never archived server-side (registration blueprint §5.5). Readable history lives only in the on-device history store (§5.8).
- **Server component:** sealed sender over XMPP requires a custom module to strip/replace `from` and to accept sealed blobs addressed by ephemeral recipient ID. This qualifies the privacy blueprint's "server swapped without app changes" claim: the *app* is server-agnostic, but sealed-sender behaviour depends on a deployed server module for each of Prosody and ejabberd. That module is a named deliverable, not stock configuration.
- **Server routing:** Resolves the correct XMPP server per the hierarchical settings cascade (§8). Default is the main server; overridden at folder or chat level by external server configuration.

---

**Scenario 2 — Internet Blackout → `WifiDirectTransportDriver`**

- **Libraries:** `nearby_connections`
- **Mechanism:** P2P Star/Mesh topology. One device acts as Advertiser; others as Discoverers.
- **Stealth discovery:** Service UUID is a 128-bit value derived per contact as `HMAC(DS_ab, TimeSlot)` (§6.4). A handshake is initiated only when the UUID matches a pre-computed value from the recipient's local contact store. MAC address randomised where the OS permits.
- **Sealed Sender:** Packet header carries only an ephemeral `DestinationID`. Sender identity not present in any advertised field.

---

**Scenario 3 — WiFi Jamming → `BleMeshTransportDriver`**

- **Libraries:** `flutter_reactive_ble` (sole BLE library)
- **Mechanism:** GATT-based Flooding Mesh. Every received packet is re-broadcast to all known neighbours except the originating peer.
- **Flood control:** Each packet carries an 8-byte `PacketID` and a 1-byte `TTL` (initial value: 7). Each relay decrements `TTL` and drops the packet at `TTL == 0`. An LRU cache of recent `PacketID`s prevents re-broadcasting packets already seen.
  - **Cache sizing:** the cache must be sized against **fragment count**, not message count. A session-establishment handshake carrying the ML-KEM-1024 encapsulation key + ciphertext (§5.2) runs to several KB and fragments into ~20 × 180-byte chunks, each a distinct `PacketID`. A fixed 256-entry cache overflows after a handful of concurrent establishments and would then re-broadcast already-seen fragments — the storm it is meant to prevent. Size the cache as `expected_concurrent_messages × max_fragments_per_message` with headroom, and rely on the §5.2 session-token scheme to keep post-establishment messages small (single-digit fragments — per-message sender certificates stay Curve25519-sized; ML-DSA material travels only with connections and prekey bundles, §5.2). Document the chosen bound.
- **Chunking:** Messages fragmented to 180-byte chunks to fit within negotiated BLE MTU. Fragment reassembly is keyed on a message ID plus fragment index.
- **Stealth discovery:** BLE advertisement "Manufacturer Specific Data" carries per-contact `HMAC(DS_ab, TimeSlot)` truncated to 4 bytes (§6.4).
- **Sealed Sender:** Sender identity is absent from all BLE advertisements and is revealed only inside the established E2EE tunnel.

---

**Scenario 4 — Total Radio Jamming → `AcousticTransportDriver`**

- **Libraries:** `flutter_pcm_sound`, `fftea`
- **Mechanism:** Frequency-Shift Keying (FSK) at 18 kHz–20 kHz. Approximately 100 bps throughput. Suitable for short text messages and authentication tokens only. Requires microphone permission.
- **Session prerequisite:** at ~100 bps, the libsignal PQXDH handshake — dominated by the ML-KEM-1024 encapsulation key and ciphertext (~1.5 KB each, §5.2) — would take **minutes** and is impractical. The acoustic driver therefore **cannot bootstrap a new session** — it carries only messages within an **already-established** session using the short session token (§5.2). Session establishment must have completed over another transport first.
- **Sealed Sender (Lite):** Extreme bandwidth constraints prohibit a full sealed sender header. The outer header carries only a 32-bit (4-byte) `ShortRecipientHash` followed by the encrypted payload. No sender information is present in the header. The recipient identifies the sender only after successful decryption of the Inner Header.

---

**Scenario 5 — Long Range (5 km+) → `ExternalRadioTransportDriver`**

- **Libraries:**
  - Android: `usb_serial` (USB-OTG for RTL-SDR) + `flutter_reactive_ble` (BLE link to LoRa node)
  - Linux: `flutter_libserialport` (serial for RTL-SDR) + `flutter_reactive_ble`
  - iOS: Not supported — no USB-OTG host mode
- **Mechanism:** BLE link to an ESP32 LoRa node (Meshtastic Anonymous mode), or RTL-SDR dongle via USB-OTG serial. Flutter owns all UI and encryption. The hardware node handles radio hopping.
- **Sealed Sender:** Meshtastic Anonymous mode carries zero plaintext metadata in the radio broadcast. Flutter's `EncryptedEnvelope` is transmitted as opaque bytes.
- **Platform guard:** All USB-OTG code paths must be gated with `Platform.isAndroid || Platform.isLinux`. No iOS code paths for this driver.

---

### 7.3 Store-and-Forward — Cross-Cutting Persistence Layer

Store-and-Forward is not a transport driver. It is a persistence layer that operates alongside all drivers and enables the Sneakernet sync model.

- **Engine:** `sql_crdt` — justified non-standard package (see §1)
- **Mechanism:** Every outbound message is written to the CRDT table with a Hybrid Logical Clock (HLC) timestamp before any transmission attempt. On any peer discovery event, `SyncEngine` performs an **HLC delta sync** — comparing timestamps to identify and exchange only missing entries.
- **Sneakernet effect:** If User A and User C never meet directly, a message from A reaches C via User B relaying the CRDT delta on next peer contact.
- **Sealed Sender interaction:** the `EncryptedEnvelope` outer header is unencrypted (§5.2), so `SyncEngine` does not decrypt it — it **matches the ephemeral recipient ID** against its own expected value. Because that ID is keyed on `SlotOf(HLC_created)` derived from the envelope's carried HLC timestamp, a bundle relayed days later still matches; the SyncEngine recomputes the recipient ID for the envelope's own slot, not the current hour. Only on a match does it attempt payload decryption.
- **Ratchet gate:** `SyncEngine` confirms `RatchetState.ready` before decrypting any incoming bundle or encrypting any queued outbound message.

#### Metadata Encryption Risk

The CRDT table stores encrypted envelope payloads (ciphertext — acceptable) alongside HLC timestamps, peer node references, and sync vector entries. This communication metadata is **not encrypted at rest** unless SQLCipher wrapping is achieved.

**Action required:** Investigate whether `sql_crdt` is compatible with `sqflite_sqlcipher`. If the `sql_crdt` API allows injection of a custom database factory, SQLCipher can encrypt the entire SQLite file including metadata. If not compatible, the following limitation must be documented prominently in the app's security disclosure: *"On a physically extracted or rooted device, communication metadata — timing, frequency, and approximate volume of messages — may be recoverable from the CRDT store, even if message content is not."*

---

## 8. Hierarchical Server Settings

XMPP server assignment follows the same Global → Folder → Chat cascade as all other application settings. Child settings override parent settings only for explicitly set keys; unset keys inherit.

| Level | Scope |
|---|---|
| **Global** | Main XMPP server. Default for all chats when no lower-level override is set. |
| **Folder** | External XMPP server assigned to all chats in this folder. Overrides the global default. |
| **Chat** | External XMPP server assigned to this specific chat. Overrides the folder setting. |

The `XmppTransportDriver` resolves the correct server for each chat by walking the hierarchy: chat server → folder server → global server.

When a chat is routed to an external server:
- The main server sees only that an opaque sealed blob was delivered and approximate delivery metadata.
- The main server does not observe: sender identity, content, the external server address, or that this was a server-routing event.
- The private channel establishment handshake (§5.3.2) ensures the routing instruction itself is transmitted with full sealed sender protection.

---

## 9. Registration & Onboarding [v7]

Identity and registration are governed by `registration-migration-blueprint.md`; this section only
records the RQSM-relevant consequences. The former verification-method table (invite-only, admin
approval, email + CAPTCHA) is **withdrawn**: account registration is open, needs no invite, and collects
no username, password, email, or phone number (registration blueprint R1.1, R2.3).

- **Registration = publishing public keys:** the client derives the hybrid master identity from a
  recovery seed (§5.1), and registering on a server means publishing the identity public keys and the
  prekey bundle (§5.6). Sign-in is a dual-signed challenge–response (R2.4, R2.4a).
- **Main server first:** every user's first server is the main server, whose address is built into the
  app. Additional servers are added later by domain with a fingerprint check (registration blueprint
  §4.1).
- **Invites gate groups, not accounts:** invites are recipient-bound credentials for entering a group,
  delivered over an existing connection (registration blueprint R1.2a). They have nothing to do with
  account creation.
- **Abuse surface:** with no directory, a newly registered account can only reach people who gave it a
  QR or link, so open registration does not create a spam channel by itself. Servers MAY rate-limit
  registrations per network origin without collecting identifying data.

> **Offline onboarding constraint:** publishing keys requires reaching a server, so a brand-new account
> cannot be created during a total internet blackout. Resilience applies to **already-established**
> identities and their sessions, which continue over the mesh transports. Two users who both want to
> onboard during a blackout must use the QR-only path (§16), which needs no server. State this
> limitation in the security disclosure.

---

## 10. Failure Hierarchy

All RQSM-specific failures extend `AppFailure` (defined in `lib/core/error/app_failure.dart` per the constitution).

```dart
/// A failure originating from a cryptographic operation.
///
/// Carries only an opaque [CryptoErrorCode]. No key material,
/// session identifiers, plaintext fragments, or peer references
/// may appear in any field of this class or its subtypes.
sealed class CryptoFailure extends AppFailure {
  const CryptoFailure(this.code);
  final CryptoErrorCode code;
}

/// A failure in the Double Ratchet state machine.
///
/// Carries only an opaque [RatchetErrorCode]. Dispatches
/// [RatchetStateBroken] via [EventBus] — see domain events §11.
sealed class RatchetFailure extends AppFailure {
  const RatchetFailure(this.code);
  final RatchetErrorCode code;
}

/// A failure in a [TransportDriver].
///
/// [driverName] is the safe display name from [TransportDriver.displayName].
/// No IP addresses, MAC addresses, HMAC values, or peer identifiers
/// may appear in any field.
sealed class TransportFailure extends AppFailure {
  const TransportFailure({required this.driverName, required this.code});
  final String driverName;
  final TransportErrorCode code;
}
```

**Failure field safety rule:** All `AppFailure` subtypes in RQSM carry only opaque error codes and safe display strings. No raw data, stack trace fragments, key bytes, session IDs, peer identifiers, or plaintext content may appear in any failure field at any log level.

---

## 11. Domain Events

Every significant state change emits an immutable `freezed` domain event dispatched via `EventBus`. Event classes live in `lib/features/<feature>/domain/events/`.

`@consumers` tags define the enforced allowlist for each event. **Adding a new consumer to `RatchetStateBroken` or any other security-critical event requires a dedicated security review, not just code review.**

```dart
/// Fired when [TransportSwitcher] activates a different [TransportDriver].
///
/// @event
/// @dispatcher   TransportSwitcher
/// @consumers    TransportCubit, SyncEngine
/// @payload      previousDriverName (String), activeDriverName (String),
///               switchedAt (DateTime), reason (TransportSwitchReason)
/// @since        0.1.0
@freezed
abstract class TransportDriverSwitched with _$TransportDriverSwitched {
  const factory TransportDriverSwitched({
    required String previousDriverName,
    required String activeDriverName,
    required DateTime switchedAt,
    required TransportSwitchReason reason,
  }) = _TransportDriverSwitched;
}
```

```dart
/// Fired when [SecurityService] detects a missing or corrupted
/// ratchet session that cannot be recovered from the isolated ratchet store.
///
/// The affected session is identified only by an opaque internal reference —
/// no peer identity, key material, or session content is included.
/// Adding a consumer requires a security review.
///
/// @event
/// @dispatcher   SecurityService
/// @consumers    MessagingCubit
/// @payload      sessionRef (String — opaque internal reference),
///               brokenAt (DateTime)
/// @since        0.1.0
@freezed
abstract class RatchetStateBroken with _$RatchetStateBroken {
  const factory RatchetStateBroken({
    required String sessionRef,
    required DateTime brokenAt,
  }) = _RatchetStateBroken;
}
```

```dart
/// Fired when [SyncEngine] completes an HLC delta sync with a peer.
///
/// No peer identity is included — only aggregate sync statistics.
///
/// @event
/// @dispatcher   SyncEngine
/// @consumers    MessagingCubit
/// @payload      deltaCount (int), syncedAt (DateTime)
/// @since        0.1.0
@freezed
abstract class PeerSyncCompleted with _$PeerSyncCompleted {
  const factory PeerSyncCompleted({
    required int deltaCount,
    required DateTime syncedAt,
  }) = _PeerSyncCompleted;
}
```

---

## 12. Dependency Injection

`get_it` + `injectable` is the single DI container. It owns infrastructure and also constructs Cubits/Blocs (annotated `@injectable`, a new instance per resolution). `BlocProvider` performs no DI — it only scopes a Cubit's lifetime to a widget subtree (§14).

```dart
// lib/core/di/security_module.dart
@module
abstract class SecurityModule {
  /// Provides the application-wide [SecurityService] singleton.
  ///
  /// [SecurityService] must be initialised before any feature module.
  /// A `@module` provider MUST return a constructed instance — injectable
  /// resolves the constructor parameters from the container.
  @singleton
  SecurityService securityService(
    CryptoFacade crypto,
    RatchetSessionRepository ratchetRepo,
  ) =>
      SecurityService(crypto, ratchetRepo);
}
```

```dart
// lib/features/<feature>/data/di/messaging_module.dart
@module
abstract class MessagingModule {
  /// Provides [TransportSwitcher] with drivers in priority order.
  @singleton
  TransportSwitcher get transportSwitcher => TransportSwitcher([
        XmppTransportDriver(),
        WifiDirectTransportDriver(),
        BleMeshTransportDriver(),
        AcousticTransportDriver(),
        ExternalRadioTransportDriver(),
      ]);

  /// Provides the [SyncEngine] singleton.
  @singleton
  SyncEngine syncEngine(CrdtStore store) => SyncEngine(store);

  /// Provides the [MessagingRepository] implementation.
  @singleton
  MessagingRepository messagingRepository(
    TransportSwitcher switcher,
    SyncEngine sync,
  ) =>
      MessagingRepositoryImpl(switcher, sync);
}
```

> Alternatively, annotate the concrete classes directly with `@singleton` / `@injectable` and omit the module getters entirely — injectable then generates the wiring from the constructors. Use a `@module` only for types you must construct by hand (third-party types, or where construction order matters). Either way, a provider must yield an instance; a bodiless abstract getter does not compile.

`configureDependencies()` in `core/di/injection.dart` aggregates all modules and must be awaited before `runApp()`. The `SecurityModule` must be registered first.

---

## 13. Core Transport Interface & Result Type

### Result Type

```dart
// lib/core/error/result.dart
import 'package:fpdart/fpdart.dart';

/// Alias for [Either] used as the standard return type for
/// all operations that may fail across layer boundaries.
typedef Result<T> = Either<AppFailure, T>;

/// Convenience constructor for a successful [Result].
Result<T> ok<T>(T value) => Right(value);

/// Convenience constructor for a failed [Result].
Result<T> err<T>(AppFailure failure) => Left(failure);
```

All repository methods, use cases, and transport send operations return `Result<T>`. Exceptions must not cross layer boundaries — they are caught at the repository boundary and mapped to an `AppFailure` subtype.

### Transport Driver Interface

```dart
// lib/features/<feature>/data/transports/transport_driver.dart
import 'package:your_app/core/error/result.dart';

/// Contract for an interchangeable transport protocol implementation.
///
/// All [TransportDriver] implementations are transport-agnostic wrappers
/// around a specific radio or network protocol. They receive and emit
/// [EncryptedEnvelope]s only — no plaintext ever crosses this boundary.
abstract class TransportDriver {
  /// Emits inbound [Packet]s as they arrive from this transport.
  Stream<Packet> get onPacketReceived;

  /// Sends an [EncryptedEnvelope] via this transport.
  ///
  /// Returns [ok] on successful hand-off to the transport layer.
  /// Returns [err] with a [TransportFailure] on any transmission error.
  Future<Result<void>> send(EncryptedEnvelope envelope);

  /// Whether this driver can currently be used.
  bool get isAvailable;

  /// Safe display name for UI and logging (e.g. 'XMPP', 'BLE Mesh').
  ///
  /// Must not contain any network address, MAC address, or peer identifier.
  String get displayName;
}
```

---

## 14. State Architecture (`flutter_bloc`)

State management follows the constitution's STATE section: **Cubit by default**; a Bloc only where event concurrency control or an auditable event log is needed. Cubits/Blocs live in `presentation/bloc/`, are thin (they call use cases and map `Result<T>` to state — no business logic, no direct repository or `TransportSwitcher` calls), and are constructed by `get_it` and scoped with `BlocProvider(create: ...)`.

RQSM-specific application of those rules:

| Concern | Rule |
|---|---|
| Which type | `TransportCubit`, `MessagingCubit`: Cubit. Contact verification / key-change handling and the Panic Mode flow: **Bloc** (security-critical; explicit event log). Typing indicators and search: Bloc with `bloc_concurrency` transformers |
| Sensitive state **[C20]** | `MessagingCubit` and any Cubit holding decrypted content or contact identities MUST emit a cleared state and close on app lock / logout. No key material, `EncryptedEnvelope` fields, or `sessionRef` in any presentation state |
| Observation **[C19]** | `AppBlocObserver` logs only Cubit/state/event `runtimeType`s — never `toString()` — and is bound by the §18.1 blocklist |
| Rebuild scope | Message lists and typing indicators use `BlocSelector` / `buildWhen` |

### Transport Cubit

```dart
// lib/features/messaging/presentation/bloc/transport_cubit.dart

/// Exposes the active [TransportDriver]'s display name to the UI.
///
/// Reflects [TransportDriverSwitched] events dispatched by [TransportSwitcher];
/// it never selects or switches drivers itself.
@injectable
class TransportCubit extends Cubit<TransportState> {
  TransportCubit(this._getActiveTransport, EventBus bus)
      : super(const TransportState.unknown()) {
    _sub = bus.on<TransportDriverSwitched>().listen(
          (event) => emit(TransportState.active(event.activeDriverName)),
        );
  }

  final GetActiveTransportUseCase _getActiveTransport;
  late final StreamSubscription<TransportDriverSwitched> _sub;

  /// Reads the currently active driver; called once when provided.
  void load() => emit(
        _getActiveTransport().match(
          (_) => const TransportState.unknown(),
          TransportState.active,
        ),
      );

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}

// transport_state.dart — sealed union: TransportUnknown | TransportActive
@freezed
sealed class TransportState with _$TransportState {
  /// No driver is active, or the active driver could not be read.
  const factory TransportState.unknown() = TransportUnknown;

  /// [driverName] is the safe [TransportDriver.displayName].
  const factory TransportState.active(String driverName) = TransportActive;
}
```

### UI Layer — Transport-Agnostic Chat Screen

```dart
// lib/features/messaging/presentation/pages/chat_page.dart

/// Provides [TransportCubit] to [ChatView]; contains no rendering logic.
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => getIt<TransportCubit>()..load(),
        child: const ChatView(),
      );
}

/// Renders the chat screen; widget tests pump this with a mock Cubit.
class ChatView extends StatelessWidget {
  const ChatView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<TransportCubit, TransportState>(
          builder: (context, state) => switch (state) {
            TransportUnknown() => Text(l10n.transportUnknownTitle),
            TransportActive(:final driverName) =>
              Text(l10n.resilientChatTitle(driverName)),
          },
        ),
      ),
      body: const MessageListView(),
    );
  }
}
```

All user-facing strings — transport status display, Panic Mode banner, ratchet broken prompt, re-entry briefing card — must use `AppLocalizations`. No raw string literals in widget code.

---

## 15. Directory Structure

```
lib/
├── core/
│   ├── crypto/              ← libsignal-client FFI bindings (frb): PQXDH, Double Ratchet,
│   │                           Sender Keys, sealed sender, Curve25519. + HMAC/HKDF glue for the
│   │                           custom P2P layer. No protocol reimplemented. No freezed on keys.
│   ├── security/            ← EncryptedEnvelope (custom P2P), SessionOrchestrator, GroupSession,
│   │                           SealedSender (libsignal in XMPP / BlindTrustToken in P2P),
│   │                           SecurityService, PrekeyService (§5.6), GroupSessionService (§5.7),
│   │                           DiscoveryService (§6.4), HistoryStore (§5.8), libsignal store-trait
│   │                           impls, RatchetSessionRepository interface,
│   │                           isolated ratchet store management (opened in crypto Isolate).
│   ├── di/                  ← get_it modules: injection.dart, event_bus_module.dart,
│   │                           security_module.dart
│   ├── error/               ← AppFailure base + subtypes (CryptoFailure, RatchetFailure,
│   │                           TransportFailure), Result<T> typedef
│   ├── network/             ← Dio factory, interceptors (XMPP REST management API only)
│   ├── router/              ← app_router.dart — GoRouter definition
│   ├── theme/               ← ThemeData, ColorScheme, text styles
│   ├── constants/           ← AppSpacing, AppDurations, RQSM constants
│   ├── extensions/          ← Shared extension methods
│   ├── utils/               ← Stateless utility functions
│   └── l10n/                ← AppLocalizations delegate config
│
├── features/
│   └── messaging/
│       ├── domain/                   ← Pure Dart — zero Flutter imports
│       │   ├── entities/             ← Message, Conversation (freezed, identity field)
│       │   ├── value_objects/        ← EncryptedPayload, PeerReference (freezed, value equality)
│       │   ├── aggregates/           ← ConversationAggregate (root: Conversation)
│       │   ├── events/               ← TransportDriverSwitched, RatchetStateBroken,
│       │   │                             PeerSyncCompleted (freezed + 5 dartdoc tags)
│       │   ├── repositories/         ← MessagingRepository interface (domain contract)
│       │   ├── services/             ← Stateless domain services (no state held)
│       │   └── usecases/             ← One file per use case; one responsibility each
│       │                                 (e.g. GetActiveTransportUseCase)
│       │
│       ├── data/
│       │   ├── datasources/
│       │   │   ├── local/            ← sql_crdt CRDT store (messages, HLC sync metadata)
│       │   │   └── remote/           ← XMPP REST management (Retrofit, if required)
│       │   ├── models/               ← DTOs only — no crypto-material classes here
│       │   ├── repositories/         ← MessagingRepository implementation
│       │   ├── transports/           ← TransportDriver implementations (Scenarios 1–5)
│       │   │                             + TransportSwitcher
│       │   ├── sync/                 ← SyncEngine, HLC delta logic
│       │   └── di/                   ← MessagingModule (@module injectable)
│       │
│       └── presentation/
│           ├── pages/                ← ChatPage/ChatView, ConversationListPage/View
│           ├── widgets/              ← MessageListView, PanicModeBanner, etc.
│           └── bloc/                 ← Cubits/Blocs + state/event files
│                                         (transport_cubit.dart, messaging_cubit.dart)
│
├── l10n/                    ← *.arb translation files (app_en.arb, etc.)
└── main.dart

docs/
└── events/                  ← Auto-generated by generate_event_registry.dart — do not edit
    └── <feature>.md

test/
├── features/
│   └── <feature>/
│       ├── unit/
│       ├── widget/
│       ├── integration/
│       ├── specs/           ← Gherkin .feature files (authored during planning)
│       └── steps/           ← Feature-local step definitions
├── shared/
│   ├── common_steps/        ← Steps used by 2+ features
│   ├── support/             ← FakeTransportDriver, MockCubit/MockBloc helpers
│   └── fixtures/            ← Test data — synthetic key material only (see §19.6)
└── runners/                 ← Thin BDD test runners
```

---

## 16. Connections & Verification [v7]

Contacts are established only through a **connection** (§5.6, registration blueprint §1.1). There is no
server-side lookup.

- **In-person QR:** each device shows a QR code carrying its identity public keys. The scan is mutual,
  and the resulting contact is `verified`. An ML-DSA-87 public key (~2.6 KB) plus a Curve25519 key is
  near the limit of the largest QR version. The QR MAY therefore carry the Curve25519 key and a hash of
  the ML-DSA key; the full ML-DSA key is then fetched with the prekey bundle and MUST match the hash.
- **Shareable link:** single-use, expiring (default 24 h), revocable, and confirmed by a tap from the
  recipient (R1.5, R1.5a). The tap is consent, not identity proof. The initiator MAY require ID
  confirmation (code word or video call, R1.6–R1.7a). Without it, the contact is `unverified`.
- **Safety code:** a human-comparable code derived from both parties' identity public keys (both the
  classical and ML-DSA halves). Comparing it out of band, or scanning it in person, upgrades an
  `unverified` contact to `verified` at any time.
- **Identity change:** a hard warning for `verified` contacts and a visible notice for `unverified`
  ones (§5.6).

Registering on a server (§9) is required before a user can publish a prekey bundle or create a
connection QR or link.

For revocation, per-contact blocking, and re-pairing procedures after device compromise, see §5.5 and §6.4.

---

## 17. Flavours & Environment

Three flavours: `dev`, `staging`, `prod`. Each loads a matching `.env` file via `flutter_dotenv`.

| Flavour | Feature availability | Crypto stack |
|---|---|---|
| `dev` | Panic Mode disabled; long-range radio disabled | Identical to prod |
| `staging` | Panic Mode **enabled** (so the emergency path is exercised before release); long-range radio disabled | Identical to prod |
| `prod` | All features active | Full libsignal PQXDH + Double Ratchet + Sender Keys |

> Panic Mode is a safety-critical, hard-to-reverse UI path; it must be verifiable in a non-prod build. It is enabled in `staging` (which is crypto-identical to prod) and disabled only in `dev`, where crash reporting and analytics are also sandboxed.

> **Crypto parity rule — [SECURITY OVERRIDE]:** Cryptographic configuration, key derivation paths, and encryption settings are **identical across all three flavours**. Only feature availability differs. It is absolutely prohibited to use hardcoded test keys, disable at-rest store encryption, skip certificate validation, or weaken any part of the security stack in dev or staging builds. Shortcuts introduced in dev have a known history of surviving into production.

`.env.dev`, `.env.staging`, and `.env.prod` are all in `.gitignore`. Only `.env.example` with placeholders is committed.

---

## 18. Security Rules

### 18.1 AppLogger Blocklist

All logging uses the `AppLogger` `get_it` singleton. The following must **never be logged at any level** — including `verbose` — under any circumstances:

- Raw key bytes (`Uint8List` containing key material of any kind)
- Ratchet chain keys, message keys, or root keys
- Session references of any kind — including the opaque `sessionRef`, which may be held, compared, and carried in event payloads but never logged (constitution C14)
- Peer identity key fingerprints or public keys
- Plaintext message content
- Sealed Sender tokens or Blind Trust Token values
- `EncryptedEnvelope` fields (including outer header HMAC values)
- Transport metadata: IP addresses, BLE MAC addresses, HMAC discovery values, CRDT node IDs

If a log call requires any of the above to be meaningful, the log call should be omitted. Prefer opaque error codes and driver display names in all log output.

The blocklist also binds `AppBlocObserver` (constitution C19): it logs only Cubit/Bloc, state, and event `runtimeType`s, never their contents.

### 18.2 OWASP Mobile Top 10

The RQSM implementation must satisfy OWASP Mobile Top 10. Key implications specific to this project:

- **M1 — Improper Credential Usage:** No hardcoded keys or credentials. All secrets via platform keystore.
- **M2 — Inadequate Supply Chain Security:** `libsignal-client` is **vendored at a pinned commit** (it offers no third-party release/versioning guarantees) and digest-verified, as are all crypto packages, before inclusion. A documented process re-pins and re-audits the vendored libsignal on a defined cadence and on any security advisory. See §18.4.
- **M5 — Insecure Communication:** All XMPP connections over TLS. Certificate pinning on the primary XMPP server connection.
- **M9 — Insecure Data Storage:** ratchet store (§5.4) and history store (§5.8) encrypted at rest under hardware-derived keys — subject to the §5.4 encryption-availability caveat (verify against the pinned store version; use SQLCipher or app-layer AEAD if native encryption is absent). CRDT metadata store SQLCipher investigation required (§7.3). At-rest stores excluded from OS backup (§18.5). No key material in `flutter_secure_storage` or `SharedPreferences`.
- **M10 — Insufficient Cryptographic Controls (v7):**
  - **Confidentiality:** post-quantum at session establishment (PQXDH, ML-KEM-1024 + X25519) and on an ongoing basis, including post-compromise recovery, via libsignal's Triple Ratchet (Double Ratchet + SPQR).
  - **Account-level authentication:** hybrid post-quantum. Server sign-in, device authorization, migration triggers, connection identity material, and prekey bundles carry XEd25519 + ML-DSA dual signatures, and verifiers require both (§5.1).
  - **Residual:** libsignal's internal per-message and sealed-sender sender authentication remains Curve25519. A future quantum adversary could forge a live sender certificate, but cannot substitute a contact's pinned identity.
  - Do not overstate the stack as "post-quantum everything". State exactly this split in the security disclosure.

### 18.3 Localisation

All user-facing strings from RQSM features must use `AppLocalizations`. This includes:
- Transport status indicator in `ChatPage` app bar
- Panic Mode activation confirmation dialog
- Panic Mode active banner
- Ratchet session broken prompt and re-pair instruction
- Re-entry briefing card (unread count, time since last message, membership changes)
- Stealth discovery status messages

No raw string literals in widget code.

### 18.4 Cryptographic Core Sourcing & Assurance

**Reuse-vetted-first.** RQSM does **not** reimplement session establishment, the Double Ratchet, Sender Keys, or sealed sender. These are provided by **`libsignal-client`** — Signal's own audited, battle-tested Rust implementation — bound via `flutter_rust_bridge` (§4, constitution C18). Reimplementing any protocol libsignal provides is prohibited.

**The unsupported-dependency reality, and how it is handled.** libsignal is not maintained for third-party reuse: no API-stability guarantees, no semantic versioning for external consumers, and no official Dart binding. This is accepted as the lesser risk than rolling our own ratchet, and mitigated — not wished away:

- **Vendored + pinned:** libsignal is vendored at a specific, digest-verified commit (§18.2 M2), never floated. A documented process re-pins and re-audits on a defined cadence and on any advisory.
- **Own the binding:** the `flutter_rust_bridge` binding layer and the store-trait implementations are RQSM code and are in scope for audit and tests.
- **Fallback of record:** if the pinned libsignal ever becomes unmaintainable, the fallback is another *vetted* implementation — never a fresh hand-rolled protocol.

**What still requires an independent audit** (the burden is narrowed, not removed):

- The **retained custom crypto**: the P2P `EncryptedEnvelope` + MAC (§5.2), the P2P sealed sender + Blind Trust Token (§5.3.1), the discovery-beacon HMAC/HKDF layer (§6.4), and the **hybrid identity layer** (v7): seed-to-key derivation, the XEd25519 + ML-DSA dual-signature wrapper and its verification (including prekey co-signature checks before libsignal), and the hardware wrapping of the master key.
- The **integration surface**: the `flutter_rust_bridge` boundary and the libsignal store-trait implementations (§5.4) — a correct protocol wired up wrongly is still a vulnerability.
- The **pinned libsignal commit** itself (supply chain), and the parameter choices (ML-KEM-1024, Curve25519 identity).

**Assurance requirements (mandatory):**

- **Independent audit** of the above before any production release. No production build ships an un-audited integration or un-audited retained-custom crypto.
- **Known-answer conformance** for any *retained custom* construction (the envelope MAC, discovery HMAC) in CI (§19.6). Delegated primitives (ML-KEM-1024, X25519, HKDF, the ratchet) are covered by libsignal's own vectors; RQSM adds interop tests against libsignal (§19.4), not re-derived KATs.
- **Constant-time discipline** for any secret/MAC/tag comparison in the retained custom code.
- **Native-memory key handling:** session key material lives in libsignal's native (Rust) memory, which can be zeroised — the Dart GC cannot. Do not copy key bytes onto the Dart heap; keep them behind the FFI boundary. Any unavoidable Dart-side handling (e.g. the store encryption key) is minimised and confined to the crypto Isolate (§5.1).

### 18.5 Platform Hardening

- **Exclude at-rest stores from OS backup:** the ratchet store (§5.4), history store (§5.8), and CRDT store (§7.3) MUST be excluded from Android auto-backup (`android:allowBackup="false"` or explicit backup rules) and iOS iCloud/iTunes backup (`isExcludedFromBackup`). Otherwise encrypted stores — and any hardware-key-wrapped material — may egress to cloud backup.
- **Screenshot / task-switcher protection:** set `FLAG_SECURE` (Android) and blur the app-switcher snapshot (iOS) on screens showing message content or key material — at minimum during Panic Mode and any key/safety-number display.
- **Push-notification metadata:** on iOS, self-hosted XMPP cannot deliver background messages without a push relay, which exposes message-**timing** metadata to APNs (adversary "push infrastructure", §1.1) even though content stays E2EE. Document this in the security disclosure; where possible run a self-hosted push proxy and coalesce notifications to blunt timing correlation. Notification content previews are governed by the privacy blueprint's Notification Preview controls and must respect lock-screen, notification-listener, and smartwatch exposure.

---

## 19. Testing Strategy

Testing follows the BDD-first workflow: Gherkin `.feature` files are authored during planning and accepted before implementation begins.

### 19.1 BDD Workflow

Gherkin `.feature` files live in `test/features/messaging/specs/`. Step definitions live in `test/features/messaging/steps/`. Steps shared across two or more features live in `test/shared/common_steps/`.

Implementation must not begin until both the plan and `.feature` files are accepted. This is a constitution requirement.

### 19.2 Fake Driver (Required Before Any Widget Test)

`FakeTransportDriver` must be implemented in `test/shared/support/` before any widget or integration test is written.

```dart
// test/shared/support/fake_transport_driver.dart

/// A controllable [TransportDriver] for use in unit and widget tests.
///
/// Injects inbound [Packet]s via [inject] and records all [send] calls
/// for assertion. [available] can be toggled to simulate driver failover.
class FakeTransportDriver implements TransportDriver {
  FakeTransportDriver({this.available = true});

  final _controller = StreamController<Packet>.broadcast();
  final List<EncryptedEnvelope> sentEnvelopes = [];
  bool available;

  @override
  Stream<Packet> get onPacketReceived => _controller.stream;

  @override
  Future<Result<void>> send(EncryptedEnvelope envelope) async {
    sentEnvelopes.add(envelope);
    return ok(null);
  }

  @override
  bool get isAvailable => available;

  @override
  String get displayName => 'Fake';

  /// Injects a [Packet] into the inbound stream for testing.
  void inject(Packet packet) => _controller.add(packet);
}
```

### 19.3 Layer Assignment

| Scenario scope | Layer |
|---|---|
| Single use case, entity, or value object | Unit |
| Single screen or widget interaction | Widget |
| End-to-end user journey | Integration |

### 19.4 Unit Tests

| Target | What to test |
|---|---|
| libsignal integration (PQXDH / ratchet) | Interop tests against libsignal (encrypt→decrypt round-trips, out-of-order, key-change); NOT re-derived KATs — the primitive is libsignal's (§18.4) |
| libsignal store traits (§5.4) | `SessionStore` / `IdentityKeyStore` / `PreKeyStore` / `SignedPreKeyStore` / `KyberPreKeyStore` / `SenderKeyStore` impls persist and reload correctly; encrypted at rest |
| Connections + prekey establishment (§5.6, §16) | QR connection → `verified`; single-use link consumed once, expired/revoked links refused, `unverified` unless ID-confirmed; bundle rejected if identity differs from the connection or ML-DSA co-signature fails; Async session from a libsignal `PreKeyBundle`; `unverified`→`verified` safety-number upgrade; one-time-prekey exhaustion path; key-change warning on a `verified` contact |
| Hybrid identity (§5.1) | Seed → identical keys on re-derivation (recovery); every master-identity signature dual and rejected if either half is invalid; master key never persisted unwrapped; KATs for the dual-signature wrapper |
| Group sender-keys (§5.7) | `SenderKeyDistributionMessage` distribution; **sender-key rotation on member removal**; signature verification rejects forgery |
| `EncryptedEnvelope` (custom P2P) | Round-trip serialisation; outer header unencrypted; payload encrypted; MAC verified before decrypt; libsignal↔envelope interop |
| Store-and-forward recognition (§5.2) | Recipient ID derived from carried HLC slot matches after multi-day delay; live-discovery ±1 window unaffected |
| `TransportSwitcher` | Driver priority selection; failover on `isAvailable` toggle |
| `SyncEngine` | HLC delta calculation; only missing entries synced |
| `HMAC TimeSlot` | Edge cases at hour boundaries; ±1 tolerance window; extended-drift widening |
| Discovery & blocking (§6.4) | Per-contact `DS_ab` beacon; blocking deletes `DS_ab` and revokes only that contact; other contacts unaffected |
| History store (§5.8) | Plaintext written on receipt; delete removes from store; encrypted at rest under hardware-derived key |
| `SealedSender` | BTT generation and verification; nonce single-use replay rejection; invitation payload validation (all 6 fields) |
| Failure subtypes | Assert no sensitive fields in any `CryptoFailure`, `RatchetFailure`, or `TransportFailure` |
| Cubits/Blocs (§14) | `blocTest` for every method/event incl. failure path; `TransportCubit` reflects `TransportDriverSwitched` and cancels its subscription on `close()`; `MessagingCubit` clears decrypted content on lock/logout (C20) |

Use `mocktail` — no real network, radio, or database calls. Widget tests replace Cubits/Blocs with `MockCubit` / `MockBloc` from `bloc_test`.

### 19.5 Coverage Gate

Domain and data layers: ≥ 80% line coverage measured by `flutter test --coverage`. PRs reducing domain/data coverage below 80% must not be merged.

`core/crypto/` and `core/security/` must meet the constitution's raised bar (C13): ≥ 95% line **and** branch coverage. For RQSM this applies to the binding layer, the libsignal store-trait implementations, and all retained custom crypto; known-answer vectors are required for the retained custom constructions (§18.4).

### 19.6 Crypto Test Fixture Safety

All known-answer test vectors for cryptographic functions must use clearly synthetic key material — all-zero bytes, sequential bytes, or similarly obvious test values. Every such fixture must carry a `// TEST ONLY — never use in production` comment on the same line as the key value declaration.

Real-looking key bytes in fixture files are a social engineering risk. A developer encountering them may incorrectly assume they are safe to use or reuse outside test context.

### 19.7 Integration Tests

Real-driver integration tests are on-device (Android / Linux) only. Each driver requires its respective hardware capability (WiFi, BLE, microphone, USB serial). These tests are excluded from CI and run manually before every release.

### 19.8 CI Gate

All of the following must pass in CI before any PR is merged:

- `dart analyze` → zero issues
- `dart doc . 2>&1 | grep -i warning` → no output
- `flutter test --coverage` → ≥ 80% line coverage on domain + data layers
- `core/crypto/` + `core/security/` → ≥ 95% line and branch coverage (C13, §19.5)
- All three test layers pass (unit, widget, integration stubs)
- No unapproved packages in `pubspec.yaml` diff (any RQSM package addition requires the justification table in §1 to be updated in the same PR)

---

## 20. Implementation Rules — Agentic Coding

| Rule | Detail |
|---|---|
| **Read constitution first** | Read the Flutter Constitution in full before producing any plan or code |
| **BDD first** | Author Gherkin `.feature` files during planning. Do not begin implementation until plan and `.feature` files are accepted |
| **Build order** | `core/crypto/` (libsignal FFI bindings) → `core/security/` (store-trait impls → session/group orchestration over libsignal → custom P2P envelope/sealed-sender §5.2/§5.3 → prekey establishment §5.6 → history store §5.8) → `TransportDriver` interface → individual drivers → `SyncEngine` → DI modules → `presentation/bloc/` (Cubits/Blocs) → `presentation/` pages/widgets |
| **UI components** | Class-based `StatelessWidget` / `StatefulWidget` (`HookWidget` only for widget-local controllers) — no functional widgets. Bind state with `BlocBuilder` / `BlocSelector`; side effects only in `BlocListener` |
| **State management** | `flutter_bloc`, Cubit by default; Bloc only for event concurrency or security-critical auditable flows (§14). Thin Cubits in `presentation/bloc/`, constructed by `get_it` (`@injectable`), provided with `BlocProvider(create: ...)` |
| **Sensitive presentation state** | Cubits holding decrypted content or contact identities clear and close on lock/logout (C20). No key material, envelope fields, or `sessionRef` in any state. `AppBlocObserver` logs `runtimeType` only (C19) |
| **Error handling** | `Result<T>` (`fpdart Either<AppFailure, T>`) for every operation that may fail. No thrown exceptions across layer boundaries |
| **`freezed` carve-out** | Do not apply `freezed` to classes holding raw key material in `core/crypto/` or `core/security/`. Implement `toString()` manually returning `'[SecuritySensitive — contents withheld]'` |
| **No DTO for crypto** | No `data/models/` DTO for any class in `core/crypto/` or `core/security/`. No `toJson()`/`fromJson()` on key-material classes |
| **Reuse-vetted-first** | Do not reimplement session/ratchet/group/sealed-sender crypto — use `libsignal-client` (§18.4, C18). Custom crypto is confined to the P2P envelope/MAC, P2P sealed sender/BTT, and discovery HMAC |
| **Crypto imports** | `libsignal-client` bindings and raw crypto primitives imported only inside `lib/core/crypto/`. Any import elsewhere is a violation |
| **Isolates for crypto** | libsignal holds key material in native memory; the encrypted store is opened/accessed in a dedicated crypto `Isolate` — not on the main thread (§5.1) |
| **EventBus dispatch** | Domain events dispatched from use cases, domain services, or infrastructure services registered in `get_it` (e.g. `TransportSwitcher`, C16) — never from presentation code, including Cubits/Blocs |
| **Security event consumers** | Adding a consumer to `RatchetStateBroken` or any security-critical event requires a security review note in the PR description |
| **Logging** | `AppLogger` singleton only. Never log any item from the blocklist in §18.1 |
| **Localisation** | All user-facing strings via `AppLocalizations` — no raw string literals in widget code |
| **Flavour parity** | Crypto stack identical across dev/staging/prod. No test keys, no disabled encryption, no skipped validation in any flavour |
| **Platform guards** | `ExternalRadioTransportDriver` USB-OTG code paths gated with `Platform.isAndroid || Platform.isLinux` |
| **Contact establishment** | Connection first, via QR (→ `verified`) or a single-use, expiring link (→ `unverified` unless ID-confirmed), then a prekey bundle fetched by identity key (§5.6, §16). No username lookup. Never silently re-trust a `verified` contact whose key changed |
| **Hybrid identity** | Every master-identity signature is dual (XEd25519 + ML-DSA); verifiers require both (§5.1). Master key derived from the recovery seed, stored wrapped under a hardware key, never generated inside the secure element (registration blueprint R2.1–R2.1b) |
| **Group crypto** | libsignal Sender Keys (§5.7). Rotate every remaining member's sender key on any member removal. No group feature ships before the integration is audited |
| **History at rest** | Persist readable history in the dedicated encrypted history store (§5.8), not the ratchet or CRDT store. `delete` removes from it |
| **Blocking** | Per-contact discovery keying (§6.4). Block deletes `DS_ab` only; never require re-pairing other contacts to block one |
| **Crypto assurance** | Reuse-vetted-first: no reimplemented protocol; libsignal vendored + pinned. Independent audit of the integration + retained custom crypto before prod (§18.4) |
| **Platform hardening** | At-rest stores excluded from OS backup; `FLAG_SECURE` on sensitive screens (§18.5) |
| **Class naming** | Canonical names from §3.1 exactly. No abbreviations or aliases in production code |
| **Test stub** | Implement `FakeTransportDriver` before writing any widget test |
| **After `freezed` / `injectable` / event / asset changes** | Run `dart run build_runner build --delete-conflicting-outputs`. Commit regenerated `docs/events/<feature>.md` in the same PR |
