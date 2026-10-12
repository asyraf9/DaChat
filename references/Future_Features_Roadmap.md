# Future Features Roadmap

*Planned and deferred scope for DaChat — the source for future `/speckit-specify` runs*

**Created**: 2026-07-07 · **Revised**: 2026-10-12 · **Living document**

> The first feature is [`specs/001-secure-direct-messaging/spec.md`](../specs/001-secure-direct-messaging/spec.md):
> open key-based signup on the main server, connections by QR or single-use link, end-to-end-encrypted
> 1:1 text, recovery phrase, and basic blocking. Everything else is recorded here.
>
> **Authoritative documents for mechanisms**: `flutter_constitution.md`; `RQSM_Blueprint.md` (secure
> communication); `registration-migration-blueprint.md` (identity, registration, connections, servers,
> migration); `FlowChat_Privacy_MentalHealth_Blueprint.md` (privacy and mental-health features).
>
> **Provenance**: Part A carries forward the scenarios, requirements (old IDs in brackets, e.g.
> `[old FR-017]`), and success criteria of the original whole-product spec (2026-07-07). That spec was
> too large for one Spec Kit feature, so it was split up. Where the registration blueprint changed the
> old intent, the blueprint wins and the change is noted.

## Original product description (2026-07-07)

> "build a secure and private chat app with integrated todo list, checklists, polls, events, notes and
> files sharing (taggable and searchable/viewable by tags and other metadata like date and topic).
> Within each chat (individual or group) you can create todo lists, checklists, polls, events, notes and
> share links, contacts, location, photos and files. Notes, checklists, links, photos, and files can be
> tagged. Chatrooms can have one or more users. Chats can have multiple topics (like telegram chat
> topics). All shared chat items are organized according to topics. Chatrooms can be viewed either as a
> combined chatroom message list or as individual topic 'rooms'. Chatrooms can be organized in folders
> (like telegram folders). Each folder has its own settings. Hierarchical settings: global settings and
> theme, overridden by folder settings and theme, overridden by chat settings and theme. Moving
> chatrooms between folders makes the chatroom inherit from the new folder except for server settings;
> chatrooms with private servers retain private server settings. Built on Flutter."

---

## Part A — Planned feature sequence

Numbers are a suggested order based on dependencies, not fixed spec numbers. Each entry is sized to be
one Spec Kit feature (specify → plan → tasks → implement).

### A1. Additional servers & privacy modes

*Depends on 001.* Lets chats live on servers other than the main server, and adds the stronger privacy
modes.

- **Add a server by domain** with trust-on-first-use: show the server's name and a human-readable key
  fingerprint, require a second "Yes, connect" confirmation, pin the fingerprint, and show a hard
  warning if it ever changes (registration blueprint R4.4–R4.8).
- **Same identity on many servers**: registering on another server publishes the same master identity
  (R4.1, R4.2). Connections and chats are server-local and do not travel (R4.3). Servers never
  federate (§4).
- **Privacy modes** — standard server / private server / no-server — selectable per chat, with each
  mode's trade-offs shown in plain language before committing `[old FR-009]`.
  - Sender identity concealed from servers in private-server and no-server modes. A delivering server
    may still learn the recipient, approximate timing, and size `[old FR-008]`.
  - Server-relayed convenience signals (read receipts, typing, presence) are unavailable in no-server
    mode, and the user is told before selecting it.
- Old acceptance scenario: *Given account setup, when the user chooses a privacy mode, then the
  trade-offs (what a server can and cannot observe, which convenience signals become unavailable) are
  shown in plain language before confirmation.*
- Old success criterion `[old SC-002]`: in private-server and no-server modes, an independent
  inspection of everything a server can observe yields zero readable content and zero sender identity
  for sealed traffic.

### A2. Group chatrooms & group invites

*Depends on 001.* Old User Story 2 plus the registration blueprint's group layer.

- Chatrooms with one or more members and end-to-end-encrypted group messaging `[old FR-012]`.
- Authorized members manage membership and assign roles (admin, moderator) with defined permissions
  `[old FR-013]`. A removed member cannot read messages sent after removal `[old FR-014]`. Members can
  attribute every message to its author, and no member can forge another's message `[old FR-016]`.
- **Group entry = recipient-bound invite** delivered over an existing connection. It is never a
  forwardable link (registration blueprint R1.2, R1.2a). The creator of a group is its admin by
  construction (R1.3).
