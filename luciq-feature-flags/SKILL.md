---
name: luciq-feature-flags
description: Tag a user with a Luciq feature flag enrollment so crashes, bug reports, App Performance, and sessions get correlated with that flag/variant. This is an attribution layer — Luciq does NOT decide whether to run a code path. The runtime decision still comes from the engineer's existing flag provider (LaunchDarkly, in-house service, remote config). This skill inserts `Luciq.addFeatureFlag(...)` (or platform equivalent) at the exposure point, optionally next to an existing flag-provider call. Use when the user says "tag this user with the [X] flag", "track that this user is in the [X] experiment", "correlate crashes with the [X] flag", or "wire LaunchDarkly flag exposures to Luciq".
---

<!--
Triggers (things the user might say):
- "tag this user with the [flag] feature flag"
- "track that this user is in the [experiment / variant]"
- "correlate crashes / bugs / sessions with the [X] flag"
- "record [X] flag exposure in Luciq"
- "wire LaunchDarkly (or Optimizely / ConfigCat / Firebase Remote Config) into Luciq"
- "remove the [X] flag from this user" / "clear all Luciq feature flags"

NOTE: Luciq feature flags are NOT a kill-switch. If the user asks "wrap [code] in a feature flag" or "add a kill-switch", that decision must come from their actual flag provider — Luciq only records the enrollment. Clarify before acting.
-->

# Luciq Feature Flag Tagging

Record a user's feature-flag / variant enrollment in Luciq so observability data is correlated with the flag.

## Mental model — read this first

Luciq feature flags are **attribution tags**, not runtime gates.

- Luciq does NOT have an `isEnabled(...)` API.
- The decision of which code path to run still comes from the engineer's existing flag provider (LaunchDarkly, Optimizely, ConfigCat, Firebase Remote Config, an in-house service).
- This skill's job: insert a `Luciq.addFeatureFlag(...)` call at the **exposure point** — the same line where the engineer reads the flag value — so Luciq can tag every crash, bug report, and session that follows with `flag=X, variant=Y`.

If the user asks to "wrap code in a feature flag" or "add a kill-switch", surface this distinction and ask which flag provider owns the decision. NEVER invent a Luciq evaluation API.

## Workflow

1. Detect platform
2. Identify flag name, variant (optional), and exposure point
3. Look up the platform's exact Luciq API via `luciq-docs`
4. Decide insertion point (standalone tag vs. alongside an existing provider call)
5. Show diff
6. Apply on confirmation
7. Remind about constraints and removal

## 1. Detect platform

Single Glob: `{pubspec.yaml,package.json,*.xcodeproj,*.xcworkspace,build.gradle,build.gradle.kts,shared/build.gradle.kts}`. First match wins.

## 2. Identify flag, variant, and exposure point

Capture from the user prompt:
- **Flag name** (e.g. `pricing_v2`) — required, ≤70 chars, case-insensitive
- **Variant** (e.g. `treatment_a`) — optional, ≤70 chars
- **Exposure point** — file/line where the flag is read (or where the user wants the tag to live)

If any of these are missing, ASK. NEVER invent a flag name or variant.

## 3. Look up the platform API via `luciq-docs`

The shape differs per platform. Verify against the live docs before applying — APIs evolved through the Instabug→Luciq rebrand.

Reference (verified on docs.luciq.ai at the time of writing — re-check via `luciq-docs`):

**iOS — Swift:**
```swift
Luciq.add(featureFlag: FeatureFlag(name: "pricing_v2"))
Luciq.add(featureFlag: FeatureFlag(name: "pricing_v2", variant: "treatment_a"))
Luciq.removeFeatureFlag("pricing_v2")
Luciq.removeAllFeatureFlags()
```

**iOS — Objective-C:**
```objc
[Luciq addFeatureFlag:[[LCQFeatureFlag alloc] initWithName:@"pricing_v2" variant:@"treatment_a"]];
[Luciq removeFeatureFlag:@"pricing_v2"];
[Luciq removeAllFeatureFlags];
```

**Android — Kotlin:**
```kotlin
Luciq.addFeatureFlag(LCQFeatureFlag("pricing_v2"))
Luciq.addFeatureFlag(LCQFeatureFlag("pricing_v2", "treatment_a"))
```

**Flutter — Dart:**
```dart
Luciq.addFeatureFlags([FeatureFlag(name: 'pricing_v2', variant: 'treatment_a')]);
Luciq.removeFeatureFlags(['pricing_v2']);
Luciq.clearAllFeatureFlags();
```

**React Native — JS/TS:**
```js
Luciq.addFeatureFlags([{ name: 'pricing_v2', variant: 'treatment_a' }]);
```

**KMP:** route to the appropriate platform source set (`iosMain`/`androidMain`); the API is the platform's native API, not a shared one.

## 4. Insertion point

Two patterns:

**A. Standalone tag** — the user already enrolled the user in an experiment elsewhere and just wants Luciq to know:
```kotlin
Luciq.addFeatureFlag(LCQFeatureFlag("pricing_v2", "treatment_a"))
```
Insert it as early as possible after enrollment is known (e.g. session start, post-login, after remote config fetch).

**B. Alongside an existing provider call** — preferred. Insert the Luciq tag on the same line / block where the engineer evaluates the flag:
```kotlin
val variant = launchDarkly.stringVariation("pricing_v2", "control")
Luciq.addFeatureFlag(LCQFeatureFlag("pricing_v2", variant))   // tag Luciq with what we just resolved
if (variant == "treatment_a") { ... }
```

ASK the user which pattern fits if it isn't obvious from context.

## 5. Edit and apply

- Show the diff before applying.
- Preserve indentation and surrounding style.
- For multi-file targets: batch all diffs, show all, apply on a single confirmation.
- DO NOT introduce a flag name or variant the user didn't specify.

## 6. Remind about constraints and removal

After applying, surface these constraints (they bite in production):

- **70-char limit** on flag names and variant names — anything longer is silently ignored by the SDK.
- **Case-insensitive** flag names.
- **200 flags per session cap.** Beyond that, additional flags are dropped.
- **One variant per multivariant flag per session** — if the same flag is added with different variants in one session, only the **last** is sent to the backend.
- **Persistence across sessions.** Flags are NOT cleared automatically and `logout` does NOT clear them. If the user signs out and a different user signs in, the old flags will keep tagging the new user's data unless explicitly removed.
- **Removal is the engineer's responsibility.** Surface `removeFeatureFlag(...)` / `clearAllFeatureFlags()` for logout flows or experiment end.

## 7. Hand off

Mention briefly:
- Where flag-tagged data shows up in the Luciq dashboard (filter Bug Reports / Crashes / APM by feature flag).
- That the LaunchDarkly integration page on docs.luciq.ai shows the canonical "tag at evaluation" pattern if the user is on LaunchDarkly.

## Style

- DO NOT pretend Luciq has a runtime gating API. It doesn't.
- DO NOT invent a flag name or variant — ASK.
- DO NOT apply edits without showing the diff.
- ALWAYS verify the platform's exact method shape via `luciq-docs` before editing.
- ALWAYS surface the 70-char / 200-per-session / persistence / logout constraints — they are easy to miss and cause real bugs.
