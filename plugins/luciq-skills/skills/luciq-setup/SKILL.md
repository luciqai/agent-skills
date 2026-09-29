---
name: luciq-setup
description: Use when the user asks to add, install, set up, integrate, or initialize the Luciq mobile observability SDK in an iOS, Android, Flutter, React Native, or Kotlin Multiplatform project. Triggers include phrases like "add Luciq", "install Luciq SDK", "set up Luciq", "initialize Luciq", or pasting an empty mobile project and asking to wire Luciq. First-time integration only — for SDK upgrades or migration from the legacy Instabug SDK use luciq-migrate.
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
| Flutter install + init | https://docs.luciq.ai/flutter/setup-luciq-for-flutter/integrating-luciq |
| React Native install + init | https://docs.luciq.ai/react-native/setup-luciq-for-react-native/integrate-luciq-on-react-native |
| KMP install + init | https://docs.luciq.ai/kmp/setup-luciq-for-kmp/integrating-luciq |
| MCP server config | https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server/setup-by-ide |
| App tokens (when authenticated) | Luciq MCP `list_applications` |

### Check symbols against the SDK, not only the docs

The live guides are the source of truth for *what* to do, but a guide snippet can be wrong: the iOS AI guide has shipped pseudo-code (`IF config_mode == default: … ELSE: …`) inside a Swift block, next to a method name that doesn't exist. Before writing any SDK call beyond the start call, confirm the symbol exists in the installed SDK:

| Platform | Where the public API lives after install |
| --- | --- |
| iOS (SPM) | `find ~/Library/Developer/Xcode/DerivedData -maxdepth 8 -type d -path '*SourcePackages/artifacts/luciq-ios-sdk/*/LuciqSDK.xcframework/ios-arm64'` → `Headers/*.h` and `Modules/LuciqSDK.swiftmodule/*.swiftinterface` |
| iOS (CocoaPods) | `Pods/Luciq/LuciqSDK.xcframework/ios-arm64/…` (same layout) |
| Flutter | `~/.pub-cache/hosted/pub.dev/luciq_flutter-*/lib/` |
| React Native | `node_modules/@luciq/react-native/` (`*.d.ts` / `src/`) |
| Android / KMP | no quick grep — the smoke build in step 9 is the check |

`grep -r "<methodName>"` there. No hit means the name is wrong: search the guide page for the real one, don't guess a variant. On iOS, headers use Objective-C names — `LCQNetworkLogger` is `NetworkLogger` in Swift, `setRequestObfuscationHandler:` is `setRequestObfuscationHandler(_:)`.

If a guide snippet is not valid code in the target language (prose inside a code block, unfilled placeholders), treat it as prose. Do not fill in the gaps and ship the rest verbatim.

## Workflow checklist

Track every step. STOP on any failed step. Do not continue past a broken state.

