# Feature Specification: Secure Direct Messaging (Main Server)

**Feature Branch**: `001-secure-direct-messaging`

**Created**: 2026-10-06

**Revised**: 2026-10-12 (realigned to `references/registration-migration-blueprint.md` v1.1)

**Status**: Draft

**Input**: User description: "Secure one-to-one messaging foundation for DaChat (standard-server mode). Scope: (1) phone-number-free onboarding via a one-time server invite link only (admin approval and email+CAPTCHA deferred); (2) establishing a contact with a remote person via server-distributed key bundles, contacts start "not verified", out-of-band safety-code comparison (e.g. scanned QR) promotes to "verified", a verified contact's identity change shows a prominent warning and is never silently re-trusted; (3) end-to-end-encrypted one-to-one text messaging through the standard (default) server mode, offline delivery on reconnect with accurate delivery states; (4) basic blocking: blocked contact's messages are dropped and never shown/notified (enforced server-side and on-device), user cannot message them until unblocked, they cannot start new conversations, blocked person is not told, unblocking restores everything, blocking never affects other contacts; (5) cross-cutting baseline: hardware-backed long-term key storage with honest guarantees (weaker on platforms without a secure element), no third-party telemetry/analytics/crash SDKs, localizable text, light and dark themes, accessibility labels, single active device per account without precluding multi-device. Out of scope: private-server and no-server modes, groups, media/attachments, shared items, topics, tags/search, folders/settings cascade, notification/attention controls, presence, reporting, edit/delete/auto-delete, mesh transports, multi-device."

> **Scope note**: This is the first slice of DaChat: the secure one-to-one messaging foundation on the
> **main server**. During clarification the original input was realigned to the registration
> blueprint. As a result, registration is open and key-based with no invite, username, or password;
> contacts connect by QR or single-use link instead of username lookup; and a recovery phrase is
> included. The full product sequence and deferred scope are in `references/Future_Features_Roadmap.md`.
> Mechanisms are governed by `references/registration-migration-blueprint.md`,
> `references/RQSM_Blueprint.md`, and `references/FlowChat_Privacy_MentalHealth_Blueprint.md`; they
> are a planning concern, not part of this spec.

## Clarifications

### Session 2026-10-12

- Q: When someone you've never talked to sends you their first message, how should DaChat handle it?
  → A: Message requests were originally chosen. Then, per the registration blueprint (§1.1), there is
  no username directory, and nobody can contact a user without a connection the user took part in
  (QR scan, or a link they shared and the other person confirmed). Message requests are therefore
  unnecessary and are not part of this feature.
- Q: If a user loses their phone or reinstalls the app, should they be able to recover their account
  identity or message history? → A: Identity, yes. Message history, no. Per registration blueprint
  R2.2, R3.1, and R3.4:
  - a recovery phrase is generated silently at signup;
  - the user is nudged later, without blocking signup, to save it;
  - entering it on a new install restores the same identity.
  History is never stored on a server, so it is not restored. PIN-protected escrow of the phrase and
  passkeys are deferred.
- Q: What should happen to a user's messages and identity on the device when they sign out?
  → A: Wipe. There is no password, so "sign out" is **Remove from this device**. It erases the
  identity, history, connections, and block list from the device, after a warning and a typed
  confirmation. Returning requires the recovery phrase (same identity) or creating a new identity.
- Q: Should people on different DaChat servers be able to message each other in 001? → A: No.
  Servers never federate (registration blueprint §4). Identity is portable across servers, but
  connections and chats are server-local. 001 uses only the main server, whose address is built into
  the app. Adding other servers and migrating chats are later features.
- Q: How are shareable connection links protected against forwarding or interception?
  → A: Each link is single-use, expires after 24 hours, and can be revoked by its creator. The
  creator can optionally require ID confirmation (registration blueprint R1.5a, R1.6), which guards
  against a forwarded link or a man-in-the-middle.
- Q: When a user restores their identity from the recovery phrase on a new phone, should their
  contact list come back too? → A: Yes, through an encrypted contact backup. The contact list
  (identities, display names, trust states, how each was connected, blocks) is kept on the server
  encrypted under a key only the recovery phrase can derive. Restore brings back contacts and trust,
  but never message history. The server sees only an opaque blob and its size.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create an identity, connect in person, and message privately (Priority: P1)

