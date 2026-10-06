# DaChat Constitution

## Core Principles

### I. Reference Constitution Is Authoritative

This file is the Spec Kit gate. The full, binding rule set is
`references/flutter_constitution.md` (v2.0.0). Where they disagree, the reference wins, and this file
MUST be corrected in the same change.

- Agents MUST read `references/flutter_constitution.md` in full before any plan, code, or test.
- Authority order for conflicts: (1) `references/flutter_constitution.md`,
  (2) `references/RQSM_Blueprint.md` for cryptography, transports, and platform security,
  (3) `references/FlowChat_Privacy_MentalHealth_Blueprint.md` for privacy and mental-health
  features. Where the RQSM blueprint states a security rule, it restates a constitution rule
  (C1–C20) in project-specific terms; it does not override one.
- MVP scope is bounded; deferred scope lives in `references/Future_Features_Roadmap.md` and MUST
  NOT be pulled into a feature without its own spec.

**Rationale**: one authoritative source keeps agents from receiving conflicting instructions.

### II. Clean Architecture & DDD Boundaries

- Every feature is a bounded context under `lib/features/<feature>/` with `data/`, `domain/`, and
  `presentation/` layers.
- `domain/` MUST be pure Dart: no Flutter imports. The only third-party imports allowed are
  `freezed_annotation`, `fpdart`, `injectable` annotations, `event_bus`, and `meta`.
  Dependencies arrive through constructors; there are no `get_it` lookups in `domain/`.
- Widgets reach the domain only through a Cubit/Bloc, and the Cubit/Bloc only through use cases.
  DTOs never leave `data/`.
- Repository methods and use cases return `Result<T>` (`fpdart` `Either<AppFailure, T>`).
  Exceptions MUST NOT cross layer boundaries.
- Cross-feature communication uses `EventBus` domain events or shared contracts only. Events
  carry the five registry dartdoc tags.

**Rationale**: strict boundaries keep the crypto core auditable and features independently
testable.

### III. Security & Privacy by Design (NON-NEGOTIABLE)

- **Reuse vetted crypto (C18)**: session, ratchet, group, and sealed-sender cryptography come
  from vendored, pinned, digest-verified `libsignal-client`. Reimplementing a protocol it provides
  is prohibited. Custom crypto is confined to what the RQSM blueprint enumerates and requires an
  independent audit before production.
- **Key material**: never in `freezed` classes, DTOs, Cubit/Bloc state, logs, or failure fields
  (C1, C3, C9, C20). It is kept behind the FFI boundary or inside the crypto Isolate (C17).
- **Storage tiers (C2, C15)** MUST be used as defined. At-rest stores MUST be encrypted and
  excluded from OS backups.
- **Logging (C5, C14, C19)**: no PII, plaintext, key material, session references, or transport
  metadata at any log level. `AppBlocObserver` logs `runtimeType`s only.
- **No third-party telemetry or analytics SDKs (C12)**. Crash sinks are self-hosted or
  on-device, and payloads are scrubbed.
- **Flavour parity (C6)**: crypto configuration is identical across `dev`, `staging`, and `prod`.
- Security claims MUST stay honest. Post-quantum confidentiality applies at session
  establishment; authentication is classical. Adversary residuals are disclosed to users.
- Decrypted content in presentation state MUST be cleared on lock and logout (C20).

**Rationale**: DaChat's purpose is privacy against servers, networks, and device seizure. A single
leak path defeats it.

### IV. Test-First, Behaviour-Driven (NON-NEGOTIABLE)

- Gherkin `.feature` files are authored during planning. Implementation MUST NOT begin until the
  plan and the `.feature` files are accepted.
- Unit tests cover all use cases, repositories, domain logic, and every Cubit/Bloc (`blocTest`,
  including the failure path). Widget tests cover every screen's `View` using `MockCubit` /
  `MockBloc`. Integration tests trace to `.feature` scenarios.
- Coverage: domain + data layers at least 80% line coverage. `core/crypto/` + `core/security/` at
  least 95% line AND branch coverage, with known-answer vectors for project-implemented primitives
  (C13).
- Crypto fixtures use clearly synthetic key material marked `// TEST ONLY` (C11).

**Rationale**: behaviour is agreed before code, and the highest-risk code carries the highest bar.

### V. Explicit, Readable State

