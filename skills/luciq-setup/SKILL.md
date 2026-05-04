---
name: luciq-setup
description: Use when the user asks to add, install, set up, integrate, or initialize the Luciq mobile observability SDK in an iOS, Android, Flutter, React Native, or Kotlin Multiplatform project. Triggers include phrases like "add Luciq", "install Luciq SDK", "set up Luciq", "initialize Luciq", or pasting an empty mobile project and asking to wire Luciq. First-time integration only.
---

# Luciq SDK Installation

End-to-end first-time integration of the Luciq mobile observability SDK in a mobile project. Drive every API decision off the canonical platform integration guides linked below. The SDK evolved through the Instabug-to-Luciq rebrand, so any signature memorized in this skill may be stale; always verify against the live guide before applying edits.

## When NOT to use this skill

This skill is for first-time SDK integration. Hand off to a sibling skill for any of the following:

- Upgrading an already-integrated Luciq SDK between versions, or migrating from the legacy Instabug SDK, use `luciq-migrate`.
- Investigating a crash, hang, regression, user-reported bug, or rating drop, use `luciq-debug`.
- Looking up an API signature without installing anything, navigate the live integration guides directly (URLs in the workflow below).

If the user's request fits any of the above, STOP and route them to the right skill rather than running this one.

## Canonical sources of truth

YOU MUST verify SDK API signatures, package names, and MCP transport URLs against these live guides before applying edits. Hardcoded values in this file are illustrative and may be stale.

| Concern | Source |
| --- | --- |
| iOS install + init | https://docs.luciq.ai/ios/setup-luciq-for-ios/integrate-luciq-on-ios/luciq-ai-ios-guide |
| Android install + init | https://docs.luciq.ai/android/set-up-luciq-for-android/integrate-luciq-on-android/luciq-ai-android-guide |
| Flutter, React Native, KMP | the platform's setup space at https://docs.luciq.ai |
| MCP server config | https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server/setup-by-ide |
| App tokens (when authenticated) | Luciq MCP `list_applications` |

## Workflow checklist

Track every step. STOP on any failed step. Do not continue past a broken state.

```
Setup Progress:
- [ ] 1. Detect platform
- [ ] 2. Acquire app token
- [ ] 3. Run per-platform recipe (deps + init)
- [ ] 4. Configure invocation
- [ ] 5. Configure auto-masking
- [ ] 6. Wire user identification
- [ ] 7. Bootstrap Luciq MCP server
- [ ] 8. Bootstrap Luciq CLI (optional, for symbol upload)
- [ ] 9. Smoke build
- [ ] 10. Hand off summary
```

## 1. Detect platform

Run a single non-recursive Glob at workspace root: `{pubspec.yaml,package.json,*.xcodeproj,*.xcworkspace,build.gradle,build.gradle.kts,shared/build.gradle.kts}`.

Apply the rules below in this exact order. First match wins. Cross-platform projects contain native subfolders (`ios/Runner.xcodeproj`, `android/build.gradle`), so root-level markers MUST take priority over those.

1. Root has `pubspec.yaml` -> Flutter (skip iOS/Android subdirs even if present).
2. Root has `package.json` containing `"react-native"` in `dependencies` -> React Native.
3. Root has `shared/build.gradle.kts` with `kotlin("multiplatform")` -> KMP.
4. Root has `*.xcworkspace` or `*.xcodeproj` (and none of the above) -> iOS.
5. Root has `build.gradle` or `build.gradle.kts` (and none of the above) -> Android.

If two or more rules match unexpectedly (for example, both `pubspec.yaml` and a top-level `*.xcodeproj` outside `ios/`), STOP and ask the user to disambiguate. Do not guess.

If no rule matches (empty repo, unusual layout, or a project where the entry point lives in a non-standard subdirectory), STOP and ask the user which platform they're targeting and where the project root lives. Do not assume — silently picking a platform here corrupts every downstream step.

## 2. Acquire app token

Resolve the token in this order:

1. Read from the Luciq MCP server if available: `list_applications` returns tokens for apps the authenticated user can see.
2. Read from environment (`LUCIQ_APP_TOKEN`).
3. Prompt the user.

NEVER commit the token inline. Use a build-time injection, an env var, or a gitignored secrets file. Tokens leak via git history, which is irreversible.

## 3. Per-platform recipe

YOU MUST verify the exact init signature, package name, and Gradle plugin name for the detected platform against the live integration guide above before applying. APIs evolved through the Instabug-to-Luciq rebrand. The recipes below name the files to edit, not authoritative signatures.

### iOS
1. Edit `Podfile`: add the Luciq pod to the main target.
2. Run `pod install` after user confirmation.
3. Edit `AppDelegate.swift` (or `.m`): import Luciq and call the start API in `application(_:didFinishLaunchingWithOptions:)`.

### Android
1. Edit `app/build.gradle(.kts)`: add the Luciq dependency. Apply the Luciq Gradle plugin if the live guide says so.
2. Sync Gradle.
3. Edit the `Application` subclass `onCreate` to construct and start Luciq.

### Flutter
1. Edit `pubspec.yaml`: add the `luciq_flutter` package per the live guide.
2. Run `flutter pub get`.
3. Edit `lib/main.dart`: call `Luciq.start(...)` before `runApp(...)`.

### React Native
1. Verify the exact package name on the live guide, then `npm install` or `yarn add` it.
2. iOS host app: `cd ios && pod install`.
3. Android host app: verify autolinking.
4. Edit the JS entry to call the start method early in app lifecycle.

