# Flutter & Dart — Antigravity AI Rules
> Paste this into Antigravity's User Rules settings. Pair with Claude Sonnet 4.6 for best results.

---

## 1. Core Flutter & Dart Principles

You are an expert in Flutter and Dart development for building beautiful, natively compiled applications.

- Everything is a Widget — compose, don't inherit
- Declarative UI at all times
- Strong typing with sound null safety — no dynamic types without justification
- Use async/await for all asynchronous operations
- Use Isolates for heavy computation to keep the UI thread free
- Hot Reload is your feedback loop — keep widgets small and focused

---

## 2. Architecture — Feature-First Clean Architecture (FFCA)

Always follow Clean Architecture. Separate every feature into three layers:

```
lib/
├── core/                        # Shared utilities, theme, constants, error handling
│   ├── error/
│   ├── theme/
│   └── utils/
├── features/
│   └── <feature_name>/
│       ├── data/                # Data sources, DTOs, repository implementations
│       │   ├── datasources/
│       │   ├── models/
│       │   └── repositories/
│       ├── domain/              # Entities, repository contracts, use cases
│       │   ├── entities/
│       │   ├── repositories/
│       │   └── usecases/
│       └── presentation/        # Widgets, screens, state notifiers/providers
│           ├── pages/
│           ├── widgets/
│           └── providers/
└── main.dart
```

**Rules:**
- Never call APIs or databases directly from UI code
- UI code must only interact with the domain layer through use cases or providers
- Repository contracts (interfaces) live in `domain/`; implementations live in `data/`
- One use case per file, one responsibility per use case
- Entities are plain Dart objects — no Flutter imports allowed in `domain/`

---

## 3. State Management — Riverpod

Use **Riverpod** (with `flutter_hooks`) as the sole state management solution.

- Never mix state management solutions (no Provider, GetX, or BLoC alongside Riverpod)
- Use `AsyncNotifierProvider` for all async data fetching
- Use `NotifierProvider` for synchronous, mutable state
- Use `StateProvider` only for simple, isolated values (e.g. a toggle)
- Use `riverpod_generator` and `@riverpod` annotations for all providers
- All providers must be defined at the top level — no providers inside widgets
- Handle loading, data, and error states explicitly for every `AsyncValue`

```dart
// Preferred pattern
@riverpod
Future<List<Product>> products(ProductsRef ref) async {
  final repo = ref.watch(productRepositoryProvider);
  return repo.getProducts();
}
```

---

## 4. Approved Package Stack

Only use packages from the approved list below. Always check pub.dev scores (popularity, likes, pub points) before suggesting anything outside this list. Never add a package without justification.

| Category         | Package                              |
|------------------|--------------------------------------|
| Navigation       | `go_router`                          |
| Networking       | `dio` + `retrofit`                   |
| State management | `riverpod` + `flutter_hooks` + `riverpod_generator` |
| Code generation  | `freezed` + `json_serializable`      |
| FP / Result type | `fpdart`                             |
| Local storage    | `hive` or `isar`                     |
| DI               | `get_it` + `injectable`              |
| Image caching    | `cached_network_image`               |
| Testing          | `mocktail`                           |
| Linting          | `very_good_analysis`                 |
| Env vars         | `flutter_dotenv`                     |
| Logging          | `logger`                             |

---

## 5. Testing — Three-Layer Coverage (Non-Negotiable)

Every feature must have tests across all three layers before it is considered complete.

**Unit Tests**
- All use cases
- All repository implementations
- All domain entities with complex logic
- Mock dependencies with `mocktail` — never use real network calls or databases in unit tests

**Widget Tests**
- All custom widgets
- All screens (at minimum: renders without error, key interactions work)
- Use `pumpWidget` with a `ProviderScope` override for Riverpod providers

**Integration Tests**
- All critical user flows (auth, checkout, onboarding, etc.)
- Run against a real or stubbed backend

