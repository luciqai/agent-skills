# iOS — wiring the SDK with Swift Package Manager

Read this before touching an `.xcodeproj`. Every rule here comes from a real integration that lost time on it.

## Facts that don't change between runs

| | Value | Where it comes from |
|---|---|---|
| Package URL | `https://github.com/luciqai/luciq-ios-sdk` | Verify on the live guide |
| SPM **product** name | `Luciq` | `Package.swift` of the package — `.library(name: "Luciq", …)` |
| Swift **module** (import) | `import LuciqSDK` | The binary is `LuciqSDK.xcframework` |
| Version | Latest tag | `git ls-remote --tags https://github.com/luciqai/luciq-ios-sdk \| awk -F/ '{print $3}' \| sort -V \| tail -1` |

Product ≠ module. `import Luciq` does not compile. Use `Luciq` only in the project file, `LuciqSDK` only in Swift.

## `.xcodeproj` projects: use the script, not hand edits

Hand-editing `project.pbxproj` means inventing 24-hex object IDs and touching four sections by hand; every agent does it slightly differently and some get it wrong. The bundled script does exactly what Xcode's *Add Package Dependencies…* does, and is idempotent.

Inspect existing Luciq package and product entries, framework links, and imports first. Reuse or update them in place, preserving identifiers and app-specific settings; use the script for missing pieces rather than adding a second integration. If `Package.swift` exists, reuse or update its declarations too.

```bash
gem list -i xcodeproj >/dev/null || gem install xcodeproj   # >= 1.27.0 for Xcode 16+ projects

ruby <skill-dir>/scripts/add_spm_package.rb \
  --project <App>.xcodeproj \
  --target <AppTarget> \
  --url https://github.com/luciqai/luciq-ios-sdk \
  --version <LATEST_TAG> \
  --product Luciq
```

It adds the package reference, the target's product dependency, and the Frameworks build-phase entry (without that last one the product builds but never links). Re-running it prints `nothing to change`.

If the gem can't be installed (no Ruby, locked-down machine), STOP and ask the user to add the package in Xcode via *File → Add Package Dependencies…* with the URL above. Do not fall back to hand-editing `project.pbxproj`.

## Rule 1 — Xcode must be closed while the project file changes

Xcode holds its own copy of the project in memory. Edit the file underneath it and Xcode picks up the new package reference but never resolves it, leaving `workspace-state.json` with the package pinned to nothing. The symptom is a build error that points nowhere useful:

```
error: Missing package product 'Luciq' (in target '<App>')
```

The script refuses to run while Xcode is open. Before running it, tell the user in one line:

> Please quit Xcode for a moment — I'm adding the Luciq package to the project file. You can reopen it once I say so.

Only if the user can't close Xcode: pass `--allow-xcode-open`, and tell them to run **File → Packages → Resolve Package Versions** in Xcode afterwards.

## Rule 2 — resolution is per DerivedData

`xcodebuild -resolvePackageDependencies` resolves into the command line's DerivedData. An Xcode window that is already open uses its own, so a green CLI resolve does **not** fix a red Xcode. If the user reports "Missing package product" in Xcode after the CLI build passed, the fix is on their side: **File → Packages → Resolve Package Versions** (or **Reset Package Caches** if that doesn't clear it).

The smoke build in step 9 resolves packages itself, so there is no need to run `-resolvePackageDependencies` separately. If you do run it with `-derivedDataPath`, it also needs `-scheme`.

If resolution fails with "no versions match", the `--version` is higher than any tag — re-read the tags with the `git ls-remote` line above.

## Entry point — where the start call goes

Start Luciq at the very beginning of `application(_:didFinishLaunchingWithOptions:)`, before any other app initialization or SDK, including Firebase. Keep required pre-start Luciq configuration immediately before `Luciq.start` as the first initialization block; starting other SDKs first can interfere with automatic network capture. Configure network masking after the start call inside that callback.

1. **UIKit / `AppDelegate`** — reuse the existing launch callback.
2. **SwiftUI with `@UIApplicationDelegateAdaptor`** — reuse that adaptor and its delegate's launch callback.
3. **SwiftUI `@main struct …: App` only** — add the missing app delegate and connect it with `@UIApplicationDelegateAdaptor`.

Merge the example into the existing entry point and delegate; add only missing pieces, keeping a single delegate and adaptor. Move any existing Luciq start call and pre-start configuration to the beginning of the launch callback, keeping exactly one start on each path the app can take at launch (separate `#if` branches may each have one). Preserve views, delegate superclass and conformances, other launch work, and return behavior.

```swift
import SwiftUI
import UIKit
import LuciqSDK

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let token = Bundle.main.object(forInfoDictionaryKey: "LuciqAppToken") as? String ?? ""
        if token.isEmpty || token.hasPrefix("$(") {
            assertionFailure("Luciq token missing — fill in Config/Luciq.xcconfig")
        } else {
            Luciq.start(withToken: token, invocationEvents: [.shake, .floatingButton])
        }
        return true
    }
}

@main
struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene { WindowGroup { ContentView() } }
}
```

Verify the start signature on the live guide, and read the token from `Info.plist` as shown in `ios-token-injection.md` — never a string literal.

## Projects with no `Info.plist` file

Projects created by Xcode 13+ usually set `GENERATE_INFOPLIST_FILE = YES` and have no `Info.plist` on disk. Check with:

```bash
grep -E "GENERATE_INFOPLIST_FILE|INFOPLIST_FILE" <App>.xcodeproj/project.pbxproj
```

- **Standard Apple keys** (usage descriptions) — add them as build settings: `INFOPLIST_KEY_NSMicrophoneUsageDescription = "…";` in the app target's Debug and Release configurations. Xcode injects these because it recognises them.
- **Custom keys** (such as the app token) — `INFOPLIST_KEY_<Custom>` is **silently dropped**; Xcode only injects keys it knows. Custom keys need a real `Info.plist` file — `scripts/add_token_config.rb` creates one; see `ios-token-injection.md`.

## Xcode 16+ project format

Projects with `objectVersion = 77` use `PBXFileSystemSynchronizedRootGroup`: any file dropped into the app folder is already part of the target. Don't add `PBXFileReference` / `PBXBuildFile` entries for new Swift files — just create the file in the folder.