A person installs DaChat and is ready to use it within seconds. No invite, phone number, email,
username, or password is needed: their device creates their identity. They set a display name, meet
a friend, scan each other's QR codes to connect, and exchange text messages that the server operator
cannot read. Messages sent while the other person is offline arrive when they reconnect, and the
sender always sees an accurate delivery state.

**Why this priority**: This is the irreducible core: a private, identifier-free, end-to-end-protected
conversation between two people, with the strongest connection method. Every later feature builds on
it. Shipped alone, it is already a usable private messenger for people who can meet.

**Independent Test**: On a test deployment of the main server, create two identities on two devices,
connect them by mutual QR scan, exchange messages in both directions (including while one is
offline), and confirm by inspecting server-side data that no message content and no human-readable
identifier (display name or similar) is present.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** the person opens the app, **Then** an identity is created on
   the main server without asking for any invite, phone number, email, username, or password, and
   without requiring the recovery phrase to be shown or saved first.
2. **Given** identity creation, **When** setup finishes, **Then** the app explains in plain language
   what the server can and cannot observe. The server cannot read messages or display names. It can see
   which identities exchange messages, when, and approximately how large they are.
3. **Given** a new identity, **When** the person sets a display name, **Then** it is shared only with
   people they connect with, end-to-end protected, and never readable by the server.
4. **Given** two people together, **When** each scans the other's QR code, **Then** a connection is
   established, each sees the other's display name, and the contact is marked "verified".
5. **Given** a connection, **When** a message is sent, **Then** its readable content is available
   only to the two participants and is never observable in plaintext by the server.
6. **Given** a recipient who is offline, **When** a message is sent, **Then** the sender sees "sent".
   The message is delivered and shown when the recipient next connects, and the sender's state then
   changes to "delivered".
7. **Given** a sender without connectivity, **When** they send a message, **Then** it is queued on
   their device as "pending" and sent automatically when connectivity returns.
8. **Given** a message that cannot be sent after retries, **When** sending fails permanently,
   **Then** the sender sees "failed" with an option to retry.

---

### User Story 2 - Connect remotely by link and manage trust (Priority: P2)

A user wants to connect with someone they cannot meet. They create a single-use connection link and
send it through any channel they already use. Each time, they decide whether the other person must
also pass an ID confirmation (a code word agreed out of band). The recipient opens the link and taps
to confirm. A link connection is "not verified" unless ID confirmation succeeded or the two later
compare safety codes. Any change to a contact's identity is surfaced and never silently trusted.

**Why this priority**: Most family and workplace contacts are remote. Links make DaChat usable
beyond in-person meetings. A link is weaker than a QR scan, because the confirmation tap is consent,
not proof of identity, so the trust UX must be explicit. Depends on US1.

**Independent Test**: Create a link without ID confirmation, redeem it on a second device, and
confirm the connection is "not verified". Try the same link again and confirm it is refused. Create a
link with code-word confirmation and confirm that a wrong code word fails and the right one yields
"verified". Compare safety codes on a "not verified" contact and confirm it becomes "verified".
Replace one party's identity and confirm the other side's warning or notice.

**Acceptance Scenarios**:

1. **Given** a user creating a link, **When** they have no saved personal default, **Then** they must
   explicitly choose yes or no for "require ID confirmation" before the link is generated. Out of the
   box, the suggested method is QR, link ID confirmation is off, and the confirmation type is code
   word.
2. **Given** a created link, **When** the creator views it, **Then** they see that it is single-use
   and when it expires (24 hours), and they can revoke it.
3. **Given** a valid link, **When** the recipient opens it and taps to confirm, **Then** a connection
   is established, display names are exchanged, and the link can never be used again.
4. **Given** a link that is expired, already used, or revoked, **When** someone opens it, **Then** no
   connection is made and they see a plain explanation.
5. **Given** a link that requires ID confirmation, **When** the recipient taps to confirm, **Then**
   they must also enter the agreed code word. A correct word connects them as "verified". A wrong word
   connects nobody and consumes the link after a limited number of attempts (3).
6. **Given** a "not verified" contact, **When** both compare their safety codes out of band and
   confirm a match, or scan each other's safety-code QR in person, **Then** the contact becomes
   "verified". A mismatch leaves it "not verified" and explains what that could mean.