```
Setup Progress:
- [ ] 1. Detect platform
- [ ] 2. Acquire app token
- [ ] 3. Run per-platform recipe (deps + init)
- [ ] 4. Configure invocation
- [ ] 5. Configure auto-masking + privacy disclosure
- [ ] 6. Wire user identification
- [ ] 7. Bootstrap Luciq MCP server
- [ ] 8. Symbol upload → hand off to `luciq-symbolicate`
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

1. Try the Luciq MCP server: `list_applications` returns tokens for apps the authenticated user can see. This works only if Luciq MCP is already authenticated in the user's agent from a previous `luciq-setup` run on another project — for genuine first-time setups, this call will fail with a tool-not-found error and you should fall through to step 2 below. Do not attempt to bootstrap MCP here; that is step 7.
2. Read from environment (`LUCIQ_APP_TOKEN`).
3. Prompt the user.

**Picking from `list_applications`.** Present the result as a numbered list only when it has 10 apps or fewer. Larger accounts return demo apps, test apps and other teams' apps — a list of a hundred tokens is worse than asking. Instead:

- Ask one question: *"Which Luciq app is this — the app name, or paste its token?"*
- Given a name, filter the result you already have (case-insensitive substring) and show only the matches.
- Given a token, look it up in the same result and confirm in one line — *"That token is **<app name>** (<platform>). Using it."* If it isn't there, say so: the token belongs to an app this login can't see, or it has a typo. Ask before shipping with an unconfirmed token.

NEVER commit the token inline. Use a build-time injection, an env var, or a gitignored secrets file. Tokens leak via git history, which is irreversible.

- **iOS:** run `scripts/add_token_config.rb` — gitignored `.xcconfig` → `$(LUCIQ_APP_TOKEN)` in a real `Info.plist` → `Bundle.main`. See `references/ios-token-injection.md`. Do NOT use `INFOPLIST_KEY_<CustomKey>`: Xcode silently drops custom keys, the build stays green, and the token is empty at runtime.

## 3. Per-platform recipe

YOU MUST verify the exact init signature, package name, and Gradle plugin name for the detected platform against the live integration guide above before applying. APIs evolved through the Instabug-to-Luciq rebrand. The recipes below name the files to edit, not authoritative signatures.

### iOS

Verify the recommended install method against the live guide before proceeding — the primary method has changed across SDK versions.

**Swift Package Manager (recommended for all new and existing projects)**

First check whether a `Package.swift` exists at the project root.

*Project has `Package.swift`:*
1. Edit `Package.swift` — add to `dependencies` and to the appropriate target's `dependencies`. Verify the repo URL and version on the live guide:
   ```swift
   // dependencies array:
   .package(url: "<REPO_URL_FROM_LIVE_GUIDE>", from: "<VERSION>"),
   // target dependencies:
   .product(name: "<SPM_PRODUCT_NAME>", package: "luciq-ios-sdk"),
   ```
2. Run `swift package resolve` to fetch.
3. Check the resolved `Package.swift` in DerivedData checkouts to confirm the product name and module name — **they are different**: the SPM product may be `Luciq` while the Swift import is `import LuciqSDK`. Use the module name (from the `.xcframework` contents) for `import`, not the product name.
4. Add the start call at the app's entry point (`AppDelegate`, or an `init()` on the `@main` `App` struct for SwiftUI — see *Entry point* in `references/ios-spm.md`). Verify the exact init signature on the live guide.
5. Edit `Info.plist`: add `NSMicrophoneUsageDescription` and `NSPhotoLibraryUsageDescription`.

*Project is `.xcodeproj`-only (no `Package.swift`):*
Read `references/ios-spm.md` first. **Do not hand-edit `project.pbxproj`** — hand-generated object IDs and missed sections are the most common way this step fails.
1. Ask the user to quit Xcode (one line — see `references/ios-spm.md`, Rule 1). Editing the project while Xcode is open leaves the package unresolved and fails later with `Missing package product 'Luciq'`.
2. Run the bundled script (installs nothing but the `xcodeproj` gem if missing):
   ```bash
   ruby <skill-dir>/scripts/add_spm_package.rb --project <App>.xcodeproj --target <AppTarget> \
     --url https://github.com/luciqai/luciq-ios-sdk --version <LATEST_TAG> --product Luciq
   ```
   SPM product = `Luciq`; Swift import = `import LuciqSDK`. Get `<LATEST_TAG>` from the repo tags (command in the reference).
3. Add the start call at the app's entry point — for a SwiftUI app with no `AppDelegate`, that is an `init()` on the `@main` `App` struct. See *Entry point* in `references/ios-spm.md`. Verify the exact init signature on the live guide.
4. Edit `Info.plist`: add `NSMicrophoneUsageDescription` and `NSPhotoLibraryUsageDescription`. If the project has no `Info.plist` file (`GENERATE_INFOPLIST_FILE = YES`), add them as `INFOPLIST_KEY_…` build settings instead — see *Projects with no `Info.plist` file* in the reference.
5. Tell the user they can reopen Xcode. If Xcode then shows `Missing package product`, the fix is **File → Packages → Resolve Package Versions** — resolution is per DerivedData, so the CLI build passing does not fix an open Xcode window.

**Carthage (alternative — only if SPM is blocked by a project-level constraint)**
1. Edit (or create) `Cartfile` — verify the binary spec URL on the live guide:
   ```
   binary "<SPEC_URL_FROM_LIVE_GUIDE>"
   ```
2. Run `carthage update --use-xcframeworks` after user confirmation.
3. Embed the built `.xcframework` programmatically using the `xcodeproj` Ruby gem:
   ```bash
   gem install xcodeproj   # skip if already installed
   ```
   Then run a Ruby script (adapt `TARGET_NAME` and the `.xcframework` filename to the actual project — check `Carthage/Build/` after step 2):
   ```ruby
   require 'xcodeproj'
   project = Xcodeproj::Project.open(Dir.glob('*.xcodeproj').first)
   target  = project.targets.find { |t| t.name == 'TARGET_NAME' }
   ref     = project.new_file('Carthage/Build/LuciqSDK.xcframework')
   target.frameworks_build_phase.add_file_reference(ref)
   phase   = target.new_shell_script_build_phase('Copy Luciq Frameworks')
   phase.shell_script    = '"$(SRCROOT)/Carthage/Build/carthage" copy-frameworks'
   phase.input_paths    << '$(SRCROOT)/Carthage/Build/LuciqSDK.xcframework'
   project.save
   ```
   Show the diff of `project.pbxproj` before saving.
4. Edit `AppDelegate.swift` (or `.m`): import the module and call the start API. Verify the exact init signature on the live guide.
5. Edit `Info.plist`: add `NSMicrophoneUsageDescription` and `NSPhotoLibraryUsageDescription`.

**CocoaPods (deprecated — avoid for new integrations)**
> ⚠️ The CocoaPods registry becomes read-only on December 2, 2026. Prefer SPM or Carthage. Only use this path if the project already uses CocoaPods and migration is out of scope for this task.
1. Edit `Podfile`: add the Luciq pod to the main target — verify the pod name on the live guide.
2. Run `pod install` and `pod update Luciq` after user confirmation.
3. Follow steps 4–5 above.

### Android

Verify exact dependency coordinates, version, and init signature against the live guide before applying — these change across releases.

1. **Check compile SDK version**: must be ≥ 29. Raise `compileSdkVersion` in `app/build.gradle(.kts)` if needed.
2. **Add the dependency** in `app/build.gradle(.kts)` (verify groupId, artifactId, and latest version on the live guide):
   - Gradle: `implementation 'ai.luciq.library:luciq:<version>'`
   - Maven projects: use the same groupId/artifactId coordinates from the live guide.
3. **Verify dependency resolution** after user confirmation: `./gradlew :app:dependencies` — this triggers Gradle to fetch the new dependency without needing Android Studio. Fix any resolution errors before continuing.
4. **Initialize in the Application subclass** `onCreate` using the Builder pattern (verify exact API on the live guide):
   - Kotlin: `Luciq.Builder(this, "APP_TOKEN").build()`
   - Java: `new Luciq.Builder(this, "APP_TOKEN").build();`
5. **Permissions**: the SDK automatically injects `WAKE_LOCK` and `INTERNET` into `AndroidManifest.xml` — no manual edits needed. Optional permissions for image/video attachments and network monitoring are listed in the live guide.
6. **Android 15+ (API 35)**: if `targetSdkVersion` is 35 or higher, the live guide requires Luciq ≥ 13.4.0 for 16 KB page-size support. Verify the minimum compatible version on the live guide and pin accordingly.

### Flutter

1. **Add dependency** in `pubspec.yaml` (verify the exact package name and version on the live guide):
   ```yaml
   dependencies:
     luciq_flutter:
   ```
2. **Fetch the package**: `flutter packages get`
3. **Import** in the file where you initialize: `import 'package:luciq_flutter/luciq_flutter.dart';`
4. **Initialize** in `initState()` (verify the exact API signature on the live guide):
   ```dart
   Luciq.init(
     token: 'APP_TOKEN',
     invocationEvents: [InvocationEvent.shake, InvocationEvent.floatingButton],
   );
   ```
5. **iOS permissions** — add to `Info.plist` (required for media attachments):
   - `NSMicrophoneUsageDescription`
   - `NSPhotoLibraryUsageDescription`
6. **Android permissions**: auto-injected into `AndroidManifest.xml` — no manual edits needed. Exception: if you enable screenshot invocation, the SDK requests storage permission at app launch (it monitors the screenshots directory).

### React Native

**Requirement:** React Native ≥ 0.60.x. Verify the minimum version on the live guide before proceeding.

1. **Install the package** (verify the exact package name on the live guide):
   - npm: `npm install @luciq/react-native`
   - yarn: `yarn add @luciq/react-native`
2. **iOS native deps**: `cd ios && pod install && cd ..` after user confirmation.
3. **Android**: autolinking handles native wiring automatically — no manual step needed.
4. **Initialize** in `index.js` (verify the exact API signature on the live guide):
   ```js
   import Luciq, { InvocationEvent } from '@luciq/react-native';

   Luciq.init({
     token: 'APP_TOKEN',
     invocationEvents: [InvocationEvent.shake, InvocationEvent.floatingButton],
   });
   ```
5. **iOS permissions** — add these keys to `info.plist` (required for media attachments):
   - `NSMicrophoneUsageDescription`
   - `NSPhotoLibraryUsageDescription`

### KMP

Verify dependency coordinates, version, and init signatures against the live guide — these change across releases.

1. **Add the shared dependency** in `shared/build.gradle.kts` under `commonMain` (get the latest version from Maven Central):
   ```kotlin
   sourceSets {
       commonMain.dependencies {
           api("ai.luciq-library:luciq-kmp:<version>")
       }
   }
   ```
   iOS also requires a separate native LuciqKMP dependency — check the live guide for the exact artifact.

2. **Create a shared config object** in `commonMain` (verify the exact class names and fields on the live guide):
   ```kotlin
   import ai.luciq.kmp.modules.LuciqKmp
   import ai.luciq.kmp.utils.InvocationEvents

   object LuciqDefaults {
       const val APP_TOKEN = "YOUR_TOKEN"
       val invocationEvents = listOf(InvocationEvents.FloatingButton)
   }

   fun initializeLuciq(configuration: LuciqConfiguration) {
       LuciqKmp.init(configuration)
   }
   ```

3. **Android entry point** — call as early as possible in the Application class, passing the `Application` instance:
   ```kotlin
   val configuration = LuciqConfiguration(
       androidApplication = application,
       token = LuciqDefaults.APP_TOKEN,
       invocationEvents = LuciqDefaults.invocationEvents,
   )
   initializeLuciq(configuration)
   ```

4. **iOS entry point** — call as early as possible in the app lifecycle (e.g. `application(_:didFinishLaunchingWithOptions:)`); omit `androidApplication`:
   ```swift
   let configuration = LuciqConfiguration(
       token: LuciqDefaults.shared.APP_TOKEN,
       invocationEvents: LuciqDefaults.shared.invocationEvents,
   )
   initializeLuciq(configuration: configuration)
   ```

5. **Permissions**:
   - Android: the native SDK declares required permissions automatically; remove any that your app does not need.
   - iOS: add `NSMicrophoneUsageDescription` and `NSPhotoLibraryUsageDescription` to `Info.plist`.

6. **Platform-specific extras** (if applicable): Jetpack Compose apps may need additional native Compose libraries for screen tracking and APM; SwiftUI apps may need native SwiftUI APIs. Check the live guide for current requirements.

## 4. Configure invocation

Default to **shake + floating button**. Offer alternatives: screenshot, two-finger swipe, or programmatic-only. Apply the user's choice.

Keep at least one **visible** way to open Luciq — the floating button, or a debug-menu entry that calls the programmatic show API. Shake and screenshot leave nothing on screen, so a working SDK looks dead to whoever tests it: shaking a simulator needs *Device → Shake* (Ctrl+Cmd+Z), and a screenshot invocation needs the photo-library prompt accepted first. If the user wants no visible entry point in production, gate the floating button to debug builds (`#if DEBUG`, `BuildConfig.DEBUG`, `kDebugMode`, `__DEV__`) rather than dropping it.

