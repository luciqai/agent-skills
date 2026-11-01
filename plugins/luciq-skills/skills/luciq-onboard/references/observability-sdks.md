# Mobile Observability SDK Reference

This file is read by `luciq-onboard` during Phase 1 (analyze) to detect any mobile observability SDKs already present in the project, extract their config posture, classify conflicts with Luciq, and map coverage gaps.

The v1 scope is **10 SDKs** that cover the vast majority of real-world environments. Adding more is a v2 question — first see what actually shows up in customer sessions.

For every SDK below:

- **Family** — drives the framing in the recap.
- **Detection patterns** — what to grep for in manifests and source. Three signals (manifest + init + config) confirm "active." Manifest-only = shelf-ware.
- **Config keys to extract** — the values that reveal team posture. Read them at the init site.
- **Coverage cells** — which Luciq products this SDK overlaps with.
- **Conflicts with Luciq** — adding which Luciq product creates a real technical conflict (signal handler race, swizzle overlap, etc.).
- **Style inference** — how to translate the extracted config into a one-line team-style summary.

Verify exact init class names and option keys against the SDK's live documentation before extracting — vendor APIs evolve.

---

## 1. Sentry

**Family.** Full-stack competitor (crash + perf + replay).

**Detection patterns.**
| Platform | Manifest | Init signature |
|---|---|---|
| iOS | `sentry-cocoa` in Podfile / Package.swift / Cartfile | `SentrySDK.start { options in` |
| Android | `io.sentry:sentry-android` in build.gradle(.kts) | `SentryAndroid.init(...)` or auto via manifest meta-data |
| React Native | `@sentry/react-native` in package.json | `Sentry.init({ ... })` |
| Flutter | `sentry_flutter` in pubspec.yaml | `await SentryFlutter.init(...)` |

Config artifacts: `sentry.properties` (build-time), `Sentry.Default.json` rare.

**Config keys to extract.**
- `dsn` (project identity)
- `tracesSampleRate`, `profilesSampleRate`, `replaysSessionSampleRate`, `replaysOnErrorSampleRate`
- `attachScreenshot`, `attachViewHierarchy`
- `sendDefaultPii`
- `enableAppHangTracking`, `appHangTimeoutInterval`
- `enableNetworkBreadcrumbs`, `enableNetworkTracking`
- `maxBreadcrumbs`
- `environment`, `release`, `dist`
- `enabledReleaseStages` (if RN/Flutter) or build-config gating wrapper
- Presence of `beforeSend` / `beforeBreadcrumb` callbacks (custom filtering discipline)

**Coverage cells.** Crashes ✓ · Hangs/ANR ✓ · APM ✓ · Network logging ✓ · Session Replay ✓ (beta on mobile) · Bug Reports – · Surveys – · Ratings –

**Conflicts with Luciq.** Crash Reporting (dual signal handlers). Network interceptor stack (if both are wired through `URLSession` / `OkHttp`).

**Style inference rules.**
- `sendDefaultPii: false` AND `attachScreenshot: false` → **privacy-conservative**.
- `tracesSampleRate ≤ 0.1` → **low sampling budget**.
- Has `beforeSend` filters in source → **high filter discipline**.
- Has `enabledReleaseStages` excluding `debug` → **strict env gating**.

---

## 2. Firebase Crashlytics

**Family.** Crash-only (with ANR).

**Detection patterns.**
| Platform | Manifest | Init signature |
|---|---|---|
| iOS | `FirebaseCrashlytics` pod or SPM | `FirebaseApp.configure()` + Crashlytics enabled |
| Android | `com.google.firebase:firebase-crashlytics` | `FirebaseApp.initializeApp(context)` + plugin applied |
| React Native | `@react-native-firebase/crashlytics` | autolinked, `crashlytics().log(...)` calls |
| Flutter | `firebase_crashlytics` | `FirebaseCrashlytics.instance.recordError(...)` |

Config artifacts: `GoogleService-Info.plist` (iOS), `google-services.json` (Android).

**Config keys to extract.**
- `setCrashlyticsCollectionEnabled(true/false)` — opt-in gating
- `setUserID` call sites — already wiring identity?
- `setCustomKey` usage — list the keys, indicates what context the team tracks
- `log()` breadcrumb usage pattern
- Build-config gates (debug-only init, release-only init)

**Coverage cells.** Crashes ✓ · Hangs/ANR ✓ (Android only) · APM – · Network logging – · Session Replay – · Bug Reports – · Surveys – · Ratings –

**Conflicts with Luciq.** Crash Reporting (dual signal handlers).

**Style inference rules.**
- `setCrashlyticsCollectionEnabled(false)` in debug → **strict env gating**.
- Rich `setCustomKey` usage → **high observability discipline** (team will want similar custom attributes in Luciq).