7. **Given** a "verified" contact, **When** their identity changes, **Then** a prominent warning
   blocks further messaging in that conversation until the user acknowledges it, the contact reverts
   to "not verified", and nothing is re-trusted without the user's action.
8. **Given** a "not verified" contact, **When** their identity changes, **Then** a visible "safety
   code changed" notice appears in the conversation.

---

### User Story 3 - Secure and restore my identity with a recovery phrase (Priority: P3)

Some time after setup, the app gently suggests saving the recovery phrase. The user views and writes
it down. Later their phone is lost. On a new phone they choose "Restore", enter the phrase, and get
their same identity back. Their contacts come back, and the contacts see no change and no warning. Their old
message history is gone, as the app told them it would be.

**Why this priority**: Without recovery, every lost phone forces every contact to see an identity
change and re-verify, which erodes trust in warnings. The phrase is already part of identity creation
(US1), so restoring from it completes that story. Independent of US2 and US4.

**Independent Test**: Create an identity and connect two contacts. Record the recovery phrase. Erase
the device, restore from the phrase on a fresh install, and confirm that both contacts reappear with
their trust states, that contacts see no identity change, that messaging resumes without
re-connecting, and that history is absent, as disclosed.

**Acceptance Scenarios**:

1. **Given** a new identity, **When** setup completes, **Then** a recovery phrase already exists,
   and the user was not required to view it.
2. **Given** an identity whose phrase has not been saved, **When** some time has passed (default:
   next app launch at least 24 hours after setup), **Then** a dismissible "Secure your account"
   nudge offers to show the phrase. It reappears periodically until the user saves the phrase or turns
   the reminders off.
3. **Given** the user views the phrase, **When** they finish, **Then** they must confirm they saved it
   by correctly re-entering a few randomly chosen words.
4. **Given** a fresh install, **When** the user chooses "Restore" and enters a correct phrase,
   **Then** their same identity is restored together with their contact list, each contact's trust
   state, and their block list. Contacts see no identity change, and messaging with them resumes
   without re-connecting. The app states that message history cannot be restored.
5. **Given** a restore attempt, **When** the phrase is wrong or incomplete, **Then** nothing is
   restored and the user can correct it without starting over.
6. **Given** an identity active on device A, **When** it is restored on device B, **Then** B becomes
   the single active device. A is signed out and erases its local copy the next time it connects,
   telling its user why.
7. **Given** a user who removes DaChat from a device, **When** they confirm, **Then** they are warned
   that without their recovery phrase the identity cannot be recovered, and they must type a
   confirmation before everything is erased.

---

### User Story 4 - Block and unblock a contact (Priority: P4)

A user stops an unwanted person reaching them. A blocked contact's messages are never shown or
notified, the user cannot message them, and the blocked contact cannot re-connect. The blocked person
is not told. Unblocking restores messaging. Blocking one contact never affects any other.

**Why this priority**: Connections need the user's participation, so unwanted contact is less likely
than on directory-based messengers. Still, a connection can sour, or a link can be forwarded once, and
users need a mainstream-parity way to cut contact. Depends on US1.

**Independent Test**: With three identities, have A block B. Confirm that B's messages never appear
or notify on A, that A cannot send to B, that B cannot re-connect to A by any QR or link, and that B
sees no "blocked" indication. Confirm A↔C is unaffected. Unblock and confirm new messages flow.

**Acceptance Scenarios**:

1. **Given** a contact, **When** the user blocks them, **Then** any later message from that contact
   is discarded before it is displayed, stored as readable content, or notified, even if it reaches
   the device.
2. **Given** a blocked contact, **When** the user opens their conversation, **Then** history stays
   readable, sending is disabled, and an unblock option is shown.
3. **Given** a blocked contact, **When** they try to message or re-connect (via any QR or link),
   **Then** nothing reaches the user. Their messages stay "not delivered" with no "blocked"
   indication.
4. **Given** a blocked contact, **When** the user unblocks them, **Then** messaging works again for
   messages sent after the unblock. Messages sent during the block are never delivered.
5. **Given** several contacts, **When** one is blocked or unblocked, **Then** no other contact's
   conversation, trust state, or delivery changes, and nobody needs to re-connect.
6. **Given** the user's settings, **When** they open the blocked list, **Then** they can see and
   unblock every blocked contact.

---

### Edge Cases