Avoid screenshot invocation as the default on apps with sensitive screens — it fires on every screenshot the user takes.

## 5. Configure auto-masking and privacy disclosure

Goal: identify likely-sensitive UI views and configure SDK-side masking. A naive substring grep produces false positives (validators, comments, test fixtures), so the search must be narrowly scoped and every match must be user-confirmed.

1. Grep the platform's UI source files only (`*.swift`, `*.kt`, `*.dart`, `*.tsx`, `*.jsx`) for these identifier-shaped strings: `password`, `email`, `cardNumber`, `ssn`, `cvv`, `pin`, `dob`, `iban`.
2. Filter out matches in `*test*`, `*spec*`, `*mock*`, `*fixture*` paths, validator/regex utilities, and anything under `node_modules`, `Pods/`, or `build/`.
3. Show the filtered match list with `file:line` for each. Get per-match confirmation. Do not apply masking rules in bulk.
4. Verify the masking API signature for the detected platform on the live guide. The masking API has differed across platforms and changed across SDK versions; do not hardcode it.
5. Apply masking config only for confirmed matches.

**Network logs — rely on the default first.** From SDK 14.2.0 the SDK masks a known set of sensitive header and query keys (auth, token, password, api key, secret variants) on the device, before anything is sent. Confirm the installed version is ≥ 14.2.0 (`Package.resolved`, `Podfile.lock`, `build.gradle`, `pubspec.lock`, `package.json`) and do not write a custom handler for keys the default already covers. The full default list is in `luciq-masking-rules/references/network-masking.md`.