- **Invite delivery**: the invite appears inside the DM thread with the inviting admin, the chat list
  shows a distinct "pending invite" badge, and the unactioned invite is pinned in the thread
  (R1.11–R1.13).
- **Group settings** (member list, roles, permissions, invite-confirmation policy) are per group and
  never inherited from folders. Optional per-group ID confirmation at invite (R1.17–R1.20).
  Near-simultaneous admin edits resolve last-write-wins, with a visible system message for each edit
  (R1.21).
- *Changed by the registration blueprint*: the old "who can add / message / find me" settings
  `[old FR-015]` are largely replaced by invite-only group entry and no directory. Revisit whether any
  residual control is needed.
- Open dependency: **sole-admin succession** — a room whose only admin disappears cannot be governed
  (registration blueprint R5.21).
- Old scenarios: create room and add members → all exchange E2EE messages; assign role → permissions
  granted; remove member → no forward read access; any member's message is attributable and
  unforgeable.

### A3. Media & attachments

*Depends on 001.*

- Share links, contact cards, location, photos, and files with the same end-to-end protection as
  messages `[old FR-018]`.
- Embedded identifying metadata (EXIF/location) is stripped by default, with an explicit per-send
  opt-out `[old FR-024]`. 100% of shares are stripped unless opted out `[old SC-007]`.
- Media is stored encrypted at rest. Decrypted media is never cached as plaintext. Thumbnails follow
  the same rules `[old FR-025]` (privacy blueprint §3.8).

### A4. Shared items

*Depends on A3 (and A2 for groups).* Old User Story 3.

- Create and share **todo lists, checklists, polls, events, and notes** in any chat `[old FR-017]`.
- Collaborative updates to todos/checklists are reflected for everyone `[old FR-019]`. Poll votes and
  results follow the poll's configuration `[old FR-020]`.
- **Bounded events**: title, start/end, optional location, an optional single reminder, optional simple
  recurrence (none / daily / weekly / monthly), and RSVP `[old FR-021]`. Richer calendar behaviour is
  in B2.
- Each item type can be created and shared in under 30 seconds `[old SC-004]`.
- May be split into two features (lists/checklists/notes, then polls/events) if planning shows it is
  too large.

### A5. Topics

*Depends on A2.* Old User Story 4.

- A chatroom contains multiple named topics, and every message and shared item belongs to one
  `[old FR-026]`.
- View a room as one combined chronological stream or as individual per-topic rooms `[old FR-027]`.
- Filtering items by topic returns only that topic's items.

### A6. Tags & search

*Depends on A4 and A5.*

- Apply one or more tags to notes, checklists, links, photos, and files `[old FR-022]`.
- Find items by tag, date, and topic, with a clear empty state when nothing matches `[old FR-023]`.
- 100% precision/recall against a known fixture, and results in under 1 second for at least 1,000
  items `[old SC-005]`.

### A7. Folders & the settings/theme cascade

*Depends on A2.* Old User Story 5, as amended by registration blueprint R1.17.

- Organise chatrooms into folders, each with its own settings and theme `[old FR-028]`.
- **Personal** settings (theme, notifications) resolve global → folder → chat. Each level overrides
  only the keys it sets `[old FR-029]`.
- Moving a chat re-inherits the destination folder's personal settings, **except server settings**
  `[old FR-030]`. A chat on a private server keeps its server settings `[old FR-031]`.
- *Changed by the registration blueprint*: **group settings are never inherited**. A folder can only
  bulk-apply a one-time edit to the groups it contains (R1.17).
- At least 90% of usability-test participants correctly predict the effective setting and the result
  of a folder move, including the server-settings exception `[old SC-006]`.

### A8. Notification & attention controls

*Depends on A7.* Old User Story 6, scenarios 1–7.

- Granular notifications (sound, vibration, banner, preview, badge/unread counts, activity indicator,
  type all / mentions / none) at global, folder, and chat scope `[old FR-032]`.
- Per-folder quiet schedules with an override that expires automatically or on cancel
  `[old FR-033]`. On-call mode, where direct mentions pierce through `[old FR-034]`.
- Low-friction **silence** with quick-pick durations and a re-entry summary (unread count, time since
  last message, membership changes) `[old FR-035]`.
- **Trusted-sender tier** governing which priority signals and mentions pierce filters, with a
  per-sender rate limit; silence overrides it `[old FR-036]`. Privacy-safe previews for non-trusted
  senders `[old FR-037]`.
- **Structured catch-up view** — mentions, priority flags, assigned todos, direct replies — with no
  semantic analysis `[old FR-038]`. No false omissions against a known fixture `[old SC-010]`.