- **Identity creation while offline**: publishing the identity requires reaching the main server.
  The user is told setup will finish when connectivity returns, and nothing is published until then.
- **Link opened on a device without the app**: the person is guided to install it, and the link stays
  valid until it expires.
- **Two people redeem the same link at once**: exactly one connection is made. The other gets the
  "already used" explanation.
- **Scanning one's own QR code or opening one's own link**: refused, with an explanation.
- **Connecting with someone already connected**: no duplicate contact is created. The existing
  contact is kept, and a matching identity confirms it.
- **One-time contact-establishment material exhausted**: messaging still starts. The reduced
  first-message protection is handled automatically.
- **Verified contact's identity changes with queued messages**: queued messages to that contact are
  held until the user acknowledges the warning (US2 scenario 7).
- **Blocked contact mid-delivery**: messages arriving after the block takes effect are discarded,
  even if sent before it.
- **Lost device without a saved phrase**: the identity cannot be recovered. The user creates a new
  one, and contacts see the identity change. This was disclosed by the nudge (US3).
- **Restore interrupted, or removal interrupted** (app killed midway): on next launch the operation
  completes or rolls back cleanly. No partial identity is ever usable.
- **Contact backup out of date** (e.g. a change made while offline): the backup updates when
  connectivity returns. A restore before that sync recovers the last synced list, and the user is
  told if recent changes may be missing.
- **Contact backup missing or unreadable**: restore still recovers the identity and tells the user
  that contacts must be re-connected. Contacts see no identity change.
- **Platform without a secure element**: the user is told during setup that key protection on this
  device is weaker.
- **Device storage full**: an incoming message that cannot be stored is not acknowledged as
  delivered, and the user is told.

## Requirements *(mandatory)*

### Functional Requirements

**Identity & registration**

- **FR-001**: The system MUST create a user's identity on first launch and register it on the main
  server without any invite, and without collecting a phone number, email address, username,
  password, or any other real-world-linkable identifier.
- **FR-002**: The main server's address MUST be built into the app. No server choice is offered in
  this release.
- **FR-003**: The system MUST protect the identity's private keys with hardware-backed protection
  where the device provides it. On devices without it, the system MUST use the strongest available
  alternative and MUST disclose the weaker guarantee.
- **FR-004**: The system MUST protect the identity against future quantum attacks on account
  authentication, so that impersonating a user requires defeating both a classical and a
  post-quantum scheme (registration blueprint R2.4a).
- **FR-005**: Before setup completes, the system MUST explain in plain language what the server can
  and cannot observe.
- **FR-006**: A user MUST be able to set and change a single display name. The display name MUST be
  shared only with connected contacts, end-to-end protected, and never readable or searchable by the
  server.
- **FR-007**: There MUST be no directory, search, or lookup by which any user can be found.

**Connections**

- **FR-008**: The system MUST let two people connect by mutual in-person QR scan. A QR connection MUST
  result in a "verified" contact.
- **FR-009**: The system MUST let a user create a connection link to share through any external
  channel. The link MUST be single-use, MUST expire 24 hours after creation, MUST be revocable by its
  creator before use, and MUST connect only after the recipient explicitly taps to confirm.
- **FR-010**: Expired, used, and revoked links MUST be refused with a plain explanation, and no
  connection made.
- **FR-011**: Before generating a link, the creator MUST explicitly choose whether ID confirmation is
  required, unless they have saved a personal default. Out-of-the-box defaults: QR suggested first,
  link ID confirmation off, confirmation type code word.
- **FR-012**: When a link requires ID confirmation, the recipient MUST enter the code word agreed
  out of band. A correct entry yields a "verified" contact. The link MUST be consumed after 3 failed
  attempts.
- **FR-013**: A link connection without successful ID confirmation MUST be "not verified".
- **FR-014**: The system MUST let users upgrade a "not verified" contact to "verified" by comparing a
  safety code out of band, or by scanning it in person.
- **FR-015**: When a "verified" contact's identity changes, the system MUST show a prominent warning
  that blocks messaging in that conversation until acknowledged, MUST revert the contact to "not
  verified", and MUST NOT silently re-trust it.
- **FR-016**: When a "not verified" contact's identity changes, the system MUST show a visible
  "safety code changed" notice.
- **FR-017**: Trust established for a contact MUST persist for that identity until the identity
  changes (registration blueprint R1.8).

