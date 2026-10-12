# Blueprint: User Registration & Chat Migration

**Status:** Draft v1.1 · **Scope:** Account/identity layer, workspace layer, cross-server chat migration
**Depends on:** RQSM identity keys (hybrid Curve25519 + ML-DSA; ML-KEM-1024 key agreement), libsignal Triple Ratchet (Double Ratchet + SPQR), Sealed Sender, XMPP routing layer
**Open items:** Edge cases deferred to a follow-up pass (see §7)

<!--
  Change log
  | Version | Change |
  |---------|--------|
  | v1      | Initial draft. |
  | v1.1    | ML-KEM-768 corrected to ML-KEM-1024 (libsignal's PQXDH parameter). R2.1 / R2.1a / R3.1 / R3.6 |
  |         | reconciled: the master identity is derived in software from the recovery seed and stored |
  |         | wrapped under a non-exportable hardware key, because a key generated inside a secure element |
  |         | cannot be exported to a mnemonic or re-derived. R1.5a added: shareable connection links |
  |         | are single-use, expiring, and revocable. Walkthroughs updated to match. |
-->

**Authority:** Authoritative for account identity, registration, contact connections, multi-server use, and chat
migration. Ranks after `flutter_constitution.md` and alongside `RQSM_Blueprint.md`, which has been updated (v7) to match
it. Where they appear to conflict on these topics, this blueprint wins and RQSM must be corrected.

---

## 0. Agent instructions

- Treat the two-layer model in §1 as invariant. No feature may collapse the account layer and the workspace layer into a single gate.
- The account identity is **client-generated key material**, never a server-held credential. No flow may introduce a server-side password, email, or phone number as the primary account identifier.
- Rules are normative (MUST/SHOULD/MAY). Rationale lives in the *Why* notes and may be skipped when implementing.

---

## 1. Two-layer trust model

The system separates *identity* from *access*. These are distinct layers with different trust requirements.

| Layer | What it gates | Trust requirement | Registration |
|---|---|---|---|
| **Account / identity** | Existence of an identity on a given server | None | Open, self-serve |
| **Workspace** (family / team) | Entry into a specific space's conversations | Invite from a member with standing | Invite-gated |

**Rules**

- **R1.1** — Account registration on any server MUST be open and require no invite.
- **R1.2** — Workspace entry MUST be invite-gated. The invite grants *workspace/room* access only; it MUST NOT be required to create an account.
- **R1.2a** — A workspace/room invite MUST be a **recipient-bound credential**, cryptographically bound to the invitee's identity public key (same mechanism as the migration credential, R5.6a), delivered via Sealed Sender and never exposed as copyable/forwardable text. Consequently, an admin MUST already hold a verified connection with the invitee (§1.1) before a room invite can be issued — there is no room-invite path that bypasses establishing a direct connection first.
- **R1.3** — Creating a new workspace MUST make the creator its admin by construction, with no invite needed (you may always create something new).
- **R1.4** — A workspace invite for a user without an account on the target server MUST silently create that account (same master identity key, see §3) at the moment the invite is accepted.

**Why.** Open account registration is what makes "try the main server, get comfortable, self-host later" frictionless — the identity layer never blocks adoption. The real trust boundary is *which humans are allowed into this family's or company's conversations*, and that boundary lives at the workspace layer. This mirrors Matrix's separation of "register an account on a homeserver" from "join a room," not Signal's single phone-number event that fuses both. Binding invites to a recipient's key (R1.2a) closes the "leaked link lets anyone in" gap that a plain bearer link would otherwise reopen at the workspace layer.

**Admin bootstrap (resolved).** The first user of a family/team is not a special case: they register an ordinary account (R1.1), then *create* a workspace (R1.3), which makes them admin. They then invite everyone else. There is no "first invite" paradox because account creation was never invite-gated.

### 1.1 Contact connections (prerequisite to workspace invites)

Because a workspace invite is recipient-bound (R1.2a), it can only be issued to someone the admin has already **connected with directly** — connecting is a separate, prior step from inviting, not part of the invite itself. Establishing a connection is a **pure user-to-user feature**, entirely independent of any group: it has no group or folder ties of its own, and once established it can be reused for any future invite through that connection, to any group, indefinitely (R1.8). No phone-contact discovery and no server-side searchable username directory are used anywhere in this system (see §4.1's approach to server discovery for the analogous stance one layer up).

**Establishing a connection**

- **R1.5** — Two people MUST establish a direct connection via one of: **(a)** in-person QR scan — each device displays a QR encoding its public identity key; scanning is mutual, in-person, visual confirmation with no impersonation surface — or **(b)** a shareable link/code encoding the sender's public identity key, sent through any external channel, requiring an explicit confirmation tap by the recipient before the connection is established.
- **R1.5a** — A shareable connection link/code (R1.5 option b) MUST be **single-use**. It MUST expire after a fixed period (default **24 hours**) and MUST be revocable by its creator before use. A second redemption, an expired link, or a revoked link MUST be refused, and the person who tried it MUST see a plain explanation. **Why:** a reusable, non-expiring link that encodes your key lets anyone it is forwarded to connect to you. Single use limits a leaked link to one connection. The optional ID confirmation (R1.6) is the defence against that one connection being a forwarded link or a man-in-the-middle substitution.
- **R1.6** — The recipient's confirmation tap on a shareable link is **consent, not identity proof** — it does not verify *who* tapped it. The person initiating the connection MAY additionally require a secondary, out-of-band **ID confirmation** step (e.g. a shared code word, or a brief video call) before treating a link-established connection as verified.
- **R1.7** — The choice between QR and shareable-link discovery, and whether ID confirmation is required for link-based connections (and which type), is a **personal preference of whoever is initiating the connection** — it is not group policy and not a folder setting; it is decoupled entirely from any group the connection will later be used to invite someone into. It MAY be saved as a personal standing default, or decided case-by-case per connection; if case-by-case, there MUST be no silent default — the initiator MUST explicitly choose yes/no for "enable ID confirmation" each time before a link is generated.
- **R1.7a** — Out of the box, before any personal preference is set, the app's default behavior MUST be: discovery method = **QR**; if the person switches to link-based discovery, ID confirmation defaults to **off**; if ID confirmation is then enabled, its type defaults to **code word**. These are personal defaults applied to whoever is initiating a connection, not settings tied to a group or folder.
- **R1.8** — Once a connection with a given identity key has been established and (if required) ID-confirmed, that trust MUST persist for that identity going forward. It is never re-verified for future group invites sent through that connection, regardless of which group(s) the connection is later used to invite that person into. **Group invites themselves need no additional QR/link/ID-confirmation step at invite time** — they inherit their security entirely from the already-established, already-secure connection (delivered via the Double-Ratchet-protected DM route, R1.2a), not from any per-invite discovery mechanism.

**Why.** Ruling out phone-contact discovery and a server-side username directory forces discovery into peer-to-peer/proximity or self-contained shareable-credential shapes — nothing server-mediated survives that constraint cleanly (even privacy-preserving server-side discovery still leaks timing/metadata to the server). QR gives the strongest guarantee available (physical co-presence, mutual visual confirmation); the shareable-link path is structurally weaker — the confirmation tap alone is consent, not proof of identity — which is exactly why R1.6's optional ID-confirmation step exists, left to the initiating person's judgment rather than mandated everywhere at the cost of friction. This entire mechanism governs **person-to-person connection only** — it is not, and was never meant to be, a group-level or folder-level policy. A group invite's security comes from R1.2a (recipient-bound, delivered over an already-established secure connection), not from re-running discovery at invite time.

**Display name (exchanged at connection, not stored server-side)**

- **R1.9** — A display name MUST be a self-asserted attribute, exchanged directly between the two parties at connection establishment alongside the public-key exchange, end-to-end encrypted — never a server-legible or server-searchable field. The server MAY hold an encrypted blob purely for the owner's own cross-device sync, but it remains ciphertext to the server either way.
- **R1.10** — Current scope is a **single global self-asserted display name**, shown identically to every connection. **Context-scoped presentation** (a different name/avatar depending on which folder/workspace a contact belongs to) is explicitly deferred to a future privacy-feature pass (§7); this blueprint reserves room for it but does not implement it.

**Why.** Treating display names the way Signal treats message content — encrypted, self-asserted, never a queryable field — closes the same directory/enumeration risk that ruling out a username database was meant to close in the first place; a human-friendly plaintext handle would have quietly reopened it.

**Invite delivery & visibility**

- **R1.11** — An arriving workspace invite MUST be delivered as a message inside the existing DM thread with the sending admin — not routed to a separate inbox screen. This follows the same pattern already used for the migration credential: the actionable item lives inside the context that grants it, not as a floating separate object.
- **R1.12** — A chat-list thread containing an unactioned invite MUST carry a distinct, uniquely styled badge/indicator, visually differentiated from an ordinary unread-message count, so pending invites remain glanceable across the whole chat list without requiring a separate inbox surface.
- **R1.13** — Within a thread, an unactioned invite MUST be automatically pinned for quick access — not left to be located by scrolling message history.

**Why (invite delivery).** A separate invites inbox was considered and rejected: it adds a new navigational surface competing for attention, breaks "credential lives inside the context that grants it" (the same principle behind the migrate button living inside its room), and risks either duplicating the invite in two places or floating it outside any thread entirely. The chat-list badge gets the one genuine benefit a dedicated inbox would offer — aggregate visibility across multiple pending invites from different people — without adding a screen, consistent with treating attention fragmentation and presence pressure as harms to design against rather than incidental UI tradeoffs.

### 1.2 Personal settings, group settings & folders

**Terminology note.** Earlier drafts of this blueprint used "workspace" as a stand-in for "the family/team's invite-gated space" without checking it against the app's actual existing organizational concept, **folders** (personal, Telegram-style, global → folder → chat settings inheritance). This is now resolved: there is no separate "workspace" entity. The invite-gated unit described throughout §1 as the "workspace layer" **is the group/room itself** — "workspace" and "group" refer to the same thing in this document.

- **R1.17** — Every setting MUST be classified as exactly one of:
  - **Personal** — inheritable through the existing global → folder → chat hierarchy and general app settings. *Examples: chatroom theme, notification preferences.*
  - **Group** — stored as synced state on the group itself (same category as the member list and admin roles, R5.17), scoped **per group**, and **never inheritable** through a folder or any other mechanism. *Examples: member list, roles (admin/moderator/etc.), permissions (e.g. which file types can/cannot be shared), and group-invite confirmation policy (R1.18–R1.19 below).*
- A folder retains its **bulk-apply convenience** for group settings (apply the same discrete edit to every group in the folder at once, per the original intent), but this is explicitly a one-time batch action, not standing inherited authority — the folder holds nothing about a group's settings between applications.

**Group-invite confirmation (new, distinct from first-contact connection)**

Separate from establishing a first connection (§1.1, R1.5–R1.8, which is a personal, person-to-person feature with no group ties), a group MAY additionally gate its own invites:

- **R1.18** — A group's invite-confirmation requirement MUST be a **group setting** (R1.17): per-group, admin-editable, non-inheritable. Options: confirmation tap only (default — mirrors the existing "Join" action, R1.11), or confirmation tap **plus** a required **ID confirmation** step (code word or video call, same mechanism as R1.6), before the invitee is admitted to that group.
- **R1.19** — QR is NOT an option at the group-invite step. Group invites are always delivered exclusively via the existing DM connection (R1.2a); QR applies only to establishing a first connection (§1.1). Skipping QR here is not a new restriction — group invites were never QR-based to begin with.
- **R1.20** — R1.18's ID-confirmation requirement, when a group enables it, MUST apply at the moment of **that group's** invite regardless of whether the invitee already holds an established, trusted connection with the admin (R1.8). This does not contradict R1.8: R1.8 guarantees the underlying cryptographic identity binding never needs to be redone once made. R1.18 is a separate, optional checkpoint a specific group may choose to require at the moment of granting entry to *that* group — a one-time gate per person per group, not a repeated re-verification of the connection itself.

**Conflict resolution for group settings**

- **R1.21** — If two admins directly edit the same group setting (R1.17) at close to the same time, resolution MUST be **last-write-wins on the active value**, but MUST NOT be silent: each edit MUST post as a visible group system message (e.g. "Admin A changed file-sharing permissions to: images only" / "Admin B changed file-sharing permissions to: all files"), so a losing edit remains discoverable by the admin who made it rather than silently overridden.

**Why.** Declaring group settings non-inheritable by definition (R1.17) resolves the "whose folder wins" question that an earlier draft left open: there is no folder-inheritance link for two co-admins to contest, because folders never hold authority over a group's settings at all — only a batch-edit convenience. The narrower question that remains — two admins editing the same group setting directly, near-simultaneously — is answered by R1.21, reusing the same transparent-last-write-wins pattern already established for roles (§5.6), now correctly anchored to real, non-inheritable group state rather than the earlier incorrect example. R1.20 keeps the group-invite ID-confirmation gate consistent with R1.8 by treating "first contact with a person" and "first entry into a particular group" as genuinely distinct events, each entitled to its own confirmation threshold.

---

## 2. Account identity: composition

Account identity is a **client-generated cryptographic keypair**, with an **optional passkey** as a per-server local convenience layer. They are not rivals; they compose.

### 2.1 Master identity key (the account)

- **R2.1** — On first launch, the client MUST generate a fresh recovery seed (R2.2) and derive the master identity keypair from it in software. The master private key MUST be stored only encrypted under a **non-exportable hardware wrapping key** held in the device's secure element (RQSM "hardware-derived" storage tier, constitution C15). It is unwrapped only transiently, inside the crypto isolate / native boundary, to sign. It MUST never be persisted in plaintext and never transmitted.
- **R2.1a** — The master identity keypair MUST be **hybrid**: a classical Curve25519 keypair (the libsignal identity key) and an **ML-DSA** keypair, both derived from the same recovery seed at first launch and stored as in R2.1. Both public keys are published together at registration (extends R2.3).
- **R2.1b** — The master key MUST NOT be generated *inside* the secure element. **Why:** a hardware-generated key cannot be exported to a mnemonic or re-derived from one, so R2.2 / R3.1 recovery would be impossible. Mobile secure elements also do not generally support Curve25519 or ML-DSA keys. The honest guarantee is therefore that the *wrapping* key never leaves hardware, while the identity key exists in memory only briefly while signing.
- **R2.2** — A recovery mnemonic (BIP39-style) MUST be derivable from / bound to the master identity, generated at signup.
- **R2.3** — "Registration" on a server is publishing the identity **public key(s)** (R2.1, R2.1a). The server MUST NOT receive email, phone number, or any real-world-correlatable identifier.
- **R2.4** — Authentication MUST be challenge–response: server sends a nonce, client signs with the identity (or a subordinate device) key, server verifies against the stored public key.
- **R2.4a** — Every signature produced using the master identity key — including R2.4 authentication, R3.6 device authorization, and R5.6c migration triggers — MUST be a **dual signature**: one classical, one ML-DSA, over the same payload. A verifier MUST accept the action only if **both** signatures are valid.

**Why.** Zero server-side PII means there is nothing at the identity layer to leak — the strongest possible position for institutional privacy. The key *is* the account, which is what makes cross-server portability (§4) a non-event rather than a migration. R2.4a closes a gap that FlowChat's own design makes unusually severe: because every other authentication factor was deliberately removed (R2.3 — no password, no phone, no email), the identity key's unforgeability alone carries 100% of the authentication model, with no fallback to catch a forged credential the way a password-reset flow might elsewhere. Once a cryptographically relevant quantum computer exists, a pure-classical signature becomes forgeable (private key derivable from the public key), enabling account impersonation, rogue device authorization, and fake migration triggers — not a "harvest now" risk, since there's no ciphertext to harvest, but a real forward-looking one given expert timelines for a CRQC cluster in the 2030s with 2026 research actively compressing that estimate. Dual-signing means an attacker must break both the classical scheme *and* ML-DSA (a distinct, lattice-based hard problem Shor's algorithm doesn't touch) — the same "adversary must break both layers" property already accepted for message confidentiality via Signal's Triple Ratchet. A bolted-on password was considered and rejected: it would need to be checked at every signature-verification point including peer-verified device authorization (R3.6, which has no server in the loop to check against), and it reintroduces exactly the server-verifiable-shared-secret pattern R2.3 and the oblivious PIN-escrow design (§3.1) were built to avoid.

**Scope note (message confidentiality, out of scope here).** This blueprint governs identity/registration, not the messaging protocol itself — but for consistency: session-key confidentiality (DM content) is a separate concern from the signing role above, already addressed by adopting Signal's Triple Ratchet (Double Ratchet + Sparse Post-Quantum Ratchet, mixed via KDF) rather than deferring PQ protection to a later version. Recommendation: adopt Triple Ratchet from v1 rather than shipping classical-only X3DH first, since libsignal already supports it — deferring it would leave an avoidable harvest-now-decrypt-later window for v1-era message history, which cuts directly against a chat app built around long-lived, migratable message history (§5.3).

### 2.2 Passkey (per-server convenience)

- **R2.5** — The client MAY register a WebAuthn/FIDO2 passkey, scoped to the server's domain, gated behind device biometrics, as a fast local re-auth mechanism.
- **R2.6** — A passkey MUST be treated as a local convenience only. It MUST NOT be treated as the account. Because passkeys are relying-party (domain) bound, a new passkey is registered per server.
- **R2.7** — At onboarding the client SHOULD register at least two passkeys (this device + one backup) where the platform allows, so a single lost device is not fatal at the convenience layer.

**Why.** The passkey gives phishing-resistant, hardware-backed local unlock without ever putting a shared secret on the wire. Keeping it domain-scoped and subordinate to the master key sidesteps the relying-party-binding collision that would otherwise break self-host migration.

---

## 3. Recovery & multi-device

### 3.1 Recovery (device lost, no other device)

- **R3.1** — Recovery MUST be possible from the mnemonic alone: entering it re-derives the master identity keypair (both halves, R2.1a) on the new device, where it is wrapped under that device's own hardware key (R2.1). Recovery restores the **identity** only; message history is not stored on any server and is not restored.
- **R3.2** — The client SHOULD offer an opt-in **PIN-escrow recovery**: the mnemonic is encrypted with a user PIN, and the encrypted blob is escrowed to a rate-limited, oblivious (enclave-style) recovery service. The server MUST NOT see the PIN or the mnemonic in cleartext.
- **R3.3** — If neither a mnemonic backup nor PIN-escrow was set up, account loss is unrecoverable. This is the accepted tradeoff for zero server-held identity and MUST be surfaced honestly (see §3.4).
- **R3.3a** — A recovery-service outage is NOT a new failure mode; it is a temporary instance of R3.3's already-accepted tradeoff. A user holding their raw mnemonic MUST NOT need the service at all (R3.1) and is unaffected by an outage. A user relying solely on PIN-escrow, with no retained mnemonic, is blocked until the service returns — the accepted answer for now is that **the service comes back eventually**; no service redundancy (multi-node/multi-region escrow) is built at this stage. This MAY be revisited if uptime requirements change at scale.

### 3.2 Recovery UX

- **R3.4** — The mnemonic MUST be generated silently at signup and MUST NOT gate the signup flow. "Secure your account" (set a recovery PIN / view backup phrase) MUST be surfaced as a later soft nudge, not a first-run blocker.

### 3.3 Adding a device (existing device retained)

- **R3.5** — A new device MUST generate its own **subordinate device keypair** and display a QR code.
- **R3.6** — An existing device holding the master key MUST authorize the new device by signing a certificate ("this device key is authorized under my identity"), which is sent to the server. The master private key MUST NOT leave the device that holds it (R2.1).
- **R3.7** — Subordinate device keys MUST be independently revocable without rotating the master identity.

**Why.** This is the Signal / WhatsApp-Web linked-device shape: one account, many devices, master key isolated to one piece of hardware, every other device holding only a revocable delegate.

---

## 4. Multi-server & self-host (no federation)

Servers are **fully contained and non-federating**. A self-hosted server never sees, queries, or trusts the main server, and vice versa. The main server never observes data flowing through a self-hosted server.

- **R4.1** — One master identity key MAY be registered on multiple servers simultaneously. Registration on each server is independent and invite-free (R1.1).
- **R4.2** — Adding/using a self-hosted server MUST be a fresh registration with the *same* master identity key — not a migration of the account. A new domain-scoped passkey is generated (R2.6).
- **R4.3** — Because servers do not federate, **only identity is portable across servers; relationships and workspaces are not.** Contacts and workspace membership live on the server where they were established and MUST be re-established on a new server.

**Why.** No federation is a deliberate privacy maximization: total data containment per server. The consequence is that "being connected" is server-local state. The portable key means users never need *new crypto identities* when they self-host — it does **not** mean their social graph travels. Moving conversations is therefore an explicit per-chat operation (§5), not an automatic account property.

### 4.1 Connecting to a server (discovery & trust-on-first-use)

Every user's first-ever connection is to the **main server** (address baked into the app, no entry needed). Connecting to any additional server — e.g. a family's self-hosted instance — is a distinct, later action.

- **R4.4** — A non-main server MUST be identified by the user entering its domain address directly (plain text entry), the same as typing a website address. No in-app provisioning flow creates server infrastructure (§4 is about *connecting to* an already-deployed instance, not standing one up).
- **R4.5** — Before registering an identity on a newly entered domain, the app MUST show a confirmation screen displaying the server's display name (if published) and a short, human-readable fingerprint of its public key/certificate (Signal-safety-number style: grouped digits/words, not raw hex).
- **R4.6** — Registration on a new server MUST require an explicit second confirmation tap after the fingerprint is shown ("Yes, connect") before any registration request fires. This is the point a mistyped or malicious domain is caught, by a human recognizing (or failing to recognize) the displayed name/fingerprint.
- **R4.7** — Once confirmed, the app MUST pin the domain's fingerprint locally (Trust-On-First-Use). Subsequent connections to the same domain MUST proceed silently, without re-prompting.
- **R4.8** — If a previously pinned domain ever returns a **different** fingerprint, the app MUST show a hard, unmissable warning (not a dismissible toast) before proceeding — the same severity as a Signal-style safety-number-changed warning. This is the case the mechanism exists to catch: server re-provisioned maliciously, DNS hijack, or MITM — not the honest first-connect case, which R4.5–R4.6 already cover.

**Why.** This reuses the TOFU-plus-prominent-warning stance already adopted for peer-to-peer first contact (see Key learnings), applied one layer down at server discovery rather than inventing a separate trust mechanism. It costs one confirmation tap per new server, ever, and silent reuse thereafter.

---

## 5. Chat migration between servers

### 5.1 Locality model

- **R5.1** — A chat or group is the unit of locality: it lives on **exactly one server** at a time. There is no live bridge and no chat that exists on two servers at once.
- **R5.2** — A single user MAY simultaneously hold some chats on the main server and others on a self-hosted server, all under one identity. "Partial move" means *some of a user's chats point at server A and others at server B* — it is not a property of the account.
- **R5.3** — Migration is **total cutoff**: export from source, import into destination, one-time. There is no ongoing sync between the two.

### 5.2 Migration flow

Migration executes **on a single device, within the admin's own app session** — the admin controls both the source room and the newly created destination room in the same client, so no key or credential ever crosses a device or session boundary. This is the basis for the flow below: because nothing is handed off to a second party or a later return trip, the entire pipeline can be a single atomic action.

**Trigger.** Admin opens the source room's settings, initiates migration, and fills one form: destination (new or an existing app-known "migration destination" room — selected internally, never via manual key entry), a custom message to members, export options (with/without history), and a deletion policy (§5.4). Admin reviews a confirmation warning that membership will be frozen, and taps **confirm once**.

**Pipeline (runs automatically after the single confirm-tap):**

1. **Provision destination.** App creates the destination room on the destination server (random placeholder name if new), holding no members/metadata yet, and obtains its public key internally — no manual key transcription, since both rooms are in the same app/session.
2. **Freeze & export.** The source room is atomically frozen (§5.5a): no new messages, no membership changes. Member list, roles, metadata, and settings are encrypted to the destination's public key and transferred internally.
3. **Populate destination & generate link.** The destination room decrypts the package, populates its member list, roles, metadata, and settings, and issues a migration credential back to the source (encrypted using a keypair the source room holds — see R5.6a).
4. **Distribute.** The source room posts the admin's custom message plus a **"Migrate to new room"** button (bound to the credential from step 3, never exposed as copyable text) and freezes fully. The migration credential is delivered to each member behind the scenes via the Sealed Sender private-message route.
5. **History (if selected).** If "with history" was chosen, history export/transfer begins as part of the same triggered pipeline, not a separate later action (see §5.3). If interrupted (app closed, device loses power), the transfer MUST resume automatically on next app open rather than requiring the admin to re-trigger it.
6. **Retire source.** Per the deletion policy set at trigger time, the source room's end state (archive or delete-on-condition) is already configured — no separate admin step (§5.4).

**Progress surface.** Because the pipeline takes real time (particularly history export on large rooms), the UI MUST show a progress indicator with short human-readable status per stage (e.g. "Setting up new room…", "Encrypting history…", "Notifying members…"). This is status-only — the admin takes no further action once confirmed.

**Rules**

- **R5.4** — The destination room MUST verify joiners against the pre-seeded member ID set. The security gate is **membership matching**, not link secrecy — the encrypted, unforwardable link is a UX safeguard on top of an already-sound gate.
- **R5.4a** — If the admin removes a member's ID from the destination room after population (step 3) but before that member migrates, the removed member's "Migrate to new room" button MUST resolve to an explicit **"you were removed"** message, not a silent or generic failure.
- **R5.5** — The migration credential MUST NOT be exposed to the user as copyable/forwardable text. The only user-facing action is a "Migrate to new room" button. Migration MUST require an explicit user tap — it MUST NOT silently relocate a user without action.
- **R5.5a** — The freeze in pipeline step 2 MUST be atomic with export: no new messages and no membership changes (add or remove) from that instant forward. The member ID set exported and pre-seeded on the destination (R5.4) is therefore fixed and cannot drift. The admin MUST be certain the current member list is correct before triggering migration — the app does not reconcile membership drift, because none is possible once frozen.
- **R5.6** — A member without an account on the destination server MUST have one created silently (same master key, R1.4 / §3) at the moment they tap "Migrate." The client SHOULD first check whether the member's identity is already registered on the destination and skip registration if so. Regardless, server-side registration MUST be idempotent (upsert on public key, not insert-or-fail): since it is always the same master identity key being published, two near-simultaneous registration attempts for the same member — e.g. from tapping "Migrate" in two overlapping groups migrating to the same destination around the same time — MUST both succeed harmlessly with no ordering dependency.
- **R5.6a** — The source room MUST hold (or generate at trigger time) a keypair whose public half is provided to the destination room during provisioning (pipeline step 1), so the migration credential returned in step 3 is genuinely decryptable by the source — not merely an opaque token. Both legs of the exchange (source→destination export, destination→source credential) MUST be real asymmetric encryption, not one-way-only.
- **R5.6b** — Because the entire pipeline runs on a single device within one app session with no manual key hand-off, a co-admin or second party is NOT required to safely complete migration. Single-admin rooms MAY migrate without appointing a co-admin, since there is no multi-step window with a mid-process admin-absence failure mode: the pipeline is triggered once and either completes autonomously or never starts.
- **R5.6c** — A migration trigger MUST be signed by the **master identity key** (R2.1), not a subordinate device key (R3.5). The server/room MUST reject a trigger signed by a subordinate key. "The master device" is defined dynamically as **whichever device currently holds the master private key**, not one fixed piece of hardware — so after recovery (§3.1) onto new hardware, the newly-recovered device is fully eligible to trigger or resume (R5.7a) a migration, exactly as the original device was.

**Why.** Restricting migration triggers to the master key rather than any authorized device eliminates the subordinate-device-revocation-mid-migration case by construction: only the master key can ever start a migration, and the master key is never independently revocable the way a subordinate device is (R3.7) — it can only be lost and recovered (§3.1), never revoked out from under itself. There is therefore no scenario where "the device that triggered this migration was just revoked," because a revocable device could never have triggered one.

**Why.** Collapsing to one device removes the reason a co-admin mitigation was needed in the first place: earlier drafts required the admin to manually copy a key, wait for provisioning, paste a link, and separately remember to trigger history transfer — each a point a dead or absent admin could strand the process. With everything internal to one confirm-tap, "the admin dies halfway through" is no longer a meaningful failure mode, because there is no halfway a human occupies — provided the one genuinely time-extended piece, history transfer, is made resumable (R5.7a) rather than dependent on a second manual trigger.


### 5.3 History migration

- **R5.7** — "Migrate with history" MUST be performed client-side as **decrypt-then-export**: the source client decrypts messages under the source room's ratchet state, writes them into the export (as plaintext or transit-re-encrypted content), and the destination client re-encrypts them under the new room's session on import.
- **R5.7a** — History export/transfer MUST be triggered as part of the same single-confirm migration pipeline (§5.2 step 5), not deferred to a separate later admin action. If interrupted (app closed, device power loss, network drop), the transfer MUST resume automatically on next app open without requiring the admin to manually re-initiate it.
- **R5.8** — History MUST NOT be moved by copying ciphertext across servers. The source room's Double Ratchet keys do not exist in the destination room, so raw ciphertext would be undecryptable there.

**Why.** Because message content is encrypted under per-room ratchet state, history migration is a client-side re-encryption operation, not a file copy. This must be explicit in the spec so it is never assumed to be a simple transfer.

### 5.4 Source retirement & stragglers

- **R5.9** — The admin MUST choose a retirement policy for the source room from:
  - **Archive** — source room kept indefinitely as read-only on the source server.
  - **Time-based delete** — deleted after a fixed retention period regardless of who has migrated.
  - **User-based delete** — deleted once all known member IDs have joined the destination.
- **R5.10** — User-based delete MUST define a "never joins" outcome to avoid an indefinitely-alive source room held open by one straggler. The RECOMMENDED default is a **hybrid**: user-based, capped by a maximum time.
- **R5.11** — Any delete policy MUST account for the straggler who joins neither: after deletion they lose both the destination room (never joined) and the source archive (deleted). This total-loss outcome MUST be surfaced to the admin when selecting a delete policy.

### 5.5 Deletion mechanics & straggler re-entry (resolved from §7.1)

Because the system mirrors Signal's model — end-to-end encrypted, Sealed Sender, **no chats stored on the server** — deletion is a per-device local purge, not a server-side object destruction. There is no server copy to reconcile.

- **R5.12** — Room deletion MUST execute as a local purge on each member's device, triggered either by a locally-evaluated timer (for members who have received the `migration` event) or by sync-on-reconnect (for members who were offline). The deletion condition MUST travel with the `migration` event so an offline client can evaluate "deadline already passed → purge" the moment it receives it.
- **R5.13** — The migrate credential MUST be distributed like room keys (per-member, via the Sealed Sender private-message route) **and stored as part of the room object**. It MUST NOT be cached, copied, or retained in any store outside the room's storage (no "recent invites" cache, no independent notification payload).
- **R5.14** — Because the "Migrate to new room" button and its credential live inside the room, room deletion MUST remove them by construction. "Room deleted" and "migrate path gone" are therefore the same event — no separate revocation signal and no cross-server coordination are required.
- **R5.15** — A straggler returning after the deletion condition has passed MUST re-enter only by manual admin reinvite. There is no orphaned credential to tap, because it was purged with the room (R5.14).
- **R5.16** — On reinvite, the admin MUST be able to choose whether the returning member receives missed past messages or joins from the current point onward only.

**Why.** Scoping the credential to the room's lifetime means the "must be reinvited" guarantee holds for free: the straggler loses the button because they lost the room that held it. Any store that retains the credential independently would let a returning straggler tap through after deletion and silently re-enter — reintroducing the exact contradiction R5.13 exists to prevent. This is load-bearing, not incidental, which is why it is stated as a rule rather than left as an implementation detail. No federation is needed to enforce it, because nothing crosses the server gap: the source server never signals the destination, and the admin's client is never made a courier.

**Group-3 case (never saw it), resolved.** Straggler comes back online → client syncs → deletion condition already met → room and the button inside it are purged locally → member must be reinvited.

### 5.6 Admin departure & hand-off mid-migration (resolved from §7.2)

- **R5.17** — Room admin roles MUST be included in the metadata copied during the export/populate steps of the pipeline (§5.2 steps 2–3), so the destination room inherits the **same admin set** as the source, including multiple admins where present. There is no separate "destination admin" role to hand off.
- **R5.18** — Temporary admin unavailability (device loss, not permanent departure) is out of scope here — it is covered by recovery in §3. The admin returns as the same identity key; since migration is atomic (R5.6b), there is no partial migration state to resume into — either the pipeline already completed, or it never started.
- **R5.19** — If the room has ≥2 admins, departure of one has no effect on migration: any surviving admin can trigger the pipeline independently. **Note:** as of R5.6b, this is a convenience, not a requirement — single-admin rooms migrate exactly as safely, since the pipeline never has a mid-process state for an admin to abandon.
- **R5.20** — Once migration has been triggered (§5.2), MUST require no further admin action to complete: the pipeline runs autonomously, member self-migration, retirement (§5.4), and local purge (§5.5) are all self-executing per member/device thereafter. A sole admin departing after the trigger does not block completion.
- **R5.21** — Sole-admin departure **before** migration is ever triggered is an unresolved gap: no one is authorized to initiate it. This is unrelated to the flow's atomicity — it is the general case of a room's only admin disappearing before performing *any* admin action, migration included.

**Dependency (not resolved here).** R5.21 is not a migration-specific problem — a sole admin disappearing with no successor blocks *any* room-governance action (renaming, settings, member removal), not just migration. Resolving it requires a general room-governance primitive (e.g., a minimum-admin-count rule or an admin-succession mechanism), which is deferred to its own pass rather than solved inside this blueprint. This blueprint assumes that primitive will exist and does not itself define it.

---

## 6. End-to-end walkthroughs (informative)

These narratives are non-normative; they illustrate the rules above.

**Signup.** A new user opens the app against the main server. The app silently generates a recovery seed and mnemonic, derives the hybrid master identity keypair from it, and wraps the private key under a hardware key (R2.1). It also registers a domain-scoped passkey behind biometrics. Only public keys reach the server. The user is in within seconds — no email, no phone number. A day later a soft nudge offers to set a recovery PIN; accepting escrows the PIN-encrypted mnemonic to the oblivious recovery service.

**Device lost.** On a new phone, the user taps "Restore," enters the recovery PIN, the oblivious service returns the encrypted mnemonic (rate-limited), it decrypts locally, and the app re-derives the master key and wraps it under the new phone's hardware key. A fresh passkey is registered. Without a PIN or written mnemonic, the account is unrecoverable — the stated tradeoff.

**Second device (phone retained).** The laptop generates a subordinate device key and shows a QR code. The phone (holding the master key) scans it, signs an authorization certificate, and sends it to the server. Two devices, one account, master key still isolated to the phone.

**Self-host.** The family stands up its own server. The user taps "Add server," which is a fresh, invite-free registration using the *same* master key — not a migration. A new domain-scoped passkey is generated. The user now holds one identity present on two non-federating servers; moving actual conversations is the separate operation in §5.

**Migrating a group.** An admin fills one migration form (destination, custom message, history option, deletion policy) and taps confirm once. A progress bar walks through the stages while the pipeline runs autonomously: destination provisioned, source frozen and exported, destination populated, migration credential generated and distributed, source fully frozen with the admin's message and a "Migrate to new room" button. Joiners are verified against the frozen member ID set; anyone lacking a destination account gets one silently; a removed member sees an explicit "you were removed" message instead of the button working. History, if selected, transfers as part of the same pipeline and resumes automatically if interrupted. The source is archived or deleted per the policy set at trigger time — no further admin action required at any point after the single tap.

---

## 7. Deferred edge cases (next pass)

To be worked through after this blueprint is accepted:

- ~~Straggler recovery after a delete policy has fired.~~ **Resolved — see §5.5.**
- ~~Admin departure / hand-off mid-migration.~~ **Resolved — see §5.6, further simplified by R5.6b (single-device atomic pipeline removes the co-admin mitigation entirely). Depends on a general room-governance / admin-succession primitive for the sole-admin-never-triggers case (not defined in this blueprint).**
- ~~Concurrent migrations of overlapping groups.~~ **Resolved — folded into R5.6 (idempotent account registration).**
- ~~Member ID set drift between export and destination provisioning (member added/removed in the window).~~ **Resolved — see R5.5a: export freezes the room atomically, so no drift window exists.**
- ~~Revocation of a subordinate device that initiated a migration.~~ **Resolved — see R5.6c: only the master identity key may trigger a migration, so a revocable subordinate device could never have initiated one.**
- ~~Recovery-service outage during PIN-escrow restore.~~ **Resolved — see R3.3a: not a new failure mode, just a temporary instance of the R3.3 tradeoff. No redundancy built for now; "the service comes back eventually."**
- Full account-creation and new-chatroom-creation walkthrough from the app — both first-ever use, and specifically creating a "family" server.
- ~~Whether a libsignal Identity Key is sufficient as the §2 master identity key, or needs augmenting.~~ **Resolved — see R2.1a/R2.4a: hybrid classical+ML-DSA dual signing for the master identity key. Message confidentiality separately addressed by adopting Triple Ratchet from v1.**
