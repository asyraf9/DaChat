# Quickstart & Validation Guide: Secure Direct Messaging

**Feature**: `001-secure-direct-messaging` · **Plan**: [plan.md](./plan.md)

This guide shows how to build the app and the main-server stack locally, and how to prove each user
story and success criterion end to end. It doesn't include implementation. Formats and endpoints are
in [contracts/](./contracts/), and entities and states are in [data-model.md](./data-model.md).

## 1. Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Flutter / Dart | 3.47.x / 3.13.x | Installed. `flutter doctor` must be clean for Android and Linux, and for iOS on macOS. |
| Rust | Stable, pinned by `native/rust-toolchain.toml` | **Not yet installed on this machine.** Install `rustup`, then the targets `aarch64-linux-android armv7-linux-androideabi x86_64-linux-android aarch64-apple-ios aarch64-apple-ios-sim x86_64-unknown-linux-gnu`. |
| `flutter_rust_bridge_codegen` | Matches the `flutter_rust_bridge` pub version | `cargo install flutter_rust_bridge_codegen --version <pinned>`. |
| `cargo-llvm-cov` | latest | Native coverage gate (R21). |
| Build dependencies for libsignal and SQLCipher | — | `protoc`, `cmake`, `clang`, `perl` (the vendored OpenSSL build). Android NDK r27+. |
| Docker or Podman with Compose | — | Both are available here. Used for the server stack. |
| Android device or emulator (API 29+), iOS device (iOS 16+), Linux desktop | — | Two devices are needed for the end-to-end stories. A Linux desktop plus an Android emulator is enough for everything except iOS push. |

## 2. One-time setup

```sh
git submodule update --init native/third_party/libsignal
native/tool/verify_libsignal_pin.sh            # recomputes the tree digest vs libsignal.lock; must print OK
cp .env.example .env.dev                       # main-server host + SPKI pins for the local stack
flutter pub get
flutter_rust_bridge_codegen generate           # regenerates lib/core/crypto/bridge/ (generated, never edited)
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

## 3. Start the main-server stack (local / staging-like)

```sh
cd server
docker compose up -d                           # prosody, dachat-keyservice, postgres, static /c/* page
docker compose exec keyservice dachat-keyservice self-check   # prints the TLS SPKI pin for .env.dev
```

Expected: `self-check` reports `prosody: ok`, `db: ok`, `mam: disabled`, `inband_register: disabled`,
and `offline_ttl: 30d`.

## 4. Fast checks (run before every commit)

```sh
dart analyze                                   # zero issues
dart doc . 2>&1 | grep -i warning              # no output
flutter test --coverage                        # unit + widget; runs .feature scenarios via test/runners/
tool/coverage_gate.sh                          # domain+data ≥ 80%; lib/core/crypto + lib/core/security ≥ 95% line+branch
(cd native && cargo test && cargo llvm-cov --fail-under-lines 95 --fail-under-branches 95)
(cd server/keyservice && cargo test)
tool/check_packages.sh                         # pubspec diff ⊆ approved list + RQSM justification table
```

## 5. Run the app

```sh
flutter run --flavor dev -t lib/main_dev.dart -d linux
flutter run --flavor dev -t lib/main_dev.dart -d <android-emulator-id>
```

## 6. End-to-end validation scenarios

Integration tests run with:

```sh
flutter test integration_test --flavor staging -d <device>
```

Each one traces to a `.feature` scenario in `test/features/*/specs/`. Manual steps below cover what
needs two physical devices or human judgment.

| # | Proves | How | Expected outcome |
|---|---|---|---|
| V1 | US1, FR-001/005, SC-009 | Fresh install, then "Get started". | No identifier, invite, or phrase prompt. Privacy explainer shown. Conversation list in under 10 s. |
| V2 | US1-4, FR-008, SC-001, SC-007 | Two devices: mutual QR scan, then a message each way. Time it. | Both show the other as **verified** with display names. First message exchanged in under 3 min from first launch. QR step under 1 min. |
| V3 | US1-6/7/8, FR-019–021, SC-003/004 | Put device B in airplane mode, send 3 messages from A, reconnect B. Then kill A's network mid-send. | A shows `sent`, then `delivered`, in order, within 30 s of reconnect. Offline sends show `pending`, then send automatically. A forced-refusal build shows `failed` with Retry. |
| V4 | **SC-002**, FR-018/021/045 | Run `server/tools/inspect_server_data.sh` after V2–V3 and after V7. | Dumps PostgreSQL, the Prosody stores, and the logs. Then `inspect_server_data.sh --grep-plaintext <all display names and message texts used>` returns **zero hits**. Backups appear only as padded blobs. No offline rows remain after delivery. |
| V5 | US2-1..5, FR-009–013, SC-005 | Create a link with ID confirmation off and redeem it on B. Re-open the same link. Create a link with a code word, enter 3 wrong words, then make a new link and enter the right word. Revoke one link and let another expire (staging clock). | Not verified, then refused ("already used"), then exhausted with no contact, then **verified**. Revoked and expired links are refused with explanations. `tool/race_redeem.sh` (50 parallel redeems) gives exactly 1 success. |
| V6 | US2-6..8, FR-014–016, SC-006 | Compare safety codes, then scan the safety QR. Use `server/tools/inject_bundle_mismatch.sh <addr>` to serve a different identity. Simulate a user-confirmed replacement. | Contact becomes verified. Then a **blocking warning**, with the composer disabled and held messages not sent until acknowledged. A not-verified contact gets a notice only. |
| V7 | US3, FR-025–031, FR-045, SC-008 | Connect A with B (QR) and C (link), block D. Record A's phrase. "Remove from this device" on A, reinstall, then Restore. Separately, restore on a second device while the original is offline, then bring the original online. Kill the app mid-restore and mid-removal. | Same identity. Contacts, trust, and block return. B and C see no warning and messaging resumes. History absent, as disclosed. The original device explains and wipes. Interrupted operations complete or roll back on next launch. |
| V8 | US4, FR-033–038, SC-010 | A blocks B. B sends messages and tries a new link and a QR. Check A↔C. Then unblock. | Nothing from B is shown or notified on A. B sees `sent`, never `delivered`, with no blocked indication. A↔C unaffected. After unblock, only new messages arrive. |
| V9 | **SC-011**, FR-040 | Run `tool/egress_capture.sh` (mitmproxy-free pcap plus DNS log) over V1–V8 on Android and Linux. | Only main-server hosts (plus `api.push.apple.com` on iOS). No content, analytics, or crash telemetry. |
| V10 | FR-041 | Run `tool/log_scan.sh` over the captured app logs and server logs with the V4 term list, plus key, address, and phrase patterns. | Zero hits. |
| V11 | FR-039, FR-042–044, SC-012 | Screenshot attempt on the QR, safety, phrase, and restore screens. TalkBack and VoiceOver walkthrough of every route in [contracts/ui-routes.md](./contracts/ui-routes.md), in light and dark themes. | Screenshot blocked (Android) or content hidden (iOS). Linux disclosure shown. Every control announced. Both themes correct. |

## 7. Acceptance gate for implementation start

Implementation (`/speckit-tasks` → `/speckit-implement`) begins only after both of these are
accepted:

1. this plan, including the **⚑ Review** decisions in research.md (R11 identity change in particular);
2. the `.feature` files under `test/features/*/specs/` (constitution BDD rule).
