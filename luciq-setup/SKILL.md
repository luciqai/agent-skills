---
name: luciq-setup
description: Use when the user asks to add, install, set up, or initialize the Luciq mobile observability SDK in an iOS, Android, Flutter, React Native, or KMP project. First-time integration only — for SDK upgrades or Instabug→Luciq migration use luciq-migrate.
---

# Luciq SDK Installation

End-to-end first-time integration of the Luciq SDK in a mobile project.

**REQUIRED SUB-SKILL:** This skill MUST invoke `luciq-docs` to verify every SDK API signature, package name, and MCP transport URL before applying edits. Hardcoded values in this file are illustrative only — they may be stale after SDK releases. Treat `luciq-docs` as the source of truth, not this file.

## Workflow checklist

Copy this and check off as you go:

```
Setup Progress:
- [ ] 1. Detect platform
- [ ] 2. Acquire app token
- [ ] 3. Run per-platform recipe (deps + init)
- [ ] 4. Configure invocation
- [ ] 5. Configure auto-masking
- [ ] 6. Bootstrap Luciq MCP server
- [ ] 7. Bootstrap luciq_cli (Flutter only)
- [ ] 8. Smoke build
- [ ] 9. Hand off summary
```

STOP on any failed step — do not continue past a broken state.

## 1. Detect platform

Run a non-recursive Glob at workspace root only. Apply rules in this order — first match wins. Cross-platform projects contain native subfolders (`ios/Runner.xcodeproj`, `android/build.gradle`), so root-level markers MUST take priority over those.

1. Root has `pubspec.yaml` → **Flutter** (skip iOS/Android subdirs even if present)
2. Root has `package.json` containing `"react-native"` in `dependencies` → **React Native**
3. Root has `shared/build.gradle.kts` with `kotlin("multiplatform")` → **KMP**
4. Root has `*.xcworkspace` or `*.xcodeproj` (and none of the above) → **iOS**
5. Root has `build.gradle` or `build.gradle.kts` (and none of the above) → **Android**

If 2+ rules match unexpectedly (e.g. both `pubspec.yaml` and a top-level `*.xcodeproj`), STOP and ask the user to disambiguate — do not guess.

## 2. Acquire app token

Check env (`LUCIQ_APP_TOKEN`). Otherwise ask the user. NEVER commit the token inline — use a build-time injection or a secrets file.

## 3. Per-platform recipe

**REQUIRED:** call `luciq-docs` to verify the exact init signature and package name for the detected platform before applying — Luciq's APIs evolved through the Instabug→Luciq rebrand and any signature in this file may be stale.

### iOS
1. Edit `Podfile`: add `pod 'Luciq'` to the main target
2. Run `pod install` (confirm with user first)
3. Edit `AppDelegate.swift` (or `.m`) — import Luciq and call the start API in `application(_:didFinishLaunchingWithOptions:)`

### Android
1. Edit `app/build.gradle(.kts)`: add the Luciq dependency, apply the Luciq Gradle plugin if the docs say so
2. Sync Gradle
3. Edit the `Application` subclass `onCreate` to construct and start Luciq

### Flutter
1. Edit `pubspec.yaml`: add `luciq_flutter`
2. Run `flutter pub get`
3. Edit `lib/main.dart` — call `Luciq.start(...)` before `runApp(...)`

### React Native
1. **REQUIRED:** call `luciq-docs` to fetch the exact RN package name, then run `npm install` / `yarn add` for it
2. iOS: `cd ios && pod install`
3. Android: verify autolinking
4. Edit JS entry to call the start method early in app lifecycle

### KMP
1. Edit `shared/build.gradle.kts` for shared deps
2. Run iOS recipe for the iOS app target
3. Run Android recipe for the Android app target

## 4. Configure invocation

Default: shake gesture. Ask if user prefers floating button, two-finger swipe, or programmatic-only.

## 5. Configure auto-masking

Goal: identify likely-sensitive UI views and configure SDK-side masking. A naïve substring grep produces false positives (validators, comments, test fixtures), so the search must be narrowly scoped and every match must be user-confirmed.