**Messaging**

- **FR-018**: The system MUST deliver one-to-one text messages between connected contacts, with
  content protected end to end, so the server cannot observe it in plaintext.
- **FR-019**: The system MUST show each sent message's state: "pending", "sent", "delivered", or
  "failed" (with retry).
- **FR-020**: The system MUST queue messages composed without connectivity and send them when
  connectivity returns.
- **FR-021**: The server MUST hold messages for an offline recipient only until they are delivered,
  preserving each sender's order. It MUST NOT keep any archive afterwards.
- **FR-022**: Readable history MUST be stored only on the participant's device, encrypted at rest,
  and excluded from operating-system cloud and device backups.
- **FR-023**: The system MUST notify the user of new messages. By default the notification MUST NOT
  show message content; at most it shows the sender's display name.
- **FR-024**: Where background delivery relies on a platform push service, the system MUST disclose
  that the push provider can observe message timing, though not content.

**Recovery & device lifecycle**

- **FR-025**: The system MUST generate a recovery phrase at identity creation without requiring the
  user to view or save it during setup.
- **FR-026**: The system MUST offer a later, dismissible "Secure your account" nudge to view and save
  the phrase, and MUST confirm saving by having the user re-enter randomly chosen words.
- **FR-027**: On a fresh install, the system MUST let the user restore their identity by entering the
  recovery phrase. A restored identity MUST appear unchanged to contacts.
- **FR-028**: The system MUST state, at the restore screen and in the nudge, that message history is
  never restored.
- **FR-045**: The system MUST keep an encrypted backup of the user's contact list on the server, and
  MUST update it whenever a contact, trust state, display name, or block changes. The backup holds
  identities, display names, trust states, connection method, and block entries. It MUST be encrypted
  under a key derived only from the recovery phrase, so the server can neither read it nor tell which
  identities it contains. A restore MUST recover it in full.
- **FR-029**: An identity MUST be active on exactly one device at a time. Restoring on a new device
  MUST sign out and erase the previous device the next time that device connects, with an
  explanation shown on it.
- **FR-030**: The system MUST let the user remove DaChat from the device. This MUST erase the identity,
  history, connections, and block list from the device, after a warning that the identity is
  unrecoverable without the phrase and a typed confirmation. The encrypted contact backup (FR-045)
  stays on the server, so a later restore can recover the contacts.
- **FR-031**: Restore and removal MUST either complete or roll back cleanly, even if interrupted.
- **FR-032**: Identity and history storage MUST NOT preclude multi-device, PIN-escrow recovery,
  passkeys, or encrypted history backup in later features.

**Blocking**

- **FR-033**: The system MUST let a user block and unblock any contact, from the conversation and
  from a blocked list.
- **FR-034**: While a contact is blocked, the system MUST stop their messages and connection
  attempts before they reach the user. Any that still reach the device MUST be discarded before they
  are displayed, stored as readable content, or notified.
- **FR-035**: While a contact is blocked, the user MUST NOT be able to message them. Existing
  history MUST remain readable.
- **FR-036**: The blocked person MUST receive no indication of being blocked.
- **FR-037**: Unblocking MUST restore messaging for messages sent after the unblock, and MUST NOT
  deliver messages sent during the block.
- **FR-038**: Blocking or unblocking one contact MUST NOT affect any other contact, and MUST NOT
  require anyone to re-connect.

**Privacy baseline**

- **FR-039**: The system MUST prevent screenshots and app-switcher previews of QR, safety-code, and
  recovery-phrase screens.
- **FR-040**: The system MUST NOT send message content, behavioural analytics, or crash telemetry to
  any third-party operator. Diagnostics MUST be on-device or self-hosted, and content-free.
- **FR-041**: The system MUST NOT write message content, display names, identity or key material,
  recovery phrases, or contact identifiers to any log.

**Accessibility, language & appearance**

- **FR-042**: All user-facing text MUST be localizable, with English provided in this release.
- **FR-043**: The system MUST support light and dark themes, following the device setting by default.
- **FR-044**: Every interactive element and non-decorative image MUST expose a screen-reader label,
  and every screen in this feature MUST be operable with a screen reader.

### Key Entities *(include if feature involves data)*

- **Identity**: the user's account, created on the device. It has hybrid public keys published to
  the server and no human-readable identifier. It is active on exactly one device at a time in this
  release.
