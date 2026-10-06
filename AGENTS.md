# DaChat — Agent Guide

A privacy- and security-focused chat app (Flutter; Android · iOS · Linux).
This file is tool-neutral: Claude Code (via `CLAUDE.md`), OpenCode, and Hermes Agent all read it.

## Read first — authority order

1. **`references/flutter_constitution.md`** — read in full before any plan, code, or test.
   Every MUST is a hard rule; it wins over everything else, including this file.
2. **`references/RQSM_Blueprint.md`** — cryptography, transports, security rules (libsignal, PQXDH).
3. **`references/FlowChat_Privacy_MentalHealth_Blueprint.md`** — privacy and mental-health feature rules.
4. **`references/Future_Features_Roadmap.md`** — scope deliberately deferred from the MVP.

If anything here disagrees with the constitution, the constitution is right — fix this file.

## Stack at a glance

- Architecture: Feature-First Clean Architecture + DDD (`lib/features/<feature>/{data,domain,presentation}`)
- State: `flutter_bloc` — Cubit by default, thin Cubits that call use cases; no state-management codegen
- DI: `get_it` + `injectable` (single container) · Errors: `fpdart` `Result<T>` · Events: `event_bus`
- Crypto: vendored `libsignal-client` via `flutter_rust_bridge` — never reimplement protocols
- Only packages on the constitution's approved list; anything else needs plan justification

## Commands

```sh
dart analyze                                              # must be zero issues
flutter test --coverage                                   # domain+data ≥ 80%; core/crypto+security ≥ 95%
dart run build_runner build --delete-conflicting-outputs  # after freezed / injectable / event / asset changes
dart doc . 2>&1 | grep -i warning                         # must print nothing
```

## Workflow

- Specs, plans, and tasks use Spec Kit (`/speckit-*`); features live under `specs/`.
- BDD first: Gherkin `.feature` files are written during planning and accepted before implementation.
- One intent per commit. Never edit generated files (`*.g.dart`, `*.freezed.dart`, `docs/events/*.md`).

## Never

- Log PII, plaintext, key material, session references, or transport metadata — at any level.
- Weaken crypto config in `dev`/`staging`, or put key material in `freezed` classes, DTOs, or Cubit state.
- Ship a third-party telemetry or analytics SDK.
