# Future Features Roadmap

*Deferred scope for DaChat — a source for future `/speckit-specify` runs*

**Created**: 2026-07-07 · **Living document**

> This file records everything intentionally excluded from the bounded MVP specified in
> [`specs/001-secure-private-chat/spec.md`](../specs/001-secure-private-chat/spec.md). The MVP is
> internet-first and single-device. Each section below is a candidate for its own future feature
> specification. The two blueprints remain authoritative for mechanisms:
> `Secure_Communication_Blueprint.md` (RQSM) and `Privacy_MentalHealth_Blueprint.md`.

---

## 1. Resilient offline / mesh transport

Operate during internet and radio blackouts via a priority-ordered fallback chain.

- **5-scenario transport fallback** (Secure Blueprint §7): XMPP → WiFi Direct → BLE mesh →
  acoustic (ultrasound FSK) → LoRa/SDR external radio, with automatic driver switching on
  connectivity/signal-quality changes.
- **Stealth discovery** (Secure Blueprint §6): Level 0 verified QR pairing, Level 1 per-contact
  rotating HMAC BLE beacons, per-contact discovery-secret keying and revocation.
- **Panic Mode (Level 2)** (Secure Blueprint §6.3): deliberately degraded emergency broadcast with
  two-gesture activation, persistent banner, auto-deactivation, and a first-launch privacy warning.
- **Store-and-forward / sneakernet sync** (Secure Blueprint §7.3): CRDT store with Hybrid Logical
  Clock timestamps, HLC delta sync on peer contact, envelope recognition from carried timestamps,
  and the associated at-rest metadata-encryption investigation.
- Platform support matrix and per-transport bandwidth constraints (e.g. session establishment
  impractical over the lowest-bandwidth links).

**Why deferred**: very large scope; hardware-dependent; on-device-only testing. MVP assumes
connectivity.

## 2. Google Calendar-grade events

Extend the MVP's bounded events (title, start/end, single reminder, simple recurrence, RSVP) to:

- Complex recurrence (full RRULE: intervals, by-day/by-month, exceptions, end conditions).
- Multiple, independently-scheduled reminders per event.
- Rich location (map pins, geocoding, geofenced arrival/leave reminders).
- Calendar-aware mute integration (suppress notifications during/around events with configurable
  buffers — Privacy Blueprint §4.2.1).
- External calendar access/import/export and cross-platform calendar sync.

**Why deferred**: large surface; some parts depend on multi-device and OS calendar permissions.

## 3. Multi-device support

Escalated by the Privacy Blueprint (§7) from an open item to a **cryptographic-architecture
dependency** — must be resolved at the crypto layer before UX design.

- Per-device vs shared identity keys decision.
- Cross-device session and group-key synchronization.
- Cross-device readable-history synchronization.
- Per-device notification de-duplication (one active device notifies; others defer).

**Why deferred**: unresolved crypto dependency; MVP is single-device but not designed to preclude it.

## 4. Cyberbullying & group-dynamics controls

Parked for a dedicated future blueprint; the Privacy Blueprint (§7) frames the threat axes that must
be understood before scoping:

- Coordinated pile-ons (volume/coordination harm).
- Forwarding abuse (out-of-context re-share where the original sender has no presence).
- Screenshot-and-share redistribution (partial mitigation only).
- Identity impersonation in group contexts (confusable usernames/display names).
- Trusted-signal abuse by group moderators.

**Why deferred**: needs its own blueprint with explicit accountability trade-offs and harm ceilings.

## 5. Super-secure QR-only contacts

A per-contact policy that pins a contact to out-of-band QR establishment and refuses any
server-distributed key material for that identity (Secure Blueprint §5.6) — maximum assurance,
never trusting the key-distribution server.

**Why deferred**: the server-distributed establishment path is the MVP default; this is an
opt-in hardening layer.

## 6. Large-group cryptographic scaling

Migrate group cryptography to a scheme with logarithmic-cost membership changes and stronger
post-compromise security once realistic group sizes grow large (Secure Blueprint §5.7 — MLS as the
named candidate, deferred due to its near-simultaneous-online requirement fitting intermittent
transports poorly).

**Why deferred**: the MVP's sender-key approach is adequate at expected group sizes.

## 7. Hybrid post-quantum identity authentication (ML-DSA)

A supplementary ML-DSA (Dilithium) co-signature on the long-term identity key, layered on top of
`libsignal-client`'s classical Curve25519 identity and signatures (Secure Blueprint §5.1, §18.2 M10).

- **Scope**: the identity key and its prekey signatures only — never the Blind Trust Token,
  private-channel invitations, or per-message data. Only a long-lived key (years, across
  re-pairings) carries meaningful "forge-later" risk from a future quantum adversary; per-message
  and per-handshake signatures are verified in real time and cannot be retroactively forged.
- **Trigger for revisiting**: libsignal's own post-quantum authentication story matures, or a
  concrete quantum-capability timeline makes the added complexity worth it.

**Why deferred**: it reopens the bespoke dual-signature crypto surface the libsignal migration was
meant to close — needs its own audit, downgrade-attack analysis, and canonical serialization design
— and ML-DSA-87 (matching ML-KEM-1024's security level) adds ~2.6 KB public keys / ~4.6 KB
signatures, which would burden the BLE-mesh and acoustic transports if scoped beyond the identity
key. PQ authentication is also lower-urgency than PQ confidentiality: there is no
harvest-now-decrypt-later analogue for a signature verified at handshake time. The MVP ships fully
on libsignal's classical authentication (Secure Blueprint §5.1).

## 8. Open design items

- **Unilateral server reassignment**: define the other participant's client behavior when one party
  moves a chat to a different server (silent follow / prompt / reject) — Privacy Blueprint §7,
  Secure Blueprint §8.
- **Session continuity across folder-driven server changes**: what happens to an active session when
  a chat moves between folders referencing different servers; server-side history migration policy.
- **Verification-method defaults** for the main public server deployment.

---

*Update this file whenever MVP scope changes or a deferred item is promoted to its own spec.*