- State management is `flutter_bloc` only. Use a Cubit by default. Use a Bloc only for event
  concurrency or security-critical flows that need an auditable event log.
- No state-management code generation.
- Cubits are thin: they call use cases and map `Result<T>` to state. States are sealed unions,
  switched exhaustively (no wildcard).
- Cubits are constructed by `get_it`, scoped with `BlocProvider(create:)`, and split into
  Page/View. Side effects happen only in `BlocListener`.
- `flutter_hooks` is limited to widget-local controllers.

**Rationale**: humans and agents must be able to read every state transition without
generated artifacts. Thin Cubits keep a future state-library migration cheap.

### VI. Approved Stack & Vetted Dependencies

- Only packages on the reference constitution's approved list. Any addition requires a plan
  justification. Crypto additions also require a threat-model rationale and a blast-radius
  statement (C8).
- RQSM's justified non-standard packages (e.g. `moxxmpp`, `sql_crdt`, `flutter_rust_bridge`) are
  approved only as listed in its justification table, which MUST be updated in the same PR as
  any addition.
- Prefer mature, multi-maintainer packages. Use version ranges, not exact pins, except for
  vendored crypto.

**Rationale**: every dependency is supply-chain attack surface in a security product.

### VII. Accessible, Localised, Themed UI

- All user-facing strings go through `AppLocalizations`. Colours and text come from the
  theme. Light and dark mode are supported.
- Every interactive element and non-decorative image has `Semantics`. Spacing uses named
  constants. Layouts adapt to screen size.
- Visual design decisions live in `DESIGN.md` when one exists.

**Rationale**: privacy and mental-health features only help users who can read and operate them.

## Technology & Security Constraints

- **Platforms**: Android, iOS, Linux. Linux key storage is weaker (no secure element) and MUST be
  disclosed.
- **Core stack**: Flutter/Dart 3, `go_router`, `dio` + `retrofit`, `flutter_bloc`, `get_it` +
  `injectable`, `freezed`, `fpdart`, `isar`, `event_bus`, `logger`, `very_good_analysis`.
- **Messaging**: XMPP (`moxxmpp`) is the primary transport. The MVP is internet-first and
  single-device. Mesh transports are deferred per the roadmap.
- **Crypto**: `libsignal-client` via `flutter_rust_bridge`: PQXDH (ML-KEM-1024 + X25519),
  Double Ratchet, Sender Keys, and Curve25519 identity.
- **Platform hardening**: `FLAG_SECURE` / snapshot blur on sensitive screens. Push-timing metadata
  exposure is documented.

## Development Workflow & Quality Gates

- Spec Kit flow: `/speckit-specify` → `/speckit-clarify` → `/speckit-plan` (with `.feature`
  files and a Constitution Check against this file) → `/speckit-tasks` → `/speckit-implement`.
- CI gate (all MUST pass before merge):
  - `dart analyze` returns zero issues.
  - `dart doc` emits no warnings.
  - `flutter test --coverage` meets the Principle IV thresholds.
  - All three test layers pass.
  - The `pubspec.yaml` diff contains no unapproved packages.
- After any `freezed`, `injectable`, domain-event, or asset change, run
  `dart run build_runner build --delete-conflicting-outputs`. Commit the regenerated
  `docs/events/` files.
- One intent per commit. Never edit generated files. No `// ignore:` without an inline reason.
- Adding a consumer to a security-critical event requires a security review (C4).

## Governance

- This constitution and `references/flutter_constitution.md` supersede all other project
  conventions. Violations require refactoring, never a workaround.
- **Amendments**: propose with rationale, then obtain approval, then write a migration plan for
  non-compliant code. Amend the reference constitution first, then mirror it here in the same
  change, with matching version numbers and change-log entries.
- **Versioning**: MAJOR when a principle is removed or redefined. MINOR when a principle or
  section is added or materially expanded. PATCH for clarification or wording only.
- **Compliance**: every plan MUST pass a Constitution Check against Principles I–VII. Code
  review verifies the package stack, layer boundaries, test coverage, and security rules.
  Complexity beyond these principles MUST be justified in the plan's Complexity Tracking table.
- Runtime agent guidance lives in `AGENTS.md` (imported by `CLAUDE.md`).

**Version**: 2.0.0 | **Ratified**: 2026-10-06 | **Last Amended**: 2026-10-06