Add a custom handler only for sensitive keys the app actually sends that the default misses (for example `Cookie`, a vendor `X-API-Key`, a body field like `dateOfBirth`). iOS, verified against LuciqSDK 19.11.0:

```swift
NetworkLogger.setRequestObfuscationHandler { request in
    var masked = request
    for header in ["Cookie", "X-API-Key"] where masked.value(forHTTPHeaderField: header) != nil {
        masked.setValue("*****", forHTTPHeaderField: header)
    }
    return masked
}
```

Response bodies use `NetworkLogger.setResponseObfuscationHandler`. For other platforms, find the equivalent on the live guide and check the name as described in *Check symbols against the SDK*. Anything deeper — omitting whole endpoints, compliance presets — belongs to `luciq-masking-rules`; mention it in the hand-off rather than doing it here.

**App Store privacy (iOS, and the iOS side of Flutter / React Native / KMP).** Every feature turned on above changes what the app must declare on its App Store privacy card, and Apple rejects mismatches. Read `references/ios-privacy.md`, then:

1. Read the SDK's `PrivacyInfo.xcprivacy` from the installed package — its *linked* flags change between SDK versions, so never quote them from memory.
2. Map what this integration enabled to the App Privacy types to declare. The two that surprise people: any screenshot capture (repro steps, attachments, Session Replay) means **Photos or Videos**, and the bug-report email field (on by default) means **Email Address, linked**.
3. Offer the switches that shrink the list — hide the email field, repro steps without screenshots, no attachments — one line each. Apply only what the user picks.
4. Put the resulting declaration in the hand-off (step 10). The agent cannot change the App Store listing; the user must.