1. Grep for sensitive identifiers — but only in the platform's UI source files (`*.swift`, `*.kt`, `*.dart`, `*.tsx`, `*.jsx`), and only as identifiers, not free text in comments or string literals: `password`, `email`, `cardNumber`, `ssn`, `cvv`, `pin`, `dob`, `iban`.
2. Filter out matches in: `*test*`, `*spec*`, `*mock*`, `*fixture*` paths; validator/regex utilities; and any path under `node_modules`, `Pods/`, `build/`.
3. Show the user the filtered match list with file:line for each. Get **per-match** confirmation — do not apply masking rules in bulk.
4. **REQUIRED:** call `luciq-docs` to fetch the masking API signature for the detected platform. Do NOT hardcode — the API has differed across platforms and changed across SDK versions.
5. Apply masking config only for confirmed matches.

## 6. Bootstrap Luciq MCP server

Add the Luciq MCP server to `~/.claude.json` (user-global) or `.mcp.json` (project) — confirm with user where to write:

```json
{
  "mcpServers": {
    "luciq": {
      "transport": "http",
      "url": "https://mcp.luciq.ai"
    }
  }
}
```

**REQUIRED:** call `luciq-docs` to verify the MCP server URL and transport type before writing the config — both may have evolved since this file was last updated.

After writing, prompt the user to restart Claude Code and complete the OAuth flow. Once authenticated, Luciq MCP tools become available qualified as `luciq:<tool_name>` (e.g. `luciq:list_crashes`).

## 7. Bootstrap luciq_cli (Flutter only)

```bash
dart pub global activate luciq_cli
```

Confirm Dart's global bin directory is on `PATH`. Add credentials to `local.properties` or env (`LUCIQ_APP_TOKEN`, `LUCIQ_API_KEY`).

## 8. Smoke build

| Platform | Command |
|---|---|
| iOS | `xcodebuild -workspace <Workspace>.xcworkspace -scheme <Scheme> build` |
| Android | `./gradlew :app:assembleDebug` |
| Flutter | `flutter build apk --debug` |
| React Native (Android) | `npx react-native run-android` |
| React Native (iOS) | `npx react-native run-ios` |
| KMP | run both Android and iOS builds |

**Deriving `<Workspace>` and `<Scheme>` for iOS / RN-iOS:**

- `<Workspace>`: the `.xcworkspace` filename (without extension) in the project's `ios/` directory (or repo root for native iOS). If only an `.xcodeproj` exists, use `-project Foo.xcodeproj` instead of `-workspace`.
- `<Scheme>`: run `xcodebuild -list -workspace <Workspace>.xcworkspace` and pick the app scheme — usually matches the workspace name. For RN, the scheme typically matches the app's display name in `app.json`.
- If multiple workspaces or schemes exist, STOP and ask the user which to build — do not guess.

STOP if the build fails. NEVER claim success on a broken build.

## 9. Hand off

Print:
- File where init was added
- Invocation event configured
- MCP / CLI wired status
- Test command (e.g. *"shake the device or simulator to invoke Luciq"*)
- Pointers: `luciq-debug` for crash investigation, `luciq-release-check` for release health

## Style

- ALWAYS show diffs before applying code edits.
- ALWAYS confirm before running `pod install`, gradle syncs, build commands.
- DO NOT hardcode SDK API signatures — **REQUIRED:** call `luciq-docs` to verify each one.

## Red Flags — STOP and surface to the user

If you catch yourself thinking any of these, you are about to ship a broken integration. STOP, surface to the user, do not proceed:

- "The build failed but the SDK is installed, so it's probably fine" → it isn't. A failing build means a broken integration. Report the failure verbatim.
- "I skipped calling `luciq-docs` because the docs probably haven't changed" → that's how you ship a stale signature. Always verify.
- "I hardcoded the init signature from this file, it looked right" → this file is illustrative, not authoritative. `luciq-docs` is the source of truth.
- "I committed the app token inline because it's just for local testing" → tokens leak via git history. Use env injection or a gitignored secrets file.
- "I auto-applied the masking rules without showing the user the matches" → false positives are likely. Per-match confirmation is mandatory.
- "`pod install` / `gradle sync` had warnings but the build went green" → warnings about Luciq specifically are not cosmetic. Read them, surface them.

The pattern: every shortcut here trades "looks done" for "actually works." The skill's job is to actually work.