```
test/
├── unit/
│   └── features/<feature>/
├── widget/
│   └── features/<feature>/
└── integration/
```

---

## 6. Performance

- Use `const` constructors everywhere possible to prevent unnecessary rebuilds
- Use `ListView.builder` / `GridView.builder` for all lists — never map to a fixed list of widgets
- Minimise widget tree depth; extract reusable sub-widgets into their own classes
- Never perform heavy computation inside `build()` methods
- Use `RepaintBoundary` to isolate frequently-animating widgets
- Profile with Flutter DevTools before claiming a performance fix
- Enable tree shaking — never import entire libraries when only one class is needed

---

## 7. Code Quality & Linting

- Enforce `very_good_analysis` lint rules on every file — zero lint warnings are acceptable at merge
- Sound null safety throughout — no use of `!` (bang operator) without an explicit justification comment
- All public APIs (classes, methods, functions) must have dartdoc comments
- Follow the official Dart style guide: `lowerCamelCase` for variables/methods, `UpperCamelCase` for classes
- No magic numbers or hardcoded strings — use constants or l10n keys
- Max function length: 40 lines. If longer, extract into smaller functions

---

## 8. Security

- Never hardcode API keys, secrets, or tokens in source code — use `flutter_dotenv` with `.env` (gitignored)
- All sensitive data in local storage must be encrypted (use `flutter_secure_storage` for credentials)
- Follow OWASP Mobile Top 10 guidelines
- Validate all user input before sending to the backend
- Never log sensitive user data (PII, tokens, passwords)
- Sanitise error messages shown to users — never expose stack traces or internal details in production

---

## 9. Navigation — go_router

- All routes must be defined in a single central router file (`lib/core/router/app_router.dart`)
- Use named routes only — no string literals scattered across the codebase
- Use `GoRouter.redirect` for auth guards
- Pass data via route parameters or `extra` — never via global state

---

## 10. Dart & Flutter Best Practices

- Always use `freezed` for data classes, union types, and sealed classes
- Always use `fpdart` `Either<Failure, T>` as the return type for repository methods and use cases — never throw exceptions across layer boundaries
- Use extensions to keep classes clean — add helper methods via `extension` rather than subclassing
- Prefer composition over inheritance in widget design
- Use `ThemeData` and `ColorScheme` for all colours and text styles — no hardcoded `Color(0xFF...)` in widgets
- Support both light and dark mode from day one
- Implement `Semantics` widgets for accessibility on all interactive elements
- Wrap all user-facing strings in `AppLocalizations` (l10n) from the start

---

## 11. Antigravity Agent Behaviour

- Always use Planning Mode before starting any new feature — review the implementation plan before accepting
- Run `dart analyze` and `flutter test` after every change and fix all issues before proceeding
- One intent per commit — do not bundle unrelated changes
- When adding a new package, always run `flutter pub get` and verify it resolves cleanly
- Never modify generated files (`*.g.dart`, `*.freezed.dart`) — regenerate them with `flutter pub run build_runner build --delete-conflicting-outputs`
- If a step fails, diagnose and fix the root cause — do not work around it with hacks

---

## 12. CLAUDE.md (Project Memory)

Place a `CLAUDE.md` at the project root to give Claude persistent context across sessions. It should include:

```markdown
# Project: <App Name>
## Stack
- Flutter 3.x / Dart 3.x
- State: Riverpod + flutter_hooks
- Architecture: Feature-First Clean Architecture
- Navigation: go_router
- Backend: <your backend here>

## Key Conventions
- fpdart Either for error handling across layers
- freezed for all data models
- mocktail for all test mocks
- very_good_analysis lints enforced

## Approved Packages
(reference Section 4 above)

## Out of Scope
- No GetX, Provider, or BLoC
- No hardcoded colours or strings
- No direct API calls from UI
```

---

*Sources: docs.flutter.dev/ai/ai-rules · antigravity.codes/rules · pub.dev*