### A9. Safety & history controls

*Depends on 001 (presence parts on A1/A2).* Old User Story 6, scenarios 8–11.

- **Presence controls**: last-seen/online, read receipts, typing indicators, with scope options, and
  unavailable in no-server mode `[old FR-039]`.
- **Reporting**: opaque evidence (references, never plaintext) to the operator in server modes; in
  no-server mode, local block plus optional local evidence export, and the user is told which applies
  `[old FR-041]`.
- **Edit/delete** within configurable windows, and a **per-chat auto-delete** timer. The user is told
  when deletion cannot be guaranteed everywhere `[old FR-042]`. Deletion removes content from the local
  history store (RQSM §5.8).
- **Context-scoped display names** (a different name or avatar per folder or group) — reserved by
  registration blueprint R1.10.

### A10. Account security extras

*Depends on 001.*

- **PIN-escrow recovery**: the recovery phrase is encrypted with a user PIN and escrowed to a
  rate-limited, oblivious (enclave-style) recovery service (registration blueprint R3.2, R3.3a). This is
  a separate hardened service, which is why it is not in 001.
- **Passkeys**: WebAuthn/FIDO2, domain-scoped per server, as a fast local re-auth convenience, ideally
  with two registered (R2.5–R2.7).
- **User-held encrypted history backup and restore.** Recovery restores identity only, and 001's
  storage design must not preclude this.

### A11. Multi-device

*Depends on 001 and A10.* Account model defined by registration blueprint §3.3: a new device makes a
subordinate key, an existing master-key device authorizes it, and device keys are revocable
independently (R3.5–R3.7). Still open, and needed before UX (privacy blueprint §7):
- cross-device session and sender-key synchronisation;
- history synchronisation;
- per-device notification de-duplication.

### A12. Chat migration between servers

*Depends on A1 and A2.* Registration blueprint §5 in full:
- a single-confirm, atomic, single-device migration pipeline;
- a frozen member set and a "Migrate to new room" credential bound to each member;
- decrypt-then-re-encrypt history transfer that resumes after interruption;
- archive / time / user-based retirement, local purge, and straggler reinvite.

---

## Part B — Larger deferred subsystems

### B1. Resilient offline / mesh transport

- **5-scenario fallback** (RQSM §7): XMPP → WiFi Direct → BLE mesh → acoustic (ultrasound FSK) →
  LoRa/SDR, with automatic driver switching.
- **Stealth discovery** (RQSM §6): per-contact rotating HMAC beacons, plus revocation.
- **Panic Mode** (RQSM §6.3).
- **Store-and-forward / sneakernet sync** (RQSM §7.3), including the at-rest metadata-encryption
  investigation.

**Why deferred**: very large, hardware-dependent, and on-device-only testing.

### B2. Google Calendar-grade events

- Full RRULE recurrence and multiple reminders.
- Rich and geofenced location.
- Calendar-aware mute (privacy blueprint §4.2.1).
- External calendar import/export/sync.

### B3. Cyberbullying & group-dynamics controls

Needs its own blueprint first (privacy blueprint §7). Threat axes:
- coordinated pile-ons;
- forwarding abuse;
- screenshot redistribution;
- display-name impersonation (names are self-asserted and non-unique);
- trusted-signal abuse by moderators.

### B4. Super-secure QR-only contacts

A per-user or per-contact policy that accepts only in-person QR connections and refuses link-based
connections.

### B5. Large-group cryptographic scaling

MLS (RFC 9420) once group sizes justify it (RQSM §5.7).

### ~~B6. Hybrid post-quantum identity authentication (ML-DSA)~~ — adopted

Adopted into the core design (registration blueprint R2.1a/R2.4a, RQSM v7 §5.1): the master identity is
Curve25519 + ML-DSA-87 with dual signatures, and libsignal's Triple Ratchet is used from v1.

---

## Part C — Open design items

- **Server reassignment for 1:1 chats**: registration blueprint §5 defines admin-triggered migration
  for rooms. Who may move a 1:1 chat, and what the other participant sees (privacy blueprint §7,
  RQSM §8), is still open.
- **Sole-admin succession** (registration blueprint R5.21): a general room-governance primitive.
- **First-use walkthroughs**: account creation, and creating a "family" server (registration blueprint
  §7).
- ~~Verification-method defaults for the main server~~ — resolved: registration is open and key-based.

---

*Update this file whenever scope changes or a deferred item is promoted to its own spec.*