---

## 3. Bugsnag

**Family.** Full-stack competitor (crash + perf + network).

**Detection patterns.**
| Platform | Manifest | Init signature |
|---|---|---|
| iOS | `Bugsnag` pod or SPM | `Bugsnag.start()` or `Bugsnag.start(withApiKey:)` |
| Android | `com.bugsnag:bugsnag-android` | `Bugsnag.start(context, config)` |
| React Native | `@bugsnag/react-native` | `Bugsnag.start({ ... })` |
| Flutter | `bugsnag_flutter` | `await Bugsnag.start(apiKey: ...)` |

Config artifacts: `bugsnag.properties` (build-time, Android).

**Config keys to extract.**
- `apiKey`, `releaseStage`, `enabledReleaseStages`
- `autoTrackSessions`, `autoDetectErrors`, `autoDetectAnrs`
- `redactedKeys` (PII redaction list — the gold)
- `OnError` / `OnSession` / `OnBreadcrumb` callbacks
- `maxBreadcrumbs`, `enabledBreadcrumbTypes`
- `appType`, `context`

**Coverage cells.** Crashes ✓ · Hangs/ANR ✓ · APM ✓ · Network logging ✓ · Session Replay – · Bug Reports – · Surveys – · Ratings –

**Conflicts with Luciq.** Crash Reporting (dual signal handlers). Network interceptor stack.

**Style inference rules.**
- Long `redactedKeys` list → **privacy-conservative; mirror redaction list in Luciq**.
- `enabledReleaseStages: [production]` only → **strict env gating**.
- Multiple `OnError` callbacks → **high filter discipline**.

---

## 4. Datadog RUM

**Family.** APM / RUM-leaning.

**Detection patterns.**
| Platform | Manifest | Init signature |
|---|---|---|
| iOS | `DatadogCore`, `DatadogRUM` via SPM | `Datadog.initialize(...)` and `RUM.enable(...)` |
| Android | `com.datadoghq:dd-sdk-android-rum` | `Datadog.initialize(...)` and `GlobalRumMonitor.registerIfAbsent(...)` |
| React Native | `@datadog/mobile-react-native` | `DdSdkReactNative.initialize(...)` |
| Flutter | `datadog_flutter_plugin` | `await DatadogSdk.instance.initialize(...)` |

Config artifacts: usually inline.

