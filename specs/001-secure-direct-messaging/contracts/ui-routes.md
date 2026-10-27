# Contract: Screens, Routes & UI Obligations (v1)

All routes are named and defined in `lib/core/router/app_router.dart`.

The `GoRouter.redirect` guard reads `AppSessionCubit`:

- `none` goes to `/welcome`;
- `pendingRegistration` or `active` goes to the app;
- `superseded` goes to `/device-replaced`;
- `restoring` goes to `/restore`.

**Protected** routes set `FLAG_SECURE` on Android and the snapshot blur on iOS (FR-039, R14), and
show the Linux disclosure.

Every screen follows these rules:

- it is split into an `XPage` and an `XView`;
- every string comes from `AppLocalizations` (FR-042);
- it uses theme colours only, in light and dark (FR-043);
- every control has `Semantics` (FR-044);
- it has widget tests for every state variant.

| Route name | Path | Screen (feature) | Cubit/Bloc | Protected | Spec |
|---|---|---|---|---|---|
| `welcome` | `/welcome` | Welcome: "Get started" / "Restore" (identity) | `OnboardingCubit` | | US1-1, US3-4 |
| `privacyExplainer` | `/welcome/privacy` | What the server can and cannot see, key-protection level, push disclosure on iOS (identity) | `OnboardingCubit` | | FR-005, FR-003, FR-024 |
| `setDisplayName` | `/welcome/name` | Set display name (identity) | `DisplayNameCubit` | | FR-006 |
| `restore` | `/restore` | Enter phrase, per-word validation, history-not-restored statement (identity) | `RestoreBloc` (security-critical) | ✓ | US3-4/5, FR-028 |
| `conversations` | `/` | Conversation list, "Secure your account" nudge banner, offline-setup banner (messaging) | `ConversationListCubit` | | R19, R20 |
| `chat` | `/chat/:conversationId` | Conversation: timeline, delivery states, composer, identity-change warning/notice, blocked state with unblock (messaging) | `ChatCubit` + `ContactTrustBloc` | | US1-5..8, US2-7/8, US4-2 |
| `connect` | `/connect` | Choose QR (suggested first) or link (connections) | `ConnectCubit` | | FR-011 |
| `showQr` | `/connect/qr` | My QR, plus "Scan theirs" (connections) | `QrPairingCubit` | ✓ | US1-4 |
| `scanQr` | `/connect/scan` | Camera scanner, unavailable on Linux (connections) | `QrPairingCubit` | ✓ | US1-4 |
| `createLink` | `/connect/link/new` | Explicit yes/no for ID confirmation (unless a default is saved), code-word entry, share sheet, single-use and 24 h notice (connections) | `CreateLinkCubit` | | US2-1/2 |
| `myLinks` | `/connect/links` | Active links with expiry and revoke (connections) | `LinkListCubit` | | US2-2 |
| `openLink` | `/c/:linkId` (deep link) | Incoming link: who, rules, "Confirm", code-word entry, expired/used/revoked explanations (connections) | `RedeemLinkBloc` | | US2-3/4/5 |
| `contact` | `/contact/:contactId` | Contact details: trust state, how connected, block/unblock (contacts) | `ContactDetailCubit` | | FR-033 |
| `safetyCode` | `/contact/:contactId/safety` | 60-digit code, scan theirs / show mine, match/mismatch explanation (contacts) | `ContactTrustBloc` | ✓ | US2-6 |
| `settings` | `/settings` | Display name, blocked list, reminders, background connection (Android), privacy disclosure, remove from device (settings) | `SettingsCubit` | | |
| `blockedList` | `/settings/blocked` | Blocked contacts with unblock (contacts) | `BlockedListCubit` | | US4-6 |
| `recoveryPhrase` | `/settings/recovery` | View the 24 words, then a 3-word confirmation (identity) | `RecoveryPhraseCubit` | ✓ | US3-2/3 |
| `removeDevice` | `/settings/remove` | Warning plus a typed confirmation word (identity) | `RemoveDeviceBloc` (security-critical) | | US3-7, FR-030 |
| `deviceReplaced` | `/device-replaced` | "Your identity is now active on another device", then wipe (identity) | `AppSessionCubit` | | US3-6 |

## Interaction obligations (tested)

- **Identity-change warning** (verified contact): a non-dismissible banner in `chat`. The composer is
  disabled until the user taps **"I understand"**, which acknowledges the change (FR-015). Held
  messages are released after acknowledgement.
- **Identity-change notice** (not-verified contact): a timeline system item. Messaging is not blocked
  (FR-016).
- **Delivery states**: every outgoing message shows `pending`, `sent`, `delivered`, or `failed` as an
  icon plus a semantic label. `failed` offers **Retry**.
- **Blocked conversation**: history stays readable, the composer is replaced by
  **"You blocked <name>. Unblock"** (US4-2).
- **Remove from device**: the user must type the localised word shown on screen (for example,
  `REMOVE`) before the destructive button is enabled.
- **Screen reader**: each screen passes a TalkBack and VoiceOver walkthrough (SC-012). QR screens
  expose a text alternative ("Show my code as a link instead") for users who can't use a camera.
- **Notifications**: the title is "DaChat" and the body is "New message from <display name>". There
  is never any message content (FR-023).
