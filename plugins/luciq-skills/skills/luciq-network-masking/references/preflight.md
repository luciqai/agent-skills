# Preflight — tools, target resolution, per-platform capture setup

The skill supports **all Luciq platforms by default** — iOS, Android, Flutter,
React Native, KMP. Capture runs against **one target at a time** (simulator,
emulator, or device); "all platforms" means the skill resolves whichever target the
app runs on and emits handlers for every platform present in the repo.

Capture is via the **seam-dump** (`../assets/seam-dump/`): a temporary pass-through
Luciq obfuscation handler. It needs **no Frida, no proxy, no CA cert** — just a
buildable debug app and the platform toolchain. Verify every command against the
current toolchain — versions drift.

## 1. Host tools

| Tool | Check | Install |
|---|---|---|
| Python 3.9+ | `python3 --version` | system / `brew install python` |
| iOS build + targets | `xcrun simctl help`, `xcodebuild -version` | Xcode + command line tools |
| Android build + targets | `adb version`, `emulator -list-avds` | Android SDK platform-tools + emulator |

The app must be **buildable from source** — the seam-dump adds a temporary snippet
and rebuilds. If you can't rebuild the app (third-party binary, no source), the
seam-dump can't apply; STOP and say so.

## 2. Target resolution (running-first, repo-fallback)

```
1. Booted/attached target?
   iOS:      xcrun simctl list devices booted
   Android:  adb devices        (emulator-XXXX or a device serial)
   - exactly one  -> use it
   - several      -> ask the developer which
   - none         -> step 3
2. (chosen) confirm the app id, then set up capture
3. No target -> detect platform from the repo, then boot:
```

| Platform | Repo markers | Boot fallback |
|---|---|---|
| iOS | `*.xcodeproj`, `*.xcworkspace`, `Podfile` | `xcrun simctl boot <UDID>` (newest available runtime) |
| Android | `settings.gradle(.kts)`, `AndroidManifest.xml` | `emulator -avd <name>` (first AVD) |
| Flutter | `pubspec.yaml` with `flutter:` | ask iOS or Android, then boot that |
| React Native | `package.json` dep on `react-native` | ask iOS or Android, then boot that |
| KMP | `*.gradle.kts` with multiplatform plugin | resolve to the iOS or Android artifact, then boot that |

Flutter / RN / KMP compile to a native iOS or Android app, so the **capture snippet
is the iOS or Android one below** — the cross-platform framework only decides which
handler templates to emit (and which seam-dump snippet to add), not the mechanics.

## 3. App id resolution

| Platform | Where to read the id |
|---|---|
| iOS | `PRODUCT_BUNDLE_IDENTIFIER` in the pbxproj / `Info.plist` `CFBundleIdentifier` |
| Android | `applicationId` in `build.gradle(.kts)` / package in `AndroidManifest.xml` |

Confirm the resolved id with the developer before capturing — it's needed to pull
the file (`simctl get_app_container` / `run-as <pkg>`).

## 4. Per-platform capture setup (seam-dump)

The full snippets and instructions live in `../assets/seam-dump/` (`ios.swift`,
`android.kt`, and the `README.md` table for Flutter/RN). Summary:

### iOS (Simulator or device)
1. Add `ios.swift` (`LuciqSeamDump`) to the target.
2. Call `LuciqSeamDump.installIfRequested()` right after `Luciq.start(...)`.
3. Build + run with the launch arg `-seamDump`
   (`xcrun simctl launch booted <bundle-id> -seamDump`, or the Xcode scheme).
4. Walk paths → pull:
   `xcrun simctl get_app_container booted <bundle-id> data` →
   `Documents/luciq-seam-capture.jsonl`.

### Android (emulator or device)
1. Add `android.kt` (`LuciqSeamDump`) to the app module.
2. Call `LuciqSeamDump.installIfEnabled(context)` right after `Luciq.start(...)`.
3. Set `SEAM_DUMP = true`, build + run a **debug** build.
4. Walk paths → pull:
   `adb exec-out run-as <pkg> cat files/luciq-seam-capture.jsonl > capture.jsonl`.

No `frida-server`, no root, no proxy — the app writes the file to its own sandbox.

## 5. Coverage note

The seam-dump captures from the moment the handler is installed (right after
`Luciq.start`), so **startup/login traffic is included** as long as you exercise
those flows in the walk. Capture is still walk-bound: only paths you actually
navigate are recorded. Walk every critical flow, and re-run after adding new ones.

## 6. Body-capture blockers (check before the walk)

Header / query / path capture is robust. **Body** capture has known blind spots —
flag these up front so an empty-body capture isn't mistaken for "no body PII":

| Condition | Effect | What to do |
|---|---|---|
| App uses a custom `URLSessionDelegate` (auth-challenge / cert-pinning) | Luciq logs metadata but not bodies for that session | Note it; verify body capture against a session Luciq fully controls |
| Target is a self-signed / local HTTP(S) backend (`localhost`, `127.0.0.1`) | Luciq's internal re-issue can't complete → response bodies empty | Test against a real HTTPS endpoint, or add the cert to the device trust store and re-confirm |
| iOS, any host | `request.httpBody` (and httpBodyStream) usually nil at the request seam | Request-body capture on iOS is unreliable; rely on response bodies |

After the walk, `classify.py`'s `bodyCoverage` block confirms per host whether bodies
were actually captured. If one host captured bodies and the app's host did not, it's a
blocker above — not absent PII. See the SKILL red flags.

## 7. `.gitignore`

Add `capture*.jsonl` and `luciq-seam-capture.jsonl` to `.gitignore` before any
capture is written — the file holds real plaintext PII.
