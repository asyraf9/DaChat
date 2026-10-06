<!--
  Flutter Constitution — Change Log
  ==================================
  | Version      | Change                                                      |
  |--------------|-------------------------------------------------------------|
  | 1.1.0        | Initial release                                             |
  | 1.2.0        | Added: core/ rules, Failure hierarchy, EventBus, DI wiring, |
  |              | Retrofit placement, flavours, CI gate, coverage threshold,  |
  |              | l10n toolchain, flutter_gen, pubspec hygiene, §XII, App. A |
  | 1.3.0        | Added: Domain Event Registry, dartdoc tag convention,       |
  |              | generate_event_registry.dart, build.yaml wiring             |
  | 1.3.1        | Added: Full dartdoc convention (§QUALITY), dart doc CI gate |
  | 1.3.1-lean   | Restructured for agent scannability. Rules first, rationale |
  |              | and examples moved to appendices. No rule changes.          |
  | 1.4.0        | C1: freezed carve-out for key-material classes              |
  |              | C2: storage tier distinction (secure storage vs hardware)   |
  |              | C3: failure field safety rule                               |
  |              | C4: EventBus security-critical event guidance               |
  |              | C5: extended AppLogger blocklist                            |
  |              | C6: crypto configuration flavour parity                     |
  |              | C7: Isolates mandate extended to crypto operations          |
  |              | C8: Cryptography row in approved package stack              |
  |              | C9: DTO safety rule for cryptographic classes               |
  |              | C10: event registry scanner security filter                 |
  |              | C11: test fixture safety for crypto vectors                 |
  | 1.4.0-lean   | Maintained agent-optimized structure. No rule changes from  |
  |              | 1.4.0.                                                      |
  | 1.4.1-lean   | C12: crash/analytics privacy carve-out. C13: coverage bar   |
  |              | for core/crypto + core/security. C14: sessionRef log rule   |
  |              | (resolves C5 vs Appendix B). C15: third storage tier        |
  |              | (hardware-derived ephemeral). C16: EventBus infra dispatch. |
  |              | C17: crypto-isolate/store seam. Extended C10 scanner terms. |
  |              | Corrected secure-element language.                          |
  | 1.4.2-lean   | C18: reuse-vetted-crypto-first — prefer an audited protocol |
  |              | implementation (e.g. libsignal) over reimplementing session,|
  |              | ratchet, or group cryptography. Cryptography row + anti-    |
  |              | pattern updated.                                            |

  Decisions on record:
  - Storage:    isar only (hive removed)
  - State:      NotifierProvider for all state (StateProvider removed)
  - Flavours:   dev / staging / prod, per-flavour .env files
  - Events:     get_it singleton EventBus (event_bus package)
  - BDD timing: .feature files authored during planning, accepted with plan
  - Coverage:   ≥ 80% line coverage, domain + data layers only
  - l10n:       flutter_localizations + intl (.arb, gen-l10n)
  - Assets:     flutter_gen (type-safe code-gen accessors)
  - Crypto:     long-term wrapping key never leaves the hardware secure
                element; derived and per-message keys are ephemeral in the
                Dart heap and never persisted (they cannot be kept out of
                memory in a Dart app); flutter_secure_storage is NOT a
                hardware-key mechanism
  - freezed:    excluded from classes holding raw key material
  - Crypto CI:  cryptographic config identical across all flavours
-->

# Flutter Constitution · v1.4.2-lean