**Config keys to extract.**
- `clientToken`, `applicationID`, `env`, `service`
- `sessionSampleRate`, `resourceSampleRate`, `longTaskThreshold`
- `trackUserActions`, `trackFrustrations`, `trackBackgroundEvents`, `trackResources`, `trackLongTasks`
- `firstPartyHosts` (which API hosts they're tracking)
- `viewEventMapper`, `errorEventMapper` (custom filtering)
- `privacy` config block

**Coverage cells.** Crashes ✓ · Hangs/ANR ✓ · APM ✓ · Network logging ✓ · Session Replay ✓ · Bug Reports – · Surveys – · Ratings –

**Conflicts with Luciq.** Crash Reporting (dual handlers). Network interceptor stack.

**Style inference rules.**
- `sessionSampleRate < 0.5` → **low sampling budget**.
- `trackBackgroundEvents: false` → **conservative posture**.
- `viewEventMapper` present → **high filter discipline**.
- `firstPartyHosts` curated to a small list → **strict scoping**.

---

## 5. Embrace

**Family.** Full-stack competitor (crash + perf + replay).

**Detection patterns.**
| Platform | Manifest | Init signature |
|---|---|---|
| iOS | `EmbraceIO` via SPM / pod | `try Embrace.setup(...).start()` |
| Android | `io.embrace:embrace-android-sdk` + Gradle plugin | `Embrace.getInstance().start(context)` |
| React Native | `@embrace-io/react-native` | `initialize({ ... })` from `@embrace-io/react-native` |

Config artifacts: `Embrace-Info.plist` (iOS), `embrace-config.json` (Android).

**Config keys to extract.**
- App ID, `captureAutoTraces`, `captureCoreData` (iOS)
- `tapsCaptureEnabled`, `screenshotCaptureEnabled`, `webViewCaptureEnabled`
- `breadcrumbLimit`, `logLimits`
- Networking interceptor enablement

**Coverage cells.** Crashes ✓ · Hangs/ANR ✓ · APM ✓ · Network logging ✓ · Session Replay ✓ · Bug Reports – · Surveys – · Ratings –

**Conflicts with Luciq.** Crash Reporting (dual handlers). Session Replay (two replay capturers simultaneously is wasteful, sometimes incompatible).

**Style inference rules.**
- `screenshotCaptureEnabled: false` → **privacy-conservative**.
- `tapsCaptureEnabled: false` → **minimal-touchpoint capture**.

---

## 6. New Relic Mobile

**Family.** APM / RUM-leaning.

**Detection patterns.**
| Platform | Manifest | Init signature |
|---|---|---|
| iOS | `NewRelicAgent` via SPM / pod | `NewRelic.start(withApplicationToken:)` |
| Android | `com.newrelic.agent.android:android-agent` + Gradle plugin | `NewRelic.withApplicationToken(...).start(this)` |
| React Native | `newrelic-react-native-agent` | `NewRelic.startAgent(token)` |

Config artifacts: usually inline.

**Config keys to extract.**
- `applicationToken`
- `crashReportingEnabled`, `analyticsEventEnabled`
- `networkRequestEnabled`, `networkErrorRequestEnabled`, `httpResponseBodyCaptureEnabled`
- `interactionTracingEnabled`, `gestureInstrumentation`
- `webViewInstrumentation`
- `loggingEnabled`, `logLevel`

**Coverage cells.** Crashes ✓ · Hangs/ANR ✓ · APM ✓ · Network logging ✓ · Session Replay – · Bug Reports – · Surveys – · Ratings –

**Conflicts with Luciq.** Crash Reporting (dual handlers). Network interceptor stack.

**Style inference rules.**
- `httpResponseBodyCaptureEnabled: false` → **privacy-conservative on network**.
- `gestureInstrumentation: false` → **minimal-touchpoint capture**.

---

## 7. Microsoft App Center

**Family.** Crash-only (deprecated 2025-03-31 but still present in many apps).

**Detection patterns.**
| Platform | Manifest | Init signature |
|---|---|---|
| iOS | `AppCenter`, `AppCenterCrashes` via Carthage / pod | `MSACAppCenter.start(withAppSecret:, services:)` |
| Android | `com.microsoft.appcenter:appcenter-crashes` | `AppCenter.start(application, secret, Crashes.class)` |
| React Native | `appcenter-crashes` | `Crashes.setEnabled(true)` |

**Config keys to extract.**
- App secret presence
- `setEnabled` calls — opt-in gating
- Crash-listener implementations

**Coverage cells.** Crashes ✓ · Hangs/ANR – · APM – · Network logging – · Session Replay – · Bug Reports – · Surveys – · Ratings –

**Conflicts with Luciq.** Crash Reporting (dual handlers).

**Style inference rules.**
- Presence at all → **legacy stack; team likely planning migration**. Flag as "App Center retired in 2025 — Luciq Crash Reporting is a natural replacement."

---

## 8. Instabug (legacy SDK)

**Family.** Full-stack — legacy predecessor of Luciq.

**Detection patterns.**
| Platform | Manifest | Init signature |
|---|---|---|
| iOS | `Instabug` pod or SPM | `Instabug.start(withToken:invocationEvents:)` |
| Android | `com.instabug.library:instabug` | `new Instabug.Builder(...).build()` |
| React Native | `instabug-reactnative` | `Instabug.start(token, ...)` |
| Flutter | `instabug_flutter` | `Instabug.start(token, ...)` |

**Coverage cells.** Crashes ✓ · Hangs/ANR ✓ · APM ✓ · Network logging ✓ · Session Replay ✓ · Bug Reports ✓ · Surveys ✓ · Ratings ✓

**Conflicts with Luciq.** Full overlap — running both wastes capture and creates ambiguous duplicate reports.

**Handling.** Detecting Instabug means `luciq-onboard` is the wrong skill. **Route the user to `luciq-migrate` and stop.** Do not run the rest of the onboarding flow until the migration is complete — recommendations against an Instabug baseline will be misleading.

---

## 9. UXCam

**Family.** Session replay / UX-leaning.

**Detection patterns.**
| Platform | Manifest | Init signature |
|---|---|---|
| iOS | `UXCam` via SPM / pod | `UXCam.start(with: configuration)` |
| Android | `com.uxcam:uxcam` | `UXCam.startWithConfiguration(...)` |
| React Native | `react-native-ux-cam` | `RNUxcam.startWithConfiguration(...)` |

**Config keys to extract.**
- `userAppKey`
- `enableAutomaticScreenNameTagging`
- `enableImprovedScreenCapture`
- Privacy/occlusion: `occludeAllTextFields`, `occludeAllTextView`, view-tagging patterns
- Sample / session selection rate

**Coverage cells.** Crashes – · Hangs/ANR – · APM – · Network logging – · Session Replay ✓ · Bug Reports – · Surveys – · Ratings –

**Conflicts with Luciq.** Session Replay (two replay capturers running simultaneously is wasteful and may produce inconsistent privacy handling).

**Style inference rules.**
- `occludeAllTextFields: true` → **privacy-conservative — mirror in Luciq replay masking**.
- Low sample rate → **low sampling budget**.

---

## 10. Smartlook

**Family.** Session replay / UX-leaning.

**Detection patterns.**
| Platform | Manifest | Init signature |
|---|---|---|
| iOS | `Smartlook` pod | `Smartlook.instance.preferences.projectKey = ...` then `Smartlook.instance.start()` |
| Android | `com.smartlook.sdk:smartlook` | `Smartlook.getInstance().start()` |
| React Native | `smartlook-react-native-wrapper` | `Smartlook.setProjectKey(...)` then `Smartlook.start()` |

**Config keys to extract.**
- Project key presence
- `eventTracking`, `interactionTracking`
- Sensitive-view masking patterns (`Smartlook.registerBlacklistedView(...)`)
- Sample rate / session selection

**Coverage cells.** Same as UXCam (replay only).

**Conflicts with Luciq.** Session Replay.

**Style inference rules.** Same patterns as UXCam.

---

## 11. MetricKit (iOS system-native)

**Family.** System-native — complement, not competitor.

**Detection patterns.**
- Source contains `import MetricKit` and `MXMetricManager.shared.add(_:)`.
- Conformance to `MXMetricManagerSubscriber`.

**Config keys to extract.**
- Which payload types are processed: `MXCPUMetric`, `MXMemoryMetric`, `MXHangDiagnostic`, `MXCrashDiagnostic`, `MXAppLaunchMetric`, etc.
- Whether the payload is **actually processed** (uploaded somewhere) or **dropped silently** — easy to subscribe and forget.

**Coverage cells.** Crashes ✓ (system) · Hangs/ANR ✓ · APM ✓ (CPU, memory, launch) · Network logging – · Session Replay – · Bug Reports – · Surveys – · Ratings –

**Conflicts with Luciq.** None — MetricKit is system-provided, complements any SDK. Do not frame as a competitor.

**Style inference rules.**
- Payloads processed → **observability-mature team** (they're using OS-level diagnostics).
- Payloads dropped → **opportunity** (suggest forwarding to Luciq as custom logs for richer crash context).

---

## Dev-only tools (detect, exclude from competitor framing)

These are debug/dev tools, not observability. If detected, list them in the profile under `dev_only_flagged` but **never** treat as competitors and never propose to replace them.

- **iOS:** FLEX, Reveal, Pulse (logging-only), Lookin.
- **Android:** DoraemonKit, LeakCanary, Stetho (deprecated), Chucker.

---

## Conflict detection (computed over the profile, same pass)

After per-SDK detection completes, run these checks. The output feeds Phase 2's conflict recap.

| Check | Trigger | Severity |
|---|---|---|
| **Dual crash handler** | ≥2 SDKs with crash coverage that own signal handlers (Sentry, Crashlytics, Bugsnag, Embrace, New Relic, Datadog, App Center) | **High** |
| **Replay collision** | ≥2 active replay capturers (UXCam, Smartlook, Sentry replay, Datadog session replay, Embrace) | **High** |
| **ANR detector race** (Android) | ≥2 SDKs with ANR detection | **High** |
| **Network interceptor stack** | ≥2 SDKs swizzling/intercepting `URLSession` / `OkHttp` | **Medium** |
| **Lifecycle swizzling overlap** (iOS) | ≥2 SDKs swizzling `UIApplication` lifecycle | **Medium** |
| **Shelf-ware** | Manifest match but no init call in source | **Low** |
| **Deprecated SDK** | App Center detected | **Low** |

High and medium severity conflicts go in Phase 2's recap, framed as "independent of Luciq, this is something you might want to look at." Low severity goes into the handoff doc only.

---

## Detection workflow (deterministic, one pass per SDK)

For each SDK in this file:

1. Run the **manifest grep** in the platform-appropriate file(s). If no match, the SDK is not present — skip.
2. If manifest match, run the **init grep** in source. If no match, classify as **shelf-ware** and stop. Do not extract config (there is none to read).
3. If both manifest and init match, run the **config artifact** check. Presence reinforces confidence; absence is OK for SDKs configured inline.
4. **Extract config keys** at the init site using regex-with-context or a small AST pass. For chained `.options { }` blocks in Swift/Kotlin, scope the read to the matched block; don't read past it.
5. Apply the **style inference rules** to produce a one-line style string.
6. Apply the **conflict rules** during the cross-SDK pass.

Detection is 100% deterministic — no LLM step. The inference rules above are simple boolean logic. Reasoning is only used in Phase 3 to map the resulting coverage matrix to a per-product recommendation, and that step reads the structured profile, not raw config.