- **Recovery Phrase**: the human-writable phrase from which the identity can be re-created. It is
  never sent to any server.
- **Display Name**: a single self-asserted name per identity, shared end-to-end with contacts only.
- **Connection Link**: a single-use, 24-hour, revocable invitation to connect, with an optional
  ID-confirmation requirement (code word).
- **Contact**: another identity the user is connected with. It has a trust state ("verified" or
  "not verified"), how it was connected (QR or link, and whether ID-confirmed), and a block state.
- **Conversation**: a one-to-one, end-to-end-protected exchange between two connected identities,
  holding the local readable history.
- **Message**: a text unit with an author, a timestamp, protected content, and a delivery state
  (pending / sent / delivered / failed).
- **Contact Backup**: an opaque, server-held encrypted copy of the user's contact list, trust states,
  and blocks, decryptable only with a key derived from the recovery phrase. It holds no message
  history.
- **Safety Code**: a human-comparable code (and QR form) derived from both identities, used to verify
  or re-verify a contact.
- **Block Entry**: the user's record that one contact is blocked. It affects only that contact.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Two people who are together can go from first opening the app to exchanging their first
  protected message in under 3 minutes.
- **SC-002**: An independent inspection of everything the server stores and relays yields zero
  readable message content, zero display names, and zero real-world-linkable identifiers. The contact
  backup appears only as an opaque blob.
- **SC-003**: 95% of messages to an online recipient are delivered and shown within 3 seconds.
  Messages to an offline recipient are delivered within 30 seconds of the recipient reconnecting.
- **SC-004**: 100% of messages report a delivery state that matches what actually happened.
- **SC-005**: 100% of expired, used, or revoked links are refused, and no link ever produces more
  than one connection.
- **SC-006**: When a verified contact's identity changes, 100% of affected users see the blocking
  warning before any further message is exchanged in that conversation.
- **SC-007**: In usability testing, at least 80% of participants complete an in-person QR connection
  without assistance in under 1 minute.
- **SC-008**: In 100% of restore tests with a correct phrase, the full contact list, trust states,
  and blocks return. Contacts see no identity change, and messaging resumes without re-connecting.
- **SC-009**: Identity creation requires 0 mandatory steps involving the recovery phrase, and at least
  60% of active users have saved their phrase within 30 days of setup.
- **SC-010**: Blocking takes effect immediately. 0 messages from a blocked contact are shown or
  notified, 0 "blocked" indications reach the blocked person, and 0 other contacts are affected.
- **SC-011**: Network inspection over a full test session shows 0 egress events of content,
  behavioural analytics, or crash telemetry to any third-party operator.
- **SC-012**: Every screen in this feature passes a screen-reader walkthrough and renders correctly in
  both light and dark themes.

## Assumptions

- **Connectivity**: users have intermittent-to-reliable internet. Offline mesh operation is out of
  scope.
- **Main server only**: the main server's address is built in. Self-hosted servers, adding servers
  (with fingerprint pinning), and chat migration are later features (roadmap A1, A12).
- **ID confirmation types**: code word only in this release. Video-call confirmation is deferred
  until the app has calls.
- **Recovery**: identity plus the encrypted contact backup; never message history. PIN-escrow of the phrase (which needs a separate hardened recovery
  service), passkeys, and encrypted history backup are deferred (roadmap A10).
- **Display name**: a single global name. Per-context names are deferred (registration blueprint
  R1.10).
- **Message content**: plain text up to 4,096 characters. No read receipts or typing indicators;
  "delivered" is the furthest state.
- **Single active device**: multi-device is deferred (roadmap A11) but not designed out.
- **Platforms**: Android and iOS first. Linux desktop is secondary, with disclosed weaker key storage.

## Out of Scope *(see `references/Future_Features_Roadmap.md`)*

- Additional or self-hosted servers, privacy modes (private-server / no-server), and chat migration.
- Groups, group invites, roles, and group settings.
- Media, attachments, shared items, topics, tags, and search.
- Folders and the settings/theme cascade.
- Notification and attention controls, presence, reporting, edit/delete/auto-delete.
- PIN-escrow recovery, passkeys, encrypted history backup, and multi-device.
- Video-call ID confirmation, and context-scoped display names.
- Offline mesh transports, Panic Mode, stealth discovery, and store-and-forward sync.