> **Agent instruction**: Read this file in full before producing any plan,
> code, or test. Every MUST is a hard rule. Every MUST NOT is an absolute
> prohibition. Violations require refactoring — never a workaround.
> When in doubt, check [Appendix A: Anti-Patterns](#appendix-a-anti-patterns)
> and [Appendix B: Reference Examples](#appendix-b-reference-examples).

---

## LANG — Language & Dart

- UI MUST be declarative. Compose widgets; never inherit from them.
- Sound null safety is required throughout. No `dynamic` without a justification
  comment. No `!` (bang) without a comment explaining why null is impossible.
- Use `async`/`await` for all async operations. Use `Isolate`s for heavy
  computation and for cryptographic operations involving key derivation or
  sensitive data encryption — never block the UI thread, and never hold
  sensitive key material in the main thread heap longer than necessary.
  **Store seam [C17]:** any encrypted store keyed by hardware-derived key
  material (e.g. a ratchet or history database) MUST be opened and accessed
  **inside the same crypto Isolate**, so the derived store key and the key
  material it protects never cross an Isolate boundary as bytes and never
  appear on the main heap. This is how the "crypto runs in an Isolate" mandate
  and the "key material never crosses Isolate boundaries" example are satisfied
  simultaneously.
- Use `freezed` for all data classes, union types, and sealed classes.
  **Security exception [C1]**: classes holding raw key material (private keys,
  shared secrets, ratchet chain or message keys) MUST NOT use `freezed`.
  Implement `toString()` manually returning `'[SecuritySensitive — contents withheld]'`.
  Equality MUST NOT compare key bytes — use an opaque ID field only.
- Use `fpdart` `Either<Failure, T>` (aliased `Result<T>`) as the return type for
  all repository methods and use cases. Never throw exceptions across layer
  boundaries.
- Use `extension` methods to add helpers to classes — never subclass to extend.
- Use `ThemeData` / `ColorScheme` for all colours and text styles — no hardcoded
  colour literals.
- Support light and dark mode from day one.
- Add `Semantics` widgets to all interactive elements.
- Wrap every user-facing string in `AppLocalizations` from the start.
  See [L10N](#l10n--localisation) for toolchain rules.

---

## ARCH — Architecture

**Pattern**: Feature-First Clean Architecture (FFCA) + Domain-Driven Design (DDD).
Every feature is a bounded context with three layers: `data/`, `domain/`,
`presentation/`. The domain layer is the source of truth for business meaning.

### Layer Rules

- `domain/` MUST be pure Dart — zero Flutter or third-party framework imports.
- UI code MUST only reach the domain through use cases or Riverpod providers.
- DTOs (`data/models/`) MUST NOT leak into `domain/` or `presentation/`.
  Map them to domain entities at the repository boundary.
- DTOs MUST NOT represent or contain raw cryptographic material. No
  `toJson()`/`fromJson()` on key material, ratchet state, or security-sensitive
  byte sequences. **[C9]**
- Repository contracts (interfaces) live in `domain/repositories/`;
  implementations in `data/repositories/`.
- One use case per file. One responsibility per use case.
- Cross-feature communication MUST use domain events via `EventBus` or shared
  contracts — never direct imports of another feature's internal classes.

### DDD Rules

- **Ubiquitous Language**: domain class/method/variable names MUST reflect
  agreed business vocabulary. No technical jargon in domain names.
- **Bounded Contexts**: each `features/<name>/` directory is one bounded context.
- **Entities**: have identity and lifecycle — carry an identity field, modelled
  as `freezed` classes.
- **Value Objects**: immutable, compared by value, no identity field.
- **Aggregates**: one aggregate root per aggregate. All external code modifies
  the aggregate through the root only. Cross-aggregate references use IDs.
- **Domain Services**: stateless operations that don't belong to an entity.
  Live in `domain/services/`. MUST NOT hold state.
- **Use Cases**: orchestrate domain objects and repositories for one application
  intent. One per file.
- **Domain Events**: every significant state change MUST be expressed as an
  immutable `freezed` event in `domain/events/` and dispatched via `EventBus`.

### Event Bus Rules

- One `EventBus` instance, registered as a `get_it` singleton in
  `core/di/event_bus_module.dart` before any feature module initialises.
- Dispatch: `getIt<EventBus>().fire(event)` from a use case, domain service, or
  infrastructure service registered in `get_it` (e.g. a transport switcher in
  `data/`) — never from presentation code. **[C16]** The rule's intent is to
  keep dispatch out of the UI, not to bar the data layer; an infrastructure
  service that owns the state change may dispatch it.
- Consume: `getIt<EventBus>().on<SomeEvent>().listen(...)` in a `Notifier` /
  `AsyncNotifier` or a domain service. Subscriptions MUST be cancelled on dispose.
- Event fields MUST be value types or entity IDs — no mutable objects.
- Security-critical events (auth state, crypto session state, key errors) MUST
  list an explicit `@consumers` allowlist in their dartdoc. Adding a new
  consumer requires a security review, not only code review. **[C4]**

### Domain Event Registry Rules

Every domain event class MUST carry all five structured dartdoc tags.
Missing tags are a Constitution violation caught at code review.

| Tag | Value |
|---|---|
| `@event` | Bare marker (required for scanner) |
| `@dispatcher` | Use case or service that fires this event |
| `@consumers` | Comma-separated consumers (notifiers, services, use cases) |
| `@payload` | Significant fields and their types |
| `@since` | Semver or date introduced (e.g. `0.1.0`) |

- Description prose MUST appear before the first `@tag` line, in ubiquitous
  language.
- `tool/generate_event_registry.dart` scans `lib/features/*/domain/events/`
  and writes `docs/events/<feature>.md` on every `build_runner` run.
- `docs/events/*.md` MUST be committed. MUST NOT be edited manually.
- Update tags in the same PR as any dispatcher or consumer change.
- The scanner MUST emit a build warning if any `@payload` field name matches a
  security-sensitive term: `key`, `secret`, `password`, `token`, `hash`,
  `ratchet`, `cipher`, `plaintext`, `session`, `peer`, `fingerprint`, `nonce`.
  Any match MUST be reviewed and documented before the PR is merged. **[C10]**
  Note the deliberate tension with **[C14]**: an opaque `sessionRef` field is
  permitted in an event payload but flagged here so a reviewer confirms it is
  opaque and never reaches a logger.

### `core/` Directory Rules

`core/` holds code shared across two or more features. Canonical subdirectories:

| Directory | Contents |
|---|---|
| `core/di/` | `get_it` modules, `injectable` setup, `EventBus` module |
| `core/error/` | `AppFailure` base, standard subtypes, `Result<T>` typedef |
| `core/network/` | `Dio` factory, interceptors, `retrofit` base config |
| `core/router/` | `app_router.dart` — central `GoRouter` definition |
| `core/theme/` | `ThemeData`, `ColorScheme`, text styles |
| `core/constants/` | App-wide constants |
| `core/extensions/` | Shared `extension` methods |
| `core/utils/` | Stateless utility functions |
| `core/l10n/` | `AppLocalizations` delegate config |

No new `core/` subdirectory without rationale in the plan's Complexity table.

### Failure Hierarchy

All failures extend `AppFailure` (sealed class, `lib/core/error/app_failure.dart`).

| Subtype | Trigger |
|---|---|
| `NetworkFailure` | HTTP errors, timeouts, no connectivity |
| `CacheFailure` | Isar read/write errors, missing cached data |
| `ValidationFailure` | Input validation errors |
| `AuthFailure` | 401 / 403 responses |
| `UnexpectedFailure` | Catch-all for unhandled exceptions |

Feature-specific subtypes (e.g. `PaymentDeclinedFailure`) MAY live in the
feature's `domain/` layer but MUST still extend `AppFailure`.

Failure message fields MUST carry only opaque error codes and generic safe
strings. No raw data, entity IDs, key material, or user content in any
failure field. Failure objects pass through logging pipelines — treat every
field as potentially visible. **[C3]**

### Data Layer: Retrofit & Dio

- Retrofit interfaces live in `data/datasources/remote/`, named
  `<Feature>RemoteDataSource`.
- `Dio` MUST be instantiated once in `core/network/` and registered with
  `get_it`. Never instantiate `Dio` inside a feature.
- `DioException` MUST be caught and mapped to an `AppFailure` subtype at the
  repository boundary. It MUST NOT propagate past `data/repositories/`.

### Dependency Injection Rules

- All `get_it` registrations MUST use `injectable` annotations.
- Each feature provides a `@module`-annotated class in `data/di/<feature>_module.dart`.
- `configureDependencies()` in `core/di/injection.dart` aggregates all modules
  and MUST be awaited before `runApp()`.
- **Boundary rule**: `get_it` owns infrastructure (repositories, data sources,
  services, `Dio`, `EventBus`). Riverpod owns UI-facing reactive state.
  Providers resolve `get_it` dependencies at the provider boundary.
  No duplication between the two containers.

### Directory Tree

```
lib/
├── core/
│   ├── di/            # get_it modules, EventBus
│   ├── error/         # AppFailure, standard subtypes, Result<T>
│   ├── network/       # Dio factory, interceptors
│   ├── router/        # app_router.dart
│   ├── theme/
│   ├── constants/
│   ├── extensions/
│   ├── utils/
│   └── l10n/
├── features/
│   └── <feature>/
│       ├── data/
│       │   ├── datasources/
│       │   │   ├── remote/    # <Feature>RemoteDataSource (Retrofit)
│       │   │   └── local/     # <Feature>LocalDataSource (Isar)
│       │   ├── models/        # DTOs only — no crypto-material classes
│       │   ├── repositories/  # Repository implementations
│       │   └── di/            # Feature @module
│       ├── domain/            # Pure Dart — no Flutter imports
│       │   ├── entities/
│       │   ├── value_objects/
│       │   ├── aggregates/
│       │   ├── events/        # Immutable freezed domain events
│       │   ├── repositories/  # Interfaces only
│       │   ├── services/      # Stateless domain services
│       │   └── usecases/
│       └── presentation/
│           ├── pages/
│           ├── widgets/
│           └── providers/     # Top-level Riverpod declarations only
├── l10n/              # *.arb translation files
└── main.dart

docs/
└── events/            # Auto-generated — do not edit manually
    └── <feature>.md

tool/
└── generate_event_registry.dart
```

---

## STATE — State Management

- **Only Riverpod** (`riverpod` + `flutter_hooks` + `riverpod_generator`).
  No `Provider`, `GetX`, or `BLoC`.
- Use `AsyncNotifierProvider` for async data.
- Use `NotifierProvider` for all synchronous mutable state, including simple
  toggles. `StateProvider` is not approved.
- Use `@riverpod` annotations (`riverpod_generator`) for all providers.
- Providers MUST be top-level declarations in `presentation/providers/` files —
  never nested inside widget classes.
- Handle loading, data, and error branches for every `AsyncValue`. Never ignore
  the error branch.

---

## NAV — Navigation

- All routes defined in `lib/core/router/app_router.dart`.
- Named routes only — no string literals in navigation calls.
- Auth guards via `GoRouter.redirect`.
- Pass data via route parameters or `extra` — never via global state.

---

## TEST — Testing

**Principle**: test-first, behaviour-driven, three layers.

### BDD Workflow

1. During planning, author Gherkin `.feature` files in
   `test/features/<feature>/specs/`. Submit with the plan. Implementation
   MUST NOT begin until both plan and `.feature` files are accepted.
2. Write step definitions in `test/features/<feature>/steps/` before or
   alongside test code — never after.
3. Steps used by two or more features MUST live in `test/shared/common_steps/`.

### Layer Assignment

| Scenario scope | Layer |
|---|---|
| Single use case, entity, or value object | Unit |
| Single screen or widget interaction | Widget |
| End-to-end user journey | Integration |

### Unit Tests

Cover: all use cases, all repository implementations (DTO mapping +
error-to-`Failure` conversion), all domain entities/value objects with logic,
all domain services. Use `mocktail` — no real network or database calls.

### Widget Tests

Cover: all custom widgets, all screens (minimum: renders, key interactions).
Use `pumpWidget` with `ProviderScope` overrides. Verify loading/data/error
states.

### Integration Tests

Cover: all critical user flows. Run on staging flavour or fully stubbed backend.
Each test MUST trace back to a `.feature` scenario.

### Coverage Gate

- Domain and data layers: ≥ 80% line coverage. Measured by
  `flutter test --coverage`.
- **Security-critical code — `core/crypto/` and `core/security/` — MUST meet a
  higher bar: ≥ 95% line AND branch coverage, plus known-answer test vectors
  for every primitive. [C13]** These directories live under `core/` and would
  otherwise fall outside the domain/data gate; they are the highest-risk code in
  the project and are explicitly in-scope at this raised bar. A PR reducing their
  coverage below the bar MUST NOT be merged.
- Presentation layer: excluded from numeric gate but every screen needs a
  widget test.
- PRs reducing domain/data coverage below 80% MUST NOT be merged.

### Test Fixture Safety

- Fixtures and crypto known-answer vectors MUST use clearly synthetic key
  material (e.g. all-zero or sequential bytes). **[C11]**
- Every fixture key value MUST carry a `// TEST ONLY — never use in production`
  comment on the same line as the declaration.

### Test Directory Structure

```
test/
├── features/
│   └── <feature>/
│       ├── unit/
│       ├── widget/
│       ├── integration/
│       ├── specs/        # Gherkin .feature files
│       └── steps/        # Feature-local step definitions
├── shared/
│   ├── common_steps/     # Steps used by 2+ features
│   ├── support/          # Fakes, mocks, ProviderScope helpers
│   └── fixtures/         # Test data — synthetic key material only
└── runners/              # Thin BDD test runners
```

---

## CI — CI Gate (non-negotiable)

Run `dart analyze` and `flutter test --coverage` locally before every commit.
All of the following MUST also pass in CI before any PR is merged:

- `dart analyze` → zero issues
- `dart doc . 2>&1 | grep -i warning` → no output
- `flutter test --coverage` → ≥ 80% line coverage on domain + data layers
- All three test layers pass (unit, widget, integration)
- No unapproved packages in `pubspec.yaml` diff

---

## L10N — Localisation

- Toolchain: `flutter_localizations` + `intl`.
- Translation files: `lib/l10n/app_<locale>.arb` (e.g. `app_en.arb`).
- Enable: `flutter.generate: true` in `pubspec.yaml`.
- Generate: `flutter gen-l10n`.
- Access: `AppLocalizations.of(context)!` — never raw string literals in
  widget code.

---

## UI — User Interface

These rules govern Flutter UI mechanics. Visual design decisions (colours,
spacing scale, typography, component appearance) MUST be defined in a
project-level `DESIGN.md` and are not governed here.

- All text styles MUST come from `Theme.of(context).textTheme` — no inline
  `TextStyle` definitions in widget code.
- All colours MUST come from `Theme.of(context).colorScheme` — no hardcoded
  colour literals anywhere (reinforces LANG).
- All spacing and sizing MUST reference named constants from `core/constants/`
  (e.g. `AppSpacing.md`) — no raw `double` literals in layout widgets.
- Layouts MUST use `LayoutBuilder` or `MediaQuery` to adapt to screen size —
  no hardcoded pixel widths or heights.
- All interactive widgets and images MUST have a `Semantics` label (reinforces
  LANG). Non-decorative images MUST set `excludeFromSemantics: false` and
  provide a meaningful label.
- Never use `setState` in a widget that could be a `ConsumerWidget`. If state
  is shared or outlives the widget, it belongs in a provider.
- `const` constructors MUST be used on all widgets where possible — the linter
  enforces this but agents must not suppress the warning.
- Avoid deep widget nesting — extract sub-trees into named widget classes when
  nesting exceeds 4–5 levels. Prefer `Sliver` widgets for complex scrolling
  layouts over nested `ListView`s.

> If the project has a design system, create `DESIGN.md` at the project root
> and reference it in the feature plan for any task introducing new UI
> components. Agents MUST read `DESIGN.md` during planning for those features.

---

## SECURITY — Security

- No hardcoded secrets, API keys, or tokens anywhere in source.
- Flavours: `dev`, `staging`, `prod`. Each loads a matching `.env` file
  (`.env.dev`, `.env.staging`, `.env.prod`) via `flutter_dotenv` at startup.
- All three `.env` files MUST be in `.gitignore`. Commit `.env.example` with
  placeholders only.
- Cryptographic configuration, key derivation paths, and encryption settings
  MUST be identical across all flavours. Only feature availability may differ.
  No test keys, disabled encryption, or skipped validation in `dev` or
  `staging` builds. **[C6]**
- **Three storage tiers — use the appropriate one [C2]:**
  - `flutter_secure_storage` — credentials and tokens. Bytes are decrypted and
    surface in the Dart heap on retrieval. Not suitable for key material that
    must never leave hardware.
  - Platform-channel hardware keystore (Android Keystore / iOS Secure Enclave),
    non-exportable key — for a long-term wrapping key requiring hardware-only
    protection. The key never leaves the secure element; only crypto operations
    are exposed to Dart code.
  - **Hardware-*derived* ephemeral key [C15]** — a store/session key derived per
    session from the hardware-resident wrapping key, used briefly in the Dart
    heap (ideally inside a crypto Isolate) to open an encrypted store, then
    dropped. It is **never persisted**. This is the honest tier for at-rest
    stores like a ratchet or history database: the wrapping key stays in
    hardware, but the derived key necessarily exists as bytes in memory while a
    Dart library uses it. Do not describe such a key as "never leaving the
    secure element" — only the wrapping key qualifies.
  - On platforms without a secure element (e.g. desktop Linux), substitute the
    OS keyring (Secret Service) or a passphrase-derived KEK via a memory-hard
    KDF, and disclose the weaker guarantee.
- Follow OWASP Mobile Top 10.
- Validate all user input before sending to the backend.
- Never log PII, tokens, or passwords at any level.
- Never expose stack traces or internal detail in production error messages.

---

## QUALITY — Code Quality

- Zero `very_good_analysis` lint warnings at merge.
- All public APIs have dartdoc comments. See dartdoc rules below.
- `lowerCamelCase` for variables/methods, `UpperCamelCase` for types.
- No magic numbers or hardcoded strings — use `core/constants/` or l10n keys.
- Max function length: 40 lines.

### Dartdoc Rules

- **Line 1**: single-sentence summary ending with `.` — this is the tooltip.
- **Elaboration**: blank `///` line, then prose covering contract, caveats,
  related types, side effects.
- **Cross-references**: use `[ClassName]` / `[ClassName.member]` syntax.
  Never raw quoted strings for type names.
- **Parameters/returns/errors**: document inline in prose using `[references]`.
  Do NOT use `@param`, `@return`, or `@throws` tags.
- **`freezed` classes**: document the abstract class and its fields only.
  Never document generated files.
- **Enum values**: every value MUST have its own `///` line.
- **What to skip**: `@override` with identical contract, `_private` members
  (unless logic is non-obvious), generated files, test files.
- **Style**: third-person present tense. Never restate the symbol name as the
  opening word.
- **CI**: `dart doc . 2>&1 | grep -i warning` MUST return no output.

See [Appendix B](#appendix-b-reference-examples) for dartdoc examples.

---

## PERF — Performance

- Use `const` constructors everywhere possible.
- `ListView.builder` / `GridView.builder` for all lists — never a fixed widget
  list.
- No heavy computation inside `build()`.
- Use `RepaintBoundary` to isolate frequently-animating widgets.
- Profile with Flutter DevTools before claiming a performance fix.
- Never import entire libraries when only one class is needed (tree shaking).

### Asset Management

- Declare assets in `pubspec.yaml` under `flutter.assets:` and `flutter.fonts:`.
- Reference assets via `flutter_gen` accessors (e.g. `Assets.images.logo`) —
  never raw path strings.
- Regenerate with `dart run build_runner build` after any asset change.

---

## CROSSCUT — Cross-Cutting Concerns

All cross-cutting concerns live in `lib/core/`. Never duplicate in feature dirs.

### Logging

- Use `logger` via a single `AppLogger` `get_it` singleton in `core/di/`.
- Levels: `verbose`/`debug` (dev only), `info`, `warning`, `error`.
- Suppress `verbose` and `debug` in production builds.
- Never log PII, tokens, or passwords at any level.
- Never log cryptographic material at any level, including `verbose`: key bytes,
  ratchet state, session identifiers, peer fingerprints, plaintext content, or
  transport metadata (IP addresses, MAC addresses, HMAC values). **[C5]**
- **Opaque `sessionRef` rule [C14]:** an opaque session reference (a UUID with
  no derivable link to a peer identity) MAY be used for equality/comparison and
  MAY appear as a field in a domain event payload. It MUST NOT be passed to
  `AppLogger` at any level, and MUST NOT appear in any `AppFailure` field (see
  Failure Hierarchy **[C3]**). This resolves the apparent tension between
  **[C5]** (do not log session identifiers) and the reference example in
  [Appendix B](#appendix-b-reference-examples): the field is legal to hold and
  compare, illegal to log.

### Crash Reporting

- One service, documented in the plan before adoption. Wrap `runApp()` in
  `runZonedGuarded`.
- Disable or sandbox in `dev` and `staging` flavours.
- **Privacy carve-out [C12]:** a project whose blueprint declares a privacy or
  surveillance-minimisation goal MUST NOT ship a third-party telemetry SDK
  (e.g. Firebase Crashlytics) that egresses device data to an external
  operator. Use a self-hosted crash sink or an on-device-only reporter.
  Crash payloads MUST be scrubbed of PII and of every item in the crypto log
  blocklist before leaving the device. When in conflict, the project's privacy
  blueprint wins over the convenience default named here.

### Analytics

- One `AnalyticsService` interface in `core/`, injected via `get_it`.
  Feature code calls `analyticsService.track(...)` — never a third-party SDK
  directly.
- No-op implementation in `dev`.
- **Privacy carve-out [C12]:** for a privacy-goal project, the `staging`/`prod`
  implementation MUST be no-op or self-hosted and content-blind — never a
  third-party analytics SDK. A default "real implementation in staging and
  prod" does NOT apply to such projects; shipping behavioural telemetry from a
  privacy-first app contradicts its purpose.

### Feature Flags

- One `FeatureFlagService` interface in `core/`. No flag values hardcoded in
  feature code.

---

## PACKAGES — Approved Stack

Only use packages from this list. Justify any addition in the plan.

| Category | Package |
|---|---|
| Navigation | `go_router` |
| Networking | `dio` + `retrofit` |
| State Management | `riverpod` + `flutter_hooks` + `riverpod_generator` |
| Code Generation | `freezed` + `json_serializable` + `injectable` |
| FP / Result | `fpdart` |
| Local Storage | `isar` |
| Secure Storage | `flutter_secure_storage` |
| DI | `get_it` + `injectable` |
| Event Bus | `event_bus` |
| Image Caching | `cached_network_image` |
| Asset Generation | `flutter_gen` |
| Localisation | `flutter_localizations` + `intl` |
| Env Vars | `flutter_dotenv` |
| Logging | `logger` |
| Testing | `mocktail` |
| Coverage | `coverage` |
| Linting | `very_good_analysis` |
| Cryptography | No default. Each project documents its crypto packages in the plan. Every addition requires: named threat model rationale, security justification, and documented blast-radius if the package is compromised. **[C8]** **Reuse-vetted-first [C18]:** prefer adopting a vetted, audited protocol implementation (e.g. `libsignal`) over reimplementing session, ratchet, or group cryptography. Reimplementing a standard protocol a vetted library already provides requires explicit plan justification and an independent audit; where the vetted library is unsupported for third-party use, vendor it at a pinned, digest-verified commit rather than rolling your own. |

**`pubspec.yaml` hygiene:**
- Runtime deps under `dependencies:`, dev-only under `dev_dependencies:`.
- Range constraints only (e.g. `^3.0.0`) — no exact pins unless resolving a
  confirmed conflict.
- Run `flutter pub outdated` quarterly.
- Run `dart pub deps --no-dev` to confirm no dev packages leak into release.

---

## AGENT — Agent Behaviour

1. Read this constitution in full before producing any plan or code.
2. Author `.feature` files during planning. Do not begin implementation until
   plan and `.feature` files are accepted.
3. After adding or modifying any provider, event class, or asset, run:
   ```
   dart run build_runner build --delete-conflicting-outputs
   ```
   Include any regenerated `docs/events/<feature>.md` in the same commit.
4. One intent per commit. Do not bundle unrelated changes.
5. When adding a package, justify it in the plan and run `flutter pub get`.
6. Never suppress a lint or analysis warning with `// ignore:` without a
   documented reason in the same line.

---

## GOVERNANCE

This constitution supersedes all other project conventions. Violations require
refactoring — never a workaround or exception.

**Amendment procedure**: propose with rationale → team approval → migration
plan for non-compliant code → update file + bump version + update change log.

**Versioning**: MAJOR = principle removed or redefined. MINOR = new section or
material expansion. PATCH = clarification or wording only.

**Compliance**: every plan MUST include `.feature` files and pass a Constitution
Check. Code review MUST verify package stack, layer boundaries, test coverage,
and security rules. Complexity beyond these principles MUST be justified in the
plan's Complexity Tracking table.

---

## Appendix A: Anti-Patterns

Encountering any of these requires refactoring before proceeding.

| Anti-Pattern | Why Banned |
|---|---|
| `context.read()` inside `initState()` | Not yet mounted; use `ref.read()` in `AsyncNotifier.build()` or `useEffect` |
| `BuildContext` in a use case or repository | Layer boundary violation; domain is pure Dart |
| `await` inside `build()` | Causes rebuild loops; move async work to a provider |
| `dynamic` without a justification comment | Defeats type safety |
| Direct import of another feature's internal class | Bounded context violation; use `EventBus` or shared contract |
| `DioException` past the repository layer | Map to `AppFailure` at the repository boundary |
| `Dio` instantiated inside a feature | Singleton lives in `core/network/`; resolve via `get_it` |
| Raw asset path string in widget code | Use `flutter_gen` accessors |
| `StateProvider` usage | Not approved; use `NotifierProvider` |
| Editing `*.g.dart` or `*.freezed.dart` | Overwritten on next build; regenerate instead |
| Domain event missing any of the five dartdoc tags | Silent registry omission; CI violation |
| Editing `docs/events/*.md` manually | Overwritten on next `build_runner` run |
| `!` (bang) without a justification comment | Hides null-safety violations |
| Logging PII, tokens, or passwords | Security violation |
| Logging crypto material (keys, ratchet state, MACs, plaintext) | Key exfiltration vector; prohibited at all log levels **[C5]** |
| `freezed` on a class holding raw key material | Auto-generated `toString()` serialises key bytes; implement manually **[C1]** |
| DTO for a cryptographic class | JSON-serialises sensitive byte sequences; no `toJson()`/`fromJson()` on key material **[C9]** |
| `flutter_secure_storage` for hardware-protected key material | Bytes surface in Dart heap on retrieval; use platform-channel hardware keystore instead **[C2]** |
| Weakening crypto stack in `dev` or `staging` | Shortcuts routinely survive into production; crypto config must be flavour-identical **[C6]** |
| Crypto known-answer vector with real-looking key bytes | Social engineering risk; use synthetic material with `// TEST ONLY` comment **[C11]** |
| Third-party telemetry SDK in a privacy-goal project | Egresses device data to an external operator; use self-hosted/on-device, scrubbed **[C12]** |
| `core/crypto` or `core/security` below the raised coverage bar | Highest-risk code; needs ≥95% line+branch and KAT vectors **[C13]** |
| Logging `sessionRef` (or any opaque session ref) | Legal to hold/compare, illegal to log; resolves the C5/Appendix-B tension **[C14]** |
| Opening a key-material-backed store outside the crypto Isolate | Leaks the derived store key onto the main heap **[C17]** |
| Reimplementing a standard crypto protocol a vetted library already provides | Highest-risk path; reuse an audited implementation (e.g. libsignal), vendor + pin if unsupported **[C18]** |
| Adding a package without plan justification | Every dependency requires documented rationale |
| Undocumented public enum value | `dart doc` warning → CI failure |
| `@param` / `@return` / `@throws` in dartdoc | Not Dart convention; use inline prose + `[references]` |
| Raw quoted string where `[reference]` works | Doesn't link; goes stale silently |
| Missing summary sentence on first `///` line | Tooltip is blank in IDEs |

---

## Appendix B: Reference Examples

### Domain Event (with registry tags)

```dart
/// Fired when a [Task] transitions to [TaskStatus.completed].
///
/// @event
/// @dispatcher   CompleteTaskUseCase
/// @consumers    TaskListNotifier, ProjectProgressService
/// @payload      taskId (String), projectId (String), completedAt (DateTime)
/// @since        0.1.0
@freezed
class TaskCompleted with _$TaskCompleted {
  const factory TaskCompleted({
    required String taskId,
    required String projectId,
    required DateTime completedAt,
  }) = _TaskCompleted;
}
```

### Security-Critical Event (with consumer allowlist)

```dart
/// Fired when the Double Ratchet session state is missing or unrecoverable.
///
/// Adding a new consumer requires a security review — see EventBus Rules.
///
/// @event
/// @dispatcher   SecurityService
/// @consumers    MessagingNotifier
/// @payload      sessionRef (String — opaque internal reference),
///               brokenAt (DateTime)
/// @since        0.1.0
@freezed
class RatchetStateBroken with _$RatchetStateBroken {
  const factory RatchetStateBroken({
    required String sessionRef,
    required DateTime brokenAt,
  }) = _RatchetStateBroken;
}
```

### Key-Material Class (no `freezed` — manual implementation)

```dart
/// Holds the current Double Ratchet sending chain key.
///
/// Never logged, serialised, or passed across Isolate boundaries as bytes.
/// Equality is based on [sessionRef] only — key bytes are never compared.
class RatchetChainKey {
  RatchetChainKey({required this.sessionRef, required Uint8List keyBytes})
      : _keyBytes = keyBytes;

  /// Opaque internal session reference — safe to compare and to carry in
  /// event payloads, but MUST NOT be written to logs. See [C14].
  final String sessionRef;
  final Uint8List _keyBytes;

  Uint8List get keyBytes => _keyBytes;

  @override
  String toString() => '[SecuritySensitive — contents withheld]';

  @override
  bool operator ==(Object other) =>
      other is RatchetChainKey && other.sessionRef == sessionRef;

  @override
  int get hashCode => sessionRef.hashCode;
}
```

### Freezed Class Dartdoc

```dart
/// An immutable line item in a shopping cart.
///
/// [quantity] must be greater than zero — validated by [AddToCartUseCase].
/// [unitPrice] is captured at add-time and does not update if the product
/// price changes later.
@freezed
class CartItem with _$CartItem {
  const factory CartItem({
    required String productId,
    required Money unitPrice,
    @Default(1) int quantity,
  }) = _CartItem;
}
```

### Use Case Dartdoc

```dart
/// Marks [task] as complete and records the completion timestamp.
///
/// Dispatches [TaskCompleted] via the [EventBus] on success.
/// Returns [Either.left] with [ValidationFailure] if the [Project] is
/// archived, or [NetworkFailure] if the remote source is unreachable.
Future<Result<void>> call(Task task);
```

### Enum Dartdoc

```dart
/// The lifecycle state of a [Task].
enum TaskStatus {
  /// Created but not yet started.
  todo,

  /// Actively being worked on.
  inProgress,

  /// Completed and verified.
  done,

  /// Removed from scope without completion.
  cancelled,
}
```

### Failure Mapping in a Repository

```dart
Future<Result<Order>> fetchOrder(String orderId) async {
  try {
    final dto = await _remoteDataSource.getOrder(orderId);
    return right(_mapper.toDomain(dto));
  } on DioException catch (e) {
    return left(NetworkFailure(message: e.message));
  } catch (e) {
    return left(const UnexpectedFailure());
  }
}
```

---

**Version**: 1.4.2-lean | **Base**: 1.4.2 | **Last Amended**: 2026-07-06