### KMP
1. Edit `shared/build.gradle.kts` for shared deps per the live guide.
2. Run the iOS recipe for the iOS app target.
3. Run the Android recipe for the Android app target.

## 4. Configure invocation

Default to shake gesture plus screenshot. Offer alternatives: floating button, two-finger swipe, or programmatic-only. Apply the user's choice.

## 5. Configure auto-masking

Goal: identify likely-sensitive UI views and configure SDK-side masking. A naive substring grep produces false positives (validators, comments, test fixtures), so the search must be narrowly scoped and every match must be user-confirmed.

1. Grep the platform's UI source files only (`*.swift`, `*.kt`, `*.dart`, `*.tsx`, `*.jsx`) for these identifier-shaped strings: `password`, `email`, `cardNumber`, `ssn`, `cvv`, `pin`, `dob`, `iban`.
2. Filter out matches in `*test*`, `*spec*`, `*mock*`, `*fixture*` paths, validator/regex utilities, and anything under `node_modules`, `Pods/`, or `build/`.
3. Show the filtered match list with `file:line` for each. Get per-match confirmation. Do not apply masking rules in bulk.
4. Verify the masking API signature for the detected platform on the live guide. The masking API has differed across platforms and changed across SDK versions; do not hardcode it.
5. Apply masking config only for confirmed matches.

Also configure network-log redaction: sensitive headers (Authorization, Cookies) and body fields (password, token).

## 6. Wire user identification

Find login and logout flows. Add `identifyUser(...)` and the corresponding sign-out call so reports tie back to your users. Verify the exact identification API on the live guide.

## 7. Bootstrap Luciq MCP server

Add the Luciq MCP server to `~/.claude.json` (user-global) or `.mcp.json` (project). Confirm with the user where to write.

```json
{
  "mcpServers": {
    "luciq": {
      "type": "http",
      "url": "https://api.luciq.ai/api/mcp"
    }
  }
}
```

YOU MUST verify the MCP server URL and transport type against https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server/setup-by-ide before writing the config. Both have evolved across releases.

After writing, prompt the user to restart their agent (Claude Code, Cursor, Codex, or other supported client) and complete the OAuth flow. Once authenticated, Luciq MCP tools become available qualified as `luciq:<tool_name>` (for example, `luciq:list_crashes`).

## 8. Bootstrap the Luciq CLI (optional)

If the project will upload symbol artifacts (dSYMs, ProGuard or R8 mapping files, source maps, or split-debug-info) to Luciq for symbolication of obfuscated frames, install the Luciq CLI.

YOU MUST verify the install command, supported platforms, and exact upload subcommand on the live integration guide for the user's platform. The CLI's distribution channel and command surface have changed across releases; do not hardcode an install command here.

Store credentials via environment variables (`LUCIQ_APP_TOKEN` plus any per-platform secrets the live guide names). NEVER commit credentials inline.

## 9. Smoke build

| Platform | Command |
| --- | --- |
| iOS | `xcodebuild -workspace <Workspace>.xcworkspace -scheme <Scheme> build` |
| Android | `./gradlew :app:assembleDebug` |
| Flutter | `flutter build apk --debug` |
| React Native (Android) | `npx react-native run-android` |
| React Native (iOS) | `npx react-native run-ios` |
| KMP | run both Android and iOS builds |

Deriving `<Workspace>` and `<Scheme>` for iOS and RN-iOS:

- `<Workspace>`: the `.xcworkspace` filename (without extension) in the project's `ios/` directory (or repo root for native iOS). If only an `.xcodeproj` exists, use `-project Foo.xcodeproj` instead of `-workspace`.
- `<Scheme>`: derive by running `xcodebuild -list -workspace <Workspace>.xcworkspace` and picking the app scheme. Usually matches the workspace name. For RN, the scheme typically matches the app's display name in `app.json`.
- If multiple workspaces or schemes exist, STOP and ask the user which to build. Do not guess.

STOP on build failure. NEVER claim success on a broken build.

## 10. Hand off

Print:
- File where init was added.
- Invocation event configured.
- Masking rules applied (with file:line for each).
- User identification call sites.
- MCP / CLI wired status.
- A test command (for example, "shake the device or simulator to invoke Luciq").
- Pointers: `luciq-debug` for crash investigation, `luciq-migrate` for moving off the legacy Instabug SDK or upgrading between Luciq versions.

## Style

- ALWAYS show diffs before applying code edits.
- ALWAYS confirm before running `pod install`, gradle syncs, or build commands.
- Verify SDK API signatures from the live integration guide. Do not hardcode them in this skill.

## Red Flags - STOP and surface to the user

If you catch yourself thinking any of these, you are about to ship a broken integration. STOP, surface to the user, do not proceed:

- "The build failed but the SDK is installed, so it's probably fine." It isn't. A failing build means a broken integration. Report the failure verbatim.
- "I skipped checking the live guide because the docs probably haven't changed." That's how you ship a stale signature. Always verify.
- "I hardcoded the init signature from this file, it looked right." This file is illustrative, not authoritative. The live guide is the source of truth.
- "I committed the app token inline because it's just for local testing." Tokens leak via git history. Use env injection or a gitignored secrets file.
- "I auto-applied the masking rules without showing the user the matches." False positives are likely. Per-match confirmation is mandatory.
- "`pod install` or `gradle sync` had warnings but the build went green." Warnings about Luciq specifically are not cosmetic. Read them, surface them.
- "Two platform markers matched but I picked the obvious one." If the workspace is ambiguous, ask. Cross-platform projects break this assumption routinely.

The pattern: every shortcut here trades "looks done" for "actually works." The skill's job is to actually work.
