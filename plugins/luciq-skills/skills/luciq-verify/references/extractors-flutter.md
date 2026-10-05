# Flutter Extractors

Per-file scan recipe for Flutter projects in Phase 2 (static audit). Static-only check; runtime audit on Flutter projects uses the bug + crash channels because APM is permanently `N/A` on Flutter (see `payload-schemas.md`).

## Table of contents

1. [Scan plan](#scan-plan)
2. [`pubspec.yaml`](#pubspecyaml)
3. [Dart source (`*.dart`)](#dart-source-dart)
4. [Anti-patterns to flag](#anti-patterns-to-flag)

## Scan plan

| File | Role |
| --- | --- |
| `pubspec.yaml` | Package declaration + pinned version |
| `pubspec.lock` | Resolved version (cross-reference) |
| `**/*.dart` | Source: init, modules, invocation, masking, identity, flags, logging |

Skip directories: `.git/`, `build/`, `.dart_tool/`, `ios/`, `android/` (those are scanned by their respective platform extractors when the project is hybrid).

## `pubspec.yaml`

### Dependency detection (`S-INSTALL-001`, `S-INSTALL-002`)

Look for the Luciq Flutter package in `dependencies:` or `dev_dependencies:`:

```yaml
dependencies:
  luciq_flutter: ^X.Y.Z
```

Legacy: `instabug_flutter` (during migration).

Emits:
- `S-BUILD-FLUTTER PASS` if `pubspec.yaml` is present at scan root
- `S-INSTALL-001 PASS` if `luciq_flutter` or `instabug_flutter` declared
- `S-INSTALL-002` per rule-pack `expected_sdk_version` cross-check (parsed from `pubspec.lock` for the resolved version)
- `S-INSTALL-004 WARN` if both `luciq_flutter` and `instabug_flutter` are declared — message: `"both Luciq and legacy Instabug packages declared in pubspec.yaml; if you're mid-migration, run luciq-migrate to finish the rename. Long-term coexistence is not supported."`

## Dart source (`*.dart`)

### SDK init (`S-INSTALL-003`)

Patterns:
- `Luciq.init(`
- `Luciq.init( token:`
- `await Luciq.init(`

`Luciq.init` returns a `Future`, but the SDK's own README and example call it without `await`, inside `runZonedGuarded` in `main()` and before `runApp`. Don't flag a missing `await`; check placement and crash hooks instead (see *Anti-patterns*).

### Module toggles (`S-MODULE-*`)

| Module | Patterns |
| --- | --- |
| Bug Reporting | `BugReporting.setEnabled` |
| Crash Reporting | `CrashReporting.setEnabled` |
| NDK | `CrashReporting.setNDKEnabled` |
| APM | `APM.setEnabled` (subset support — APM is mostly auto-instrumented on Flutter) |
| Session Replay | `SessionReplay.setEnabled`, `SessionReplay.setNetworkLogsEnabled`, `SessionReplay.setUserStepsEnabled`, `SessionReplay.setLuciqLogsEnabled` |
| Network Logs | No Dart switch. Requests are logged only through an add-on interceptor in `pubspec.yaml`: `luciq_dio_interceptor`, `luciq_http_client` or `luciq_gql_link`. Bodies: `NetworkLogger.setNetworkLogBodyEnabled` |
| Surveys | `Surveys.setEnabled` |
| Replies | `Replies.setEnabled` |
| Whole SDK | `Luciq.setEnabled` |

### Invocation events (`S-INVOKE-*`)

Patterns:
- `invocationEvents:` (named arg in `Luciq.init`)
- `BugReporting.setInvocationEvents(` (runtime override after init)
- `InvocationEvent.shake`, `InvocationEvent.screenshot`, `InvocationEvent.floatingButton`, `InvocationEvent.twoFingersSwipeLeft`, `InvocationEvent.none`

### Identity + attributes (`S-IDENTITY-*`)

| Code | Patterns |
| --- | --- |
| `S-IDENTITY-USER` | `Luciq.identifyUser`, `Luciq.setUserData` |
| `S-IDENTITY-LOGOUT` | `Luciq.logOut` |
| `S-IDENTITY-ATTR` | `Luciq.setUserAttribute`, `Luciq.removeUserAttribute`, `Luciq.getUserAttributeForKey` |
| `S-IDENTITY-CDATA` | `Luciq.setUserData(` |

### Feature flags (`S-FLAG-*`)

Flutter SDK exposes the full feature-flag API (verified):

| Code | Patterns |
| --- | --- |
| `S-FLAG-ADD` | `Luciq.addFeatureFlags` |
| `S-FLAG-REMOVE` | `Luciq.removeFeatureFlags` |
| `S-FLAG-CLEAR` | `Luciq.clearAllFeatureFlags` |

### Custom logging (`S-LOG-*`)

| Code | Patterns |
| --- | --- |
| `S-LOG-API` | `LuciqLog.logVerbose(`, `LuciqLog.logDebug(`, `LuciqLog.logInfo(`, `LuciqLog.logWarn(`, `LuciqLog.logError(` |
| `S-LOG-USEREVENT` | `Luciq.logUserEvent(` |

### Masking config (`S-MASK-*`)

| Code | Patterns |
| --- | --- |
| `S-MASK-SCREEN` | `Luciq.setAutoMaskScreenshotTypes(`, `LuciqWidget(automasking:`, `LuciqPrivateView(`, `LuciqSliverPrivateView(`, `Luciq.setReproStepsConfig`, `Luciq.setScreenNameMaskingCallback` |
| `S-MASK-NETWORK` | `NetworkLogger.setNetworkAutoMaskingEnabled`, `NetworkLogger.setNetworkLogBodyEnabled(false)` |
| `S-MASK-CALLBACK` | `NetworkLogger.obfuscateLog(`, `NetworkLogger.omitLog(` |

### Route wrapping (informational)

`MaterialApp` typically wraps with `LuciqNavigatorObserver` for screen-loading APM. `MaterialApp.router` (Navigator 2.0) ignores `navigatorObservers`, so there the observer goes on the router instead, e.g. `GoRouter(observers: [LuciqNavigatorObserver()])`. Detection:

- `LuciqNavigatorObserver` referenced in `*.dart` → `INFO`
- Absence with route-based app → `INFO` "screen-loading APM may be partial without LuciqNavigatorObserver"

## Anti-patterns to flag

| Anti-pattern | Detection | Status |
| --- | --- | --- |
| No Dart crash hooks | `Luciq.init` found, but no `CrashReporting.reportCrash` passed to `runZonedGuarded` (or `PlatformDispatcher.instance.onError`) and no `FlutterError.onError` forwarding. `Luciq.init` installs no error handlers itself | `WARN` — Dart exceptions are not reported |
| `LuciqPrivateView` with no `LuciqWidget` | `LuciqPrivateView(` / `LuciqSliverPrivateView(` used, but no `LuciqWidget(` wraps the app (or it sets `enablePrivateViews: false`) | `FAIL` — the private views mask nothing, silently |
| Init in `main()` after `runApp()` | Init must precede `runApp` to capture early errors | `WARN` |
| Token in source (vs. read from env / `--dart-define`) | Long string literal passed as the `token:` named arg to `Luciq.init` | `WARN` masked in report |
| Both `luciq_flutter` and `instabug_flutter` declared | Both packages in `pubspec.yaml` dependencies | `WARN` — run `luciq-migrate` to finish the rename if mid-migration; long-term coexistence is unsupported |
| Module disabled in release mode source path | `setXEnabled(false)` outside any `kDebugMode` guard | `INFO` surface for review |