## 6. Wire user identification

If the app has authentication, find login and logout flows. Add `identifyUser(...)` and the corresponding sign-out call so reports tie back to your users. Verify the exact identification API on the live guide.

Pass the app's own opaque user ID and leave email and name empty unless the user asks for them — each non-empty argument becomes another type (Email Address, Name) *linked to the user* on the App Store privacy card.

If the app is anonymous-first (no login surface — typical for many B2C utilities, content readers, and games with guest play), skip this step entirely. Do not synthesize a fake user identity, do not insert `identifyUser` at app launch with placeholder values, and do not block the workflow waiting for a login flow that doesn't exist. Note the skip in the hand-off summary so the user can wire identification later if they add auth.

## 7. Bootstrap Luciq MCP server

YOU MUST verify the MCP server URL and transport type against https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server/setup-by-ide before proceeding. Both have evolved across releases.

Ask the user once: "global or project-local?" — then run immediately. Default to user-global if they don't express a preference. Use the `claude mcp add` CLI. Do NOT hand-edit `~/.claude.json` directly — the file can be very large and a malformed edit will break all MCP servers:

```bash
# User-global (survives across projects):
claude mcp add --transport http luciq <URL_FROM_LIVE_GUIDE> --scope user

# Project-local (.mcp.json in repo root):
claude mcp add --transport http luciq <URL_FROM_LIVE_GUIDE>
```

