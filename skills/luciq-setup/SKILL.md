---
name: luciq-setup
description: Install and configure the Luciq mobile observability SDK in any iOS, Android, Flutter, React Native, or KMP project. Auto-detects platform, edits build files (Podfile, build.gradle, pubspec.yaml, package.json), inserts the SDK init call at the right entry point, configures invocation events and auto-masking, bootstraps Luciq MCP authentication and the luciq_cli, and runs a smoke build. Use when the user says "add Luciq", "install Luciq SDK", "set up Luciq", or "initialize Luciq".
---

<!--
Triggers (things the user might say):
- "add Luciq" / "add the Luciq SDK"
- "install Luciq SDK" / "install Luciq in this project"
- "set up Luciq" / "set up Luciq for [iOS / Android / Flutter / RN / KMP]"
- "initialize Luciq"
- "integrate Luciq into our app"
-->

# Luciq SDK Installation

End-to-end first-time integration of the Luciq SDK in a mobile project.

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

Single Glob at workspace root: `{pubspec.yaml,package.json,*.xcodeproj,*.xcworkspace,build.gradle,build.gradle.kts,shared/build.gradle.kts}`. First match:

- `pubspec.yaml` → Flutter
- `package.json` with `react-native` → React Native
- `shared/build.gradle.kts` with `kotlin("multiplatform")` → KMP
- `*.xcodeproj` / `*.xcworkspace` only → iOS
- `build.gradle*` only → Android

Confirm with the user if ambiguous.

## 2. Acquire app token

Check env (`LUCIQ_APP_TOKEN`). Otherwise ask the user. NEVER commit the token inline — use a build-time injection or a secrets file.

## 3. Per-platform recipe

ALWAYS verify the exact init signature against `luciq-docs` before applying — Luciq's APIs evolved through the Instabug→Luciq rebrand.

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
1. Run `npm install` / `yarn add` for the Luciq RN package (verify exact name via `luciq-docs`)
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

Search the codebase for likely sensitive views: `password`, `email`, `cardNumber`, `ssn`, `cvv`. Suggest masking rules for matches. Apply on confirmation.

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

Verify URL and transport against `luciq-docs` (these may evolve).

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
- DO NOT hardcode SDK API signatures — verify via `luciq-docs`.
