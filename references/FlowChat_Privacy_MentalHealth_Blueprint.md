# FlowChat
## Privacy & Mental Health Preservation Blueprint
*Version 2.2 · July 2026*

> **v2.2 changes:** RQSM crypto now sourced from `libsignal-client` (reuse-vetted-first) — PQXDH with **ML-KEM-1024**, libsignal Sender Keys, and **classical Curve25519 authentication** (ML-DSA dropped; PQ confidentiality but not PQ authentication). §2.3/§2.4 updated accordingly.
>
> **v2.1 changes:** recipient-account observation corrected across mode tables; hardware-key claim corrected; invitation field list reconciled with RQSM §5.3.2 (6 fields); added §2.6 push-notification metadata, §3.7 blocking & reporting, §3.8 media & attachments; clarified inactivity measurement, export audit trail locality, and the structural-vs-semantic boundary; escalated multi-device to an architecture dependency.

> **PURPOSE** — This document defines the privacy and mental health principles, architectural decisions, and feature specifications for FlowChat — a self-hosted, privacy-first chat application spanning family and workplace contexts.

> **SCOPE** — Three-layer architecture: Infrastructure (institutional surveillance), Market Baseline (accountability-preserving recipient controls), and Feature Layer (interpersonal privacy and mental health by harm axis).

> **RELATED DOCUMENTS** — `RQSM_Blueprint.md` (cryptographic and transport architecture). Where this document references cryptographic mechanisms, the RQSM blueprint is the authoritative specification.

---

# 1. Foundations

## 1.1 Design Principles

The following principles govern all privacy and mental health decisions in FlowChat:

- The app mediates communication — it does not mediate human behaviour. Conflict is resolved human to human; the app provides tools to set boundaries, not to arbitrate.
- Privacy is a spectrum, not a binary. FlowChat offers a continuum from convenient cloud-hosted defaults to fully opaque private server channels.
- Recipient-facing controls are kept at market standard to preserve accountability. Exotic disappearing-message features can shield abusive users from consequences.
- Settings are hierarchical: global defaults cascade to folder-level overrides, then to chat-level overrides. Child settings win only for explicitly set keys.
- Scheduled behaviour with manual override is preferred over daily manual switching. The default is automatic; the exception is the override.
- No AI or semantic analysis reads message meaning. Triage and organisation are structural, not semantic. Bounded, purely mechanical matching performed **locally on-device** (e.g. exact string match of the user's own name, §4.2.2) is permitted; what is prohibited is any ML/semantic interpretation of content, and any analysis performed off-device. This preserves the privacy guarantees the infrastructure layer provides while keeping the "structural vs semantic" line precise rather than absolute.

## 1.2 Harm Axes (Priority Order)

Six axes of harm were identified and ranked by severity for FlowChat's target context (family and workplace, self-hosted, privacy-first):

1. **Surveillance Anxiety** — fear of institutional access to private conversations (addressed primarily in infrastructure layer)
2. **Attention Fragmentation** — notifications pulling attention at wrong moments, backlogs creating avoidance loops
3. **Emotional Ambush** — difficult messages arriving when the user is not equipped to handle them
4. **Context Bleed** — wrong conversation finding the user in the wrong headspace, eroding life boundaries
5. **Social Obligation Escalation** — app design creating guilt for not responding
6. **Presence Pressure** — exposure of availability signals creating entitlement to immediate response

## 1.3 Three-Layer Architecture

| Layer | Responsibility |
|---|---|
| **Layer 1 — Infrastructure** | Institutional surveillance anxiety. Self-hosted XMPP, E2EE, RQSM post-quantum cryptography, opaque private server channels. |
| **Layer 2 — Market Baseline** | Recipient-facing controls. Telegram-parity privacy settings, accountability-preserving defaults. Nothing exotic. |
| **Layer 3 — Feature Layer** | Interpersonal privacy and mental health. Hierarchical, scheduled, granular controls per harm axis. |

---

# 2. Layer 1 — Infrastructure

## 2.1 Server Architecture

FlowChat operates on a spectrum of privacy modes, controlled by where a chat's data lives and what the main server can observe.

| Mode | Data Lives On | Main Server Observes | Identity |
|---|---|---|---|
| **Default Chat** | Main XMPP server | Message routing metadata; sender and recipient identities | Main server username |
| **Private Server Chat** | External XMPP server | An opaque sealed blob was delivered **to a known recipient account**; approximate timing and payload size. Sender identity and content are blind. | Same username; channel is opaque |
| **Pure E2EE** | No server-side persistence | An opaque sealed blob was delivered **to a known recipient account**; approximate timing and payload size | Same username |

> **"Zero knowledge" qualification:** Private Server Chat and Pure E2EE modes are *sender-anonymous and content-blind* — not event-blind and not recipient-anonymous. Any server that *delivers* a message must know the recipient account to route to it (the XMPP `to` attribute remains even when `from` is a relay token). The main server always observes that a delivery event to a given recipient occurred, including approximate timing and payload size. Users whose threat model requires concealing the *existence* of a communication channel should understand that sealed sender is a content protection mechanism, not a traffic concealment mechanism.

> **Layer 2 signal availability in Pure E2EE mode:** In Pure E2EE mode, server-relayed presence signals — read receipts, typing indicators, online status — are unavailable. There is no relay mechanism for short-lived signals without server-side state. This is an accepted trade-off of the pure mode. Users must be informed of this limitation before selecting Pure E2EE.

## 2.2 Server Driver Model

The XMPP server is treated as an interchangeable driver, not a hard dependency. Prosody and ejabberd are both supported and can be swapped without app changes.

- Individual chatrooms can reference external XMPP servers via address and credentials
- If no external server is specified, the chat defaults to the main public server
- This follows the hierarchical settings model: global server default, overridden per folder, overridden per chat
- The main server is blind to sender identity and content for traffic routed to external servers. It does observe that opaque sealed delivery events to a known recipient occurred.

> **Qualification — server-side module:** the *app* is server-agnostic, but sealed-sender behaviour (stripping/replacing the `from` attribute, accepting blobs addressed by ephemeral recipient ID) requires a **deployed server module** on each of Prosody and ejabberd. That module is a named deliverable, not stock configuration. See `RQSM_Blueprint.md §7.2` (Scenario 1). "Swapped without app changes" is accurate for the client; the server side needs the module.

> **Qualification — server assignment is bilateral:** moving a chat to an external server via the folder/chat cascade is not a purely local setting. It changes where *both* participants' traffic is routed, so it is established via the invitation handshake (§2.3). Subsequent *unilateral* server reassignment by one party (e.g. moving a chat between folders that reference different servers) needs a defined behaviour for the other party — see Open Items (§7).

## 2.3 Private Channel Establishment

When two users wish to move a conversation to a private server, the handshake is established without the main server learning the sender's identity or the invitation's content.

**Handshake summary:**

1. Alice constructs an invitation payload and sends it to Bob via sealed sender.
2. The main server receives an opaque encrypted blob. It observes: a delivery event occurred, approximate timing, approximate payload size. It does not observe: sender identity, content, or that this was a server-routing invitation.
3. Bob's client decrypts and surfaces the invitation. Bob accepts and the private channel is established.
4. Identity is not anonymised between Alice and Bob — the same username spans both servers. Opacity is at the channel level, not the identity level.

**Required security properties of the invitation payload:**

Every private channel invitation requires **all six** fields below. `RQSM_Blueprint.md §5.3.2` is the **authoritative and complete** specification for validation — implement against it, not against this summary.

| Field | Purpose |
|---|---|
| `nonce` | 128-bit random — single-use, rejected on replay |
| `expiry` | UTC timestamp — invitation expires after 24 hours |
| `recipientKeyFingerprint` | Binds the invitation to the intended recipient's identity key — non-transferable |
| `externalServerAddress` | The external server address, encrypted to the recipient with the hybrid KEM |
| `externalServerCredentials` | The external server credentials, encrypted to the recipient with the hybrid KEM |
| `senderSignature` | Classical Curve25519 signature over all fields — prevents forgery |

An invitation missing any required field (per RQSM §5.3.2) must be silently rejected by the recipient's client.

## 2.4 RQSM — Resilient Quantum-Signal Mesh

The full RQSM specification is maintained in `RQSM_Blueprint.md`. Key guarantees relevant to this blueprint:

- Session, ratchet, and group crypto via **`libsignal-client`** (Signal's own audited Rust implementation, reuse-vetted-first — RQSM §18.4), not a custom protocol stack
- Post-quantum *confidentiality* via libsignal **PQXDH (ML-KEM-1024 + X25519 hybrid)** at session establishment. The ongoing Double Ratchet DH step is classical — post-compromise recovery is not quantum-resistant (RQSM §5.1)
- **Authentication is classical Curve25519** (matches Signal). RQSM provides PQ *confidentiality* but **not** PQ authentication/non-repudiation — a deliberate trade-off; a quantum adversary cannot retroactively forge past authentications (RQSM §18.2 M10)
- Sealed sender: sender identity cannot be inferred by the transport layer or the server (recipient identity is still known to a delivering server). libsignal sealed sender in server-backed XMPP mode; a custom Blind Trust Token path in P2P/mesh (RQSM §5.3)
- Encrypted envelope pattern with layered visibility (outer header unencrypted; inner header and payload encrypted for recipient only)
- Driver-plugin transport architecture with automatic fallback logic
- Pure E2EE mode: no server-side message persistence
- Asynchronous contact establishment via server-distributed libsignal prekey bundles; QR upgrades a contact to `verified` via safety-number comparison (RQSM §5.6)
- Group messaging via **libsignal Sender Keys** (RQSM §5.7)
- Per-contact blocking and discovery revocation (RQSM §6.4)
- **Hardware-backed key storage:** the long-term wrapping key never leaves the device's secure element. Derived and per-message keys are ephemeral in app memory while in use and are never persisted — they cannot be kept entirely out of memory in a Dart app (RQSM §5.4, §18.4). On Linux, which usually has no secure element, the guarantee is weaker (OS keyring or passphrase-derived key)

## 2.5 Human Verification & Onboarding

To prevent bot registration while preserving privacy, the following verification approach is used:

- Phone number not required — avoids linkability to real-world identity and SIM-swap risk
- Supported verification methods (configurable per server deployment):
  - **Invite-only** — existing member generates a one-time link; link expires after use or after a configurable TTL
  - **Admin approval** — username/email registration with admin review before activation
  - **Email + CAPTCHA** — lower friction, filters bots
- Server operators choose their verification model. The main public server uses invite-only or admin approval by default.
- After verification, contacts are established by default via server-distributed prekey bundles (`RQSM_Blueprint.md §5.6`); QR pairing is the out-of-band upgrade to a `verified` contact, not the only way to reach someone.

> **Verification record retention — Email + CAPTCHA:** For email + CAPTCHA verification, the email address and confirmation token must be discarded immediately after the account is confirmed. These records must not be stored alongside or linked to the user's identity key, username, or any persistent account record. Retaining them creates a permanent email → identity linkage that undermines the no-phone-number privacy guarantee.

> **Offline onboarding constraint:** verification and prekey publication require reaching a server, so a brand-new account cannot be created during a total internet blackout. Resilience applies to already-established identities and their sessions (which continue over the mesh transports), not to first-time onboarding. Two users onboarding during a blackout must use the QR-only path. See `RQSM_Blueprint.md §9`.

## 2.6 Push Notification Metadata

Every feature in Layers 2 and 3 assumes notifications work. That assumption has a privacy cost that must be stated, because a self-hosted, surveillance-averse app cannot silently rely on the same push path as a mainstream messenger.

- **iOS background delivery:** self-hosted XMPP cannot wake the app for background messages without going through Apple Push Notification service (APNs). Even with content end-to-end encrypted, this exposes message-**timing** metadata to Apple (adversary "push infrastructure", `RQSM_Blueprint.md §1.1`). Android/FCM has the analogous exposure to Google.
- **Mitigations:** where possible, run a self-hosted push proxy and coalesce/delay notifications to blunt timing correlation; on Android, a foreground service or direct XMPP push can avoid FCM at a battery cost. Document the residual exposure in the security disclosure.
- **OS-surface exposure of previews:** notification content previews (§4.1, §4.3.2) surface message text at the OS layer — lock screens, notification-listener apps, paired smartwatches, and car displays. Preview controls must default to privacy-safe (sender name or nothing for untrusted senders) and the exposure surfaces above must be considered part of the threat surface, not just the in-app UI.

---

# 3. Layer 2 — Market Baseline

> **PRINCIPLE** — Recipient-facing controls are kept at Telegram-parity. Exotic controls that give abusive users tools to escape accountability are deliberately excluded. The same features that protect vulnerable users can shield harassers — this asymmetry is resolved in favour of accountability.

## 3.1 Identity & Discoverability

- Username-based identity (no phone number required)
- Control who can find you by username
- Control who can add you to groups: everybody / contacts / nobody
- Control who can send you direct messages

## 3.2 Presence Controls

- Last seen & online visibility: everybody / contacts / nobody / custom
- Read receipts toggle
- Typing indicator toggle

> **Note — Pure E2EE mode:** In Pure E2EE mode, presence controls that depend on server relay (read receipts, typing indicators, online status) are unavailable. See §2.1.

## 3.3 Profile

- Profile photo visibility controls
- Bio visibility controls
- Forwarded message attribution: link to original profile or strip attribution

> **Tension with forwarding abuse (§7):** stripping attribution is a Telegram-parity privacy control, but it is also the mechanism behind the "forwarding abuse" threat framed in §7 — a message re-shared without attribution into a group where the original sender has no presence cannot be responded to or corrected. This blueprint keeps the market-parity control (accountability principle: recipient-facing features stay at baseline) but flags the tension for the future cyberbullying blueprint to resolve, e.g. with cryptographic forward-provenance that survives stripping.

## 3.4 Sessions & Security

- Active session management and remote logout
- Two-step verification
- Passcode lock
- Auto account deletion after configurable inactivity period

> **Inactivity measurement in sealed/Pure E2EE modes:** "inactivity" here means server-observed account activity (login, prekey refresh, delivery events to the account). For Pure-E2EE-heavy users the server sees little, so account-level auto-deletion keys off account touchpoints (prekey bundle refresh, authentication), not message activity — otherwise a heavily-private user could be deleted while actively communicating over the mesh. Local data retention/auto-delete (§3.5) is a separate, device-local control.

## 3.5 Content Controls

- Message edit within configurable timeframe
- Message delete within configurable timeframe
- Per-chat auto-delete timer (message lifetime)

> **Message deletion in E2EE and Pure E2EE modes:** Message deletion removes content from the local UI **and from the local encrypted history store** (`RQSM_Blueprint.md §5.8` — readable history lives there, not in the ratchet or CRDT store) and, where the transport supports it, sends a deletion signal to connected peers. In Pure E2EE and store-and-forward mode, deletion signals are best-effort and cannot be guaranteed to remove content from all peers' local stores. Deletion is not equivalent to erasure in a store-and-forward architecture. Users should be informed of this limitation in the app's privacy disclosure and at the point of enabling auto-delete in Pure E2EE mode.

## 3.6 Data

- Chat history export: controlled, with audit trail
- Contact sync: opt-in, deletable
- Suggest frequent contacts: opt-in only

> **Export audit trail is local-only:** the "audit trail" for chat-history export is a **device-local** record visible only to the account owner — it is never sent to or stored on any server. An audit trail is itself sensitive metadata; in a privacy-first app it must not become a server-side log of who exported what and when. Its purpose is to let the user themselves detect an unexpected export (e.g. after a device compromise), not to enable third-party accountability.

## 3.7 Blocking & Reporting

Blocking is a baseline safety expectation, not an exotic control, and is distinct from the "who can DM/add me" access controls in §3.1 (which govern *strangers*; blocking governs *existing contacts*). It is included at market parity.

- **Block a contact:** stops messages, calls, presence, and discovery from that contact. In the serverless/mesh modes this has a cryptographic dimension — blocking deletes the pairwise discovery secret so the contact can no longer discover the device (`RQSM_Blueprint.md §6.4`). Blocking one contact never requires re-pairing others.
- **Report a contact or message:** in server-backed modes, a report sends opaque abuse evidence (message references, never plaintext) to the server operator per that server's policy. In Pure E2EE/serverless modes there is no operator to receive a report, so reporting is local-only (block plus optional local evidence export). Users must be told which applies in their current mode.
- **Residual limit:** a blocked contact who already recorded your presence keeps those past observations; blocking prevents future discovery, not retroactive de-anonymisation (`RQSM_Blueprint.md §6.4`).
- **Group-context blocking** (moderator abuse, coordinated pile-ons) is deliberately out of scope here and framed in §7 for the future cyberbullying blueprint.

## 3.8 Media & Attachments

Media is a first-class privacy surface and must not inherit the text pipeline's assumptions.

- **Encryption at rest and in transit:** attachments are wrapped in the same `EncryptedEnvelope` pattern as text; the media blob is E2EE and stored in the encrypted history store (`RQSM_Blueprint.md §5.8`), never as a plaintext file in a general cache.
- **No plaintext CDN cache:** the constitution's `cached_network_image` is for *public* URL-fetched images only. It MUST NOT be used for E2EE message media — that would cache decrypted content as plaintext on disk. E2EE media uses a dedicated encrypted media store with explicit decrypt-to-memory rendering.
- **Metadata stripping:** on send, strip EXIF/location and other embedded metadata from photos and files by default (a classic family-chat leak — GPS coordinates in a shared photo). Stripping is on by default with an explicit opt-out per send.
- **Thumbnails and previews:** generated locally from decrypted content; thumbnail caches are subject to the same encrypted-at-rest and OS-backup-exclusion rules (`RQSM_Blueprint.md §18.5`).
- **Deletion:** deleting a message deletes its media from the encrypted media store, subject to the same store-and-forward erasure limits as text (§3.5).

---

# 4. Layer 3 — Feature Layer

The feature layer addresses interpersonal privacy and mental health across the five non-infrastructure harm axes. All features in this layer are hierarchical: global defaults cascade to folder-level overrides, then to chat-level overrides.

## 4.1 Surveillance Anxiety (Feature Layer)

Institutional surveillance is handled in Layer 1. The feature layer addresses residual interpersonal surveillance concerns not covered by the infrastructure.

| Feature | Description | Settings Level |
|---|---|---|
| **Notification Preview Control** | Notification banners show content only from trusted signal senders. Others show sender name only, or nothing. | Global / Folder / Chat |
| **Trusted Sender Tier** | Per chat or folder, designate which senders can surface content in notification previews and triage views. | Folder / Chat |

## 4.2 Attention Fragmentation

> **CORE HARM** — The app pulls attention at wrong moments (interruption harm) or makes returning feel punishing after deliberate absence (backlog harm). Backlog harm is a consequence of healthy boundary-setting behaviour — the app must not punish stepping away.

### 4.2.1 Interruption Controls

| Feature | Description | Settings Level |
|---|---|---|
| **Granular Notification Settings** | Per chat/folder: independently toggle sound, vibration, banner, preview, badge count, unread count, activity indicator, and notification types (all / mentions only / none). | Global / Folder / Chat |
| **Scheduled Mute Times** | Per folder: define time windows and day patterns when all signals from that folder are suppressed. Follows the folder-as-context-boundary principle. | Folder / Chat |
| **Schedule Override** | Temporarily extend a folder's active window beyond its schedule (e.g. 'I am still at work'). Expires automatically or on manual cancel. | Folder |
| **On-Call Mode** | A special folder state where only direct @mentions pierce through. Message flow is suppressed but the user remains reachable for urgent signals. | Folder / Chat |
| **Calendar-Aware Mute** | Suppress notifications during and around calendar events. Configurable buffer time before and after events. | Global / Folder |
| **Per-Device Notification Rules** | Prevent the same message triggering simultaneous alerts on phone and laptop. One active device notifies; others defer. | Global |

### 4.2.2 Backlog Triage — While You Were Away

When returning after a silence or mute period, instead of a raw unread count, the app presents a structured catch-up view. The app never performs semantic analysis of message content — triage is structural only.

> **Decryption and triage:** Extracting structural signals (@mentions, priority flags, assigned todos, direct replies) requires decrypting the envelope payload. This decryption is necessary and permitted — structural signals live inside the encrypted payload, not in the unencrypted outer header. What is prohibited is semantic analysis of the decrypted content. The app may read structure; it may not read meaning.

- **Trusted structural signals surfaced:** @mentions, priority flags, todo items assigned to you, direct replies to your messages, messages marked needs-reply
- **Derived structural signals:** messages from close contacts tier, messages containing your name (string match only, no semantic analysis)
- All other messages collapse into a single unread count the user can browse or mark read at will
- Trusted signal tier controls who can inject signals into this view — abuse prevention for pushy or toxic senders

### 4.2.3 Signal Granularity Reference

| Signal Type | Granular Control |
|---|---|
| Sound / Vibration | On / Off |
| Notification Banner | On / Off / Trusted senders only |
| Notification Preview | Full content / Sender name only / None |
| Badge Count (app icon) | Show / Hide |
| Unread Count (in folder) | Show / Hide |
| Chat Activity Indicator | Show / Hide |
| Notification Types | All messages / @mentions only / Assigned todos only / None |
| On-Call Pierce | Direct @mentions only |

## 4.3 Emotional Ambush

> **CORE HARM** — A difficult message reaches the user at a moment they are not equipped to handle it. Two forms: anticipated (known conflict, active disengagement needed) and unanticipated (blindside, no warning). The silence feature covers the anticipated form; additional features address the unanticipated.

### 4.3.1 Active Retreat — Silence Feature

| Feature | Description | Settings Level |
|---|---|---|
| **Chat Silence / Snooze** | Delay delivery visibility (hides from UI) of all messages from a chat. Single low-friction gesture designed for heightened emotional states. | Chat |
| **Quick-Pick Duration** | Pre-set durations shown on silence gesture: 1 hour, Tonight, 3 days, Until I turn it off. Reduces cognitive load during conflict. | Chat |
| **Re-Entry Briefing Card** | Before unmuting a silenced chat, show a metadata summary: unread count, time since last message, membership changes (who joined or left). A conscious speed bump, not automatic re-entry. | Chat |

> **Silence is a UI-layer control — not a delivery stop:** Messages from a silenced chat continue to be delivered to the device and stored as encrypted envelopes by the RQSM layer. Silence controls visibility and notification; it does not halt delivery. A user who activates silence does not stop receiving messages — they stop being notified of and shown them until they choose to re-enter. This distinction matters particularly in high-conflict or safety-sensitive situations where a user might assume silence means non-delivery.

### 4.3.2 Passive Protection — Preventing the Blindside

| Feature | Description | Settings Level |
|---|---|---|
| **Notification Preview Tier** | Notification banners show message content only from trusted senders. Untrusted senders show name only. Prevents blindside via OS notification layer. | Global / Folder / Chat |
| **Contextual Mute Windows** | Scheduled mute times and calendar-aware mute ensure difficult messages cannot reach the user's attention during protected periods (sleep, focused work, family time). | Folder / Chat |
| **Cyberbullying Controls** | Parked for a dedicated future blueprint — see §7 for threat framing. | TBD |

## 4.4 Context Bleed

> **CORE HARM** — The wrong conversation finds the user in the wrong headspace. Unlike Emotional Ambush (acute trigger), Context Bleed is ambient and cumulative — the slow drip of work messages during family dinner, or family drama during focused work. Folders are the primary architectural response: they are context boundaries, not organisational labels.

### 4.4.1 Folder as Context Boundary

| Feature | Description | Settings Level |
|---|---|---|
| **Folder Context Mode** | Each folder is an active context zone with its own notification behaviour, signal visibility, and schedule. The folder experience honours the boundary, not just the label. | Folder |
| **Folder Quiet Schedule** | Per folder: define time windows and day patterns (e.g. Work folder quiet Mon–Fri after 6pm, weekends). Schedule lives in the folder — consistent with hierarchical settings model. | Folder |
| **Schedule Override** | Temporarily extend a folder's active window: 'I am still at work'. Expires automatically (end of day) or on manual cancel. Preferred over daily manual switching. | Folder |
| **On-Call Mode** | Work folder suppresses message flow after hours but passes through direct @mentions. Allows being reachable without being bombarded. | Folder |

### 4.4.2 Multi-Context Contacts

When a person is both a colleague and a friend, the app does not attempt to resolve the ambiguity automatically. Instead:

- Users create separate chats for separate contexts with the same person (e.g. a work chat and a personal chat)
- Each chat lives in the appropriate folder and inherits that folder's context settings
- No special feature required — the existing chat and folder model handles this naturally

## 4.5 Social Obligation Escalation

> **CORE HARM** — App design makes the user feel guilty for not responding. Primarily addressed by granular signal controls (unread count, badge, notification type) already specified under Attention Fragmentation. No additional features required beyond market baseline.

Key insight: unread count as psychological debt is the primary driver. Hiding unread counts and badge counts per folder/chat directly reduces obligation pressure without requiring new mechanisms.

- Response time patterns and reaction pressure are relationship problems, not app problems. Left to users to manage in their relationships.
- Market baseline read receipt toggle, last seen, and typing indicator controls are sufficient for this axis.

## 4.6 Presence Pressure

> **CORE HARM** — Exposure of availability signals creates entitlement to immediate response. Fully addressed by market baseline privacy settings already established and used by the user on existing platforms.

Market baseline controls (read receipts, last seen/online visibility, typing indicator) are sufficient. These have already proven effective for the target user context. No additional feature layer required for this axis.

---

# 5. Trusted Signal Tier — Cross-Cutting Mechanism

The Trusted Signal Tier is a cross-cutting mechanism that governs which senders can inject signals into the user's attention. It prevents pushy or toxic senders from abusing structural signals (mentions, priority flags, needs-reply flags) to pierce notification controls and triage views.

## 5.1 How It Works

- Per folder: designate trusted senders (e.g. moderators, admins). Only their signals surface in the While You Were Away triage view and pierce notification filters.
- Per direct message chat: explicitly designate whether that contact's signals are trusted. Contacts not designated do not get their messages prioritised.
- Silence feature overrides everything: a silenced chat passes no signals regardless of trust tier.
- The trusted tier is hierarchical: a global default can be overridden per folder, overridden per chat.

## 5.2 Rate Limiting — Trusted Sender Abuse Prevention

Being in the trusted tier grants access to priority signal injection. Without a rate limit, a trusted sender can flood the triage view — whether through careless overuse or deliberate abuse by a sender who knows the user filters aggressively.

- Each trusted sender is subject to a maximum signal injection rate: no more than **N priority flags per sender per hour** (specific N to be tuned during implementation; suggested starting point: 5 per hour).
- Signals beyond the rate limit from a trusted sender are accepted and stored but are treated as ordinary messages — they do not pierce notification filters or surface in the triage priority view.
- Rate limit state is maintained locally. The sender is not notified when their signals are rate-limited.
- The rate limit applies per folder context. A sender in both a Work folder and a Family folder has a separate limit in each context.

## 5.3 Abuse Cases Addressed

- **Case A — Noisy but well-meaning sender:** marks everything priority without malicious intent. Solved by not including them in the trusted tier, or by the rate limit if they are trusted.
- **Case B — Deliberately pushy sender:** knows you filter and abuses priority flags. Solved by the trust tier (explicit opt-in, not default) and the rate limit.
- **Case C — Trusted sender who becomes toxic:** rate limit reduces blast radius. Full silence overrides the trust tier entirely.

---

# 6. Hierarchical Settings Model

All privacy and mental health settings follow the FlowChat hierarchical cascade:

| Level | Scope |
|---|---|
| **Global** | Default values for all settings across the entire app. The baseline when no lower-level override exists. |
| **Folder** | Overrides global defaults for all chats within that folder. A folder's quiet schedule, notification profile, trusted signal tier, and context mode all live here. |
| **Chat** | Overrides folder settings for a specific chat. The most granular level. Child settings win only for explicitly set keys — unset keys continue to inherit. |

This model means a user can set a global default of 'hide unread counts everywhere', override it at the Family folder level to show counts, and then override again at one specific family chat to hide them. Each level only touches what it explicitly sets.

---

# 7. Open Items & Future Work

## Cyberbullying & Group Dynamics — Threat Framing

Cyberbullying controls are parked for a dedicated future blueprint. Before that blueprint is scoped, the following threat axes must be understood — this framing is not a feature specification, it is the foundation the future blueprint requires to be scoped correctly.

**Identified threat axes:**

- **Coordinated pile-ons:** multiple group members directing simultaneous negative signals at a target; the harm is amplified by volume and coordination, not any single message.
- **Forwarding abuse:** messages taken out of context and re-shared into groups where the original sender has no presence; the sender cannot respond or correct the record.
- **Screenshot-and-share:** content captured and redistributed outside the app; ephemeral and auto-delete features provide partial mitigation but cannot prevent this.
- **Identity impersonation in group contexts:** a bad actor creating a username or display name designed to be confused with a trusted contact; the trust model relies on username clarity.
- **Trusted signal abuse in group settings:** a group moderator with trusted tier status using priority flags to direct group attention toward a target.

The future blueprint should address each axis with specific feature proposals, explicit accountability trade-offs, and harm ceilings.

## Other Open Items

- **Identity & onboarding model** — finalise verification method defaults for the main public server deployment.
- **Multi-device support** — *escalated from an open item to a cryptographic-architecture dependency.* Multi-device is not a UI feature; it requires a decision on per-device identity keys vs shared identity, cross-device session/sender-key synchronisation, and how a second device joins existing pairwise and group sessions. It interacts directly with prekeys (`RQSM §5.6`), sender-keys (`RQSM §5.7`), and history sync (`RQSM §5.8`). Must be resolved in RQSM before any multi-device UX is designed. Per-device notification deduplication (§4.2.1) sits on top of this and cannot be fully specified until it lands.
- **Calendar integration spec** — exactly which calendar events trigger mute, buffer time configuration, cross-platform calendar access.
- **Key session continuity and unilateral server reassignment** — (a) what happens to an active Double Ratchet session when a chat is moved between folders that reference different XMPP servers. Working assumption: the ratchet session continues (it is transport-agnostic); server-side message history is not migrated. (b) Server assignment is bilateral (§2.2): define what the *other* participant's client does when one party unilaterally reassigns a chat's server — silent follow, prompt, or reject. To be confirmed in RQSM implementation.
- **Axis-by-axis privacy feature scenarios** — detailed scenario brainstorm for each harm axis (queued).

---

*FlowChat Privacy & Mental Health Blueprint v2.2 · Living document, updated as architecture evolves*