After running, prompt the user to restart their agent (Claude Code, Cursor, Codex, or other supported client) and complete the OAuth flow. Once authenticated, Luciq MCP tools become available qualified as `luciq:<tool_name>` (for example, `luciq:list_crashes`).

## 8. Symbol upload — hand off to `luciq-symbolicate`

Without symbol files (iOS dSYMs, Android ProGuard/R8 mappings, React Native source maps, Flutter split-debug-info) the first crashes arrive as raw addresses. Crash reporting works; the traces just can't be read.

Do not install the CLI or write an upload step from this skill. `luciq-symbolicate` owns it: it installs and authenticates the `luciq` CLI, knows the upload subcommand per platform, and wires it into an Xcode build phase, Gradle, Fastlane or CI with the credential read from a secret.

Ask once: *"Crash traces need symbol files uploaded to be readable. Set that up now? (It's a separate step — about 5 minutes.)"*

- **Yes** → invoke the `luciq-symbolicate` skill and follow it. Come back to step 9 afterwards.
- **Later** → record it in the hand-off as *"Symbol upload: not set up — first crashes will show raw addresses. Run `luciq-symbolicate` when ready."*

The CLI authenticates with its own CLI token (`luciq login` / `LUCIQ_AUTH_TOKEN`), **not** the app token. NEVER commit either.

## 9. Smoke build

| Platform | Command |
| --- | --- |
| iOS | `xcodebuild -project <Name>.xcodeproj -scheme <Scheme> -sdk iphonesimulator -destination "generic/platform=iOS Simulator" build` |
| Android | `./gradlew :app:assembleDebug` |
| Flutter | `flutter build apk --debug` |
| React Native (Android) | `npx react-native run-android` |
| React Native (iOS) | `npx react-native run-ios` |
| KMP | run both Android and iOS builds |

Deriving `<Workspace>` and `<Scheme>` for iOS and RN-iOS:

- `<Name>`: the `.xcodeproj` filename (without extension) at the project root. If a `.xcworkspace` exists instead (e.g. after CocoaPods install), use `-workspace Foo.xcworkspace` instead of `-project`.
- `<Scheme>`: derive by running `xcodebuild -list -project <Name>.xcodeproj` (or `-workspace` if applicable) and picking the app scheme. Usually matches the project name. For RN, the scheme typically matches the app's display name in `app.json`.
- If multiple workspaces or schemes exist, STOP and ask the user which to build. Do not guess.

STOP on build failure. NEVER claim success on a broken build.

## 10. Hand off

Print:
- File where init was added.
- Invocation event configured.
- Masking rules applied (with file:line for each).
- User identification call sites.
- MCP / CLI wired status.
- **App Store privacy** — the types to declare and whether they are linked, from step 5 (iOS targets only).
- The **Test it yourself** checklist below.
- Symbol upload status from step 8 (set up, or deferred with the one-line reason).
- Pointers: `luciq-symbolicate` for readable crash traces (if deferred), `luciq-debug` for crash investigation, `luciq-migrate` for moving off the legacy Instabug SDK or upgrading between Luciq versions.

### Test it yourself — the user runs this, not the agent

Setup ends at a green build. **Do not launch the app, trigger crashes, or inspect app containers to verify the integration** — that is slow, and the user can do it in three minutes. Print this checklist, adapted to the invocation events and platform actually configured:

> **Test it yourself (≈3 min)**
> 1. **Bug reporting:** run the app, tap the Luciq floating button (or shake — in the iOS Simulator: *Device → Shake*, Ctrl+Cmd+Z), and send a report that says "test report".
> 2. **Crash reporting:**
>    - **Stop the debugger first.** With Xcode (or Android Studio) attached, the debugger catches the crash and the app just freezes — no report is written. On iOS, launch the app from the simulator's home screen, or uncheck *Edit Scheme → Run → Debug executable*.
>    - Crash the app. If there's no easy way, add a temporary button that calls `fatalError("Luciq test crash")` (Kotlin: `throw RuntimeException("Luciq test crash")`) and remove it afterwards.
>    - **Open the app again.** Crash reports are sent on the next launch, not at the moment of the crash.
> 3. Open the Luciq dashboard for this app. The report and the crash should be there within a minute or two.
>
> **Nothing showing up?** Check the app token matches the app you're viewing on the dashboard, and that you reopened the app after the crash. On iOS, a `Library/IBGCache` folder in the app's data container means the SDK did start (the on-device folders still carry pre-rebrand names).

**Do NOT mention `luciq-onboard`.** Do not offer it, do not describe it, do not print *"next natural step…"*, do not ask *"want to onboard you now?"*. Setup ends after the items above. If the customer wants to onboard later, they will invoke `luciq-onboard` themselves — that decision is theirs to make on their own initiative, not a prompt for the assistant to surface.

## Style

- ALWAYS show diffs before applying code edits.
- ALWAYS confirm before running `pod install`, gradle syncs, or build commands.
- Verify SDK API signatures from the live integration guide. Do not hardcode them in this skill.

## Red Flags - STOP and surface to the user

If you catch yourself thinking any of these, you are about to ship a broken integration. STOP, surface to the user, do not proceed:

- "The build failed but the SDK is installed, so it's probably fine." It isn't. A failing build means a broken integration. Report the failure verbatim.
- "I skipped checking the live guide because the docs probably haven't changed." That's how you ship a stale signature. Always verify.
- "I hardcoded the init signature from this file, it looked right." This file is illustrative, not authoritative. The live guide is the source of truth.
- "The guide shows this method, so it exists." Check it against the installed SDK first. A guide snippet that isn't valid code is prose — don't fill in its gaps.
- "I'll write a network obfuscation handler to be safe." Not for keys the default auto-masking already covers. Extra handlers are extra code to get wrong.
- "I committed the app token inline because it's just for local testing." Tokens leak via git history. Use env injection or a gitignored secrets file.
- "I'll show all the apps from `list_applications` and let them pick." Not past 10 — ask for the name or token and filter.
- "`INFOPLIST_KEY_LuciqAppToken` is simpler." It is silently dropped. Use the xcconfig + real `Info.plist` path.
- "Privacy labels are the user's business, not setup's." Setup just changed what the binary collects. Say what to declare, or the next App Review submission can be rejected.
- "I auto-applied the masking rules without showing the user the matches." False positives are likely. Per-match confirmation is mandatory.
- "`pod install` or `gradle sync` had warnings but the build went green." Warnings about Luciq specifically are not cosmetic. Read them, surface them.
- "Shake is enough, no need for a button." Keep one visible entry point at least in debug builds — otherwise the first tester reports the SDK as broken.
- "I'll run the app and crash it to prove the setup works." Don't. Stop at the green build and hand the user the *Test it yourself* checklist.
- "The docs say to download the upload script from the dashboard, so I'll leave symbols for later." Hand off to `luciq-symbolicate` — it has a scriptable path, no dashboard download needed.
- "Two platform markers matched but I picked the obvious one." If the workspace is ambiguous, ask. Cross-platform projects break this assumption routinely.
- "I'll just hand-edit `project.pbxproj`, it's only a few entries." Use `scripts/add_spm_package.rb`. If it can't run, ask the user to add the package in Xcode — don't improvise object IDs.
- "Xcode is open but the edit is small." Ask the user to quit Xcode first. An edit under an open Xcode is what produces `Missing package product`.

The pattern: every shortcut here trades "looks done" for "actually works." The skill's job is to actually work.
