---
name: luciq-symbolicate
description: Upload Luciq symbol artifacts so crash reports show readable stack traces. Wraps the luciq_cli upload-symbols command. Auto-locates dSYM (iOS), mapping.txt (Android Proguard/R8), DWARF / split-debug-info (Flutter), and source maps + native artifacts (React Native). Optionally scaffolds CI auto-upload (GitHub Actions, Bitrise, Fastlane). Use when the user says "upload symbols", "symbolicate", "this stack trace is unreadable / obfuscated", "set up symbol upload in CI", or "fix obfuscated traces".
---

<!--
Triggers (things the user might say):
- "upload symbols" / "upload dSYM / mapping.txt to Luciq"
- "symbolicate this crash" / "deobfuscate this stack trace"
- "this stack trace is unreadable / obfuscated"
- "set up symbol upload in CI" / "automate dSYM upload"
- "fix obfuscated traces in Luciq"
-->

# Luciq Symbol Upload

Upload symbol artifacts so Luciq deobfuscates production stack traces.

## Workflow checklist

```
Symbol Upload Progress:
- [ ] 1. Detect platform
- [ ] 2. Check luciq_cli installed
- [ ] 3. Locate symbol artifacts
- [ ] 4. Read app version
- [ ] 5. Run upload (after showing the command)
- [ ] 6. Verify exit code
- [ ] 7. (Optional) Scaffold CI auto-upload
```

## 1. Detect platform

Single Glob (same rule as other Luciq skills).

## 2. Check luciq_cli

Run `which luciq` (or `dart pub global list | grep luciq_cli`). If missing:

```bash
dart pub global activate luciq_cli
```

Confirm Dart's global bin directory is on `PATH`.

## 3. Locate symbol artifacts

| Platform | Artifact | Default location(s) |
|---|---|---|
| iOS | `*.dSYM` | `~/Library/Developer/Xcode/DerivedData/<App>-*/Build/Products/<config>-iphoneos/<App>.app.dSYM`, or `<workspace>/build/.../*.dSYM` |
| Android | `mapping.txt` (R8/Proguard) | `app/build/outputs/mapping/<variant>/mapping.txt` |
| Flutter | symbols dir from `--split-debug-info` | `build/symbols/`, or wherever the build was directed |
| React Native iOS | `*.dSYM` + JS source map | iOS path + `ios/main.jsbundle.map` |
| React Native Android | `mapping.txt` + JS source map | Android path + `android/app/build/.../*.map` |
| KMP | both iOS and Android artifacts | as above |

If an artifact isn't found, ask the user to point at it, or to run a build with the right flags first (e.g. Flutter: `flutter build apk --release --split-debug-info=build/symbols --obfuscate`).

## 4. Read app version

| Platform | Source |
|---|---|
| iOS | `Info.plist` (`CFBundleShortVersionString`) or `*.xcconfig` |
| Android | `app/build.gradle*` (`versionName`) |
| Flutter | `pubspec.yaml` (`version:`) |
| React Native | `package.json` `version` (or platform-specific) |

## 5. Run upload

ALWAYS show the command (with redacted credentials) before running:

```bash
luciq upload-symbols \
  --app-token <APP_TOKEN> \
  --api-key <API_KEY> \
  --symbols-path <PATH> \
  [--enable-native-sourcemaps] \
  [--verbose-logs]
```

Credentials precedence:
1. CLI args (`--app-token`, `--api-key`)
2. Env vars (`LUCIQ_APP_TOKEN`, `LUCIQ_API_KEY`)
3. `local.properties`

Confirm exact flag names against `luciq-docs` if the SDK is recent.

## 6. Verify

Check the CLI exit code and output. If non-zero, surface the error and STOP.

## 7. CI scaffold (only if requested)

### GitHub Actions
Insert after the build step:

```yaml
- name: Upload Luciq symbols
  env:
    LUCIQ_APP_TOKEN: ${{ secrets.LUCIQ_APP_TOKEN }}
    LUCIQ_API_KEY: ${{ secrets.LUCIQ_API_KEY }}
  run: |
    dart pub global activate luciq_cli
    luciq upload-symbols --symbols-path ./build [--enable-native-sourcemaps]
```

Remind the user to add `LUCIQ_APP_TOKEN` and `LUCIQ_API_KEY` to repo secrets.

### Bitrise
Add a "Script" step after the build with the same command and secrets exposed via env.

### Fastlane
Add a `desc 'Upload Luciq symbols'` lane with `sh "luciq upload-symbols ..."`.

## Style

- DO NOT claim symbols uploaded if the CLI returned non-zero.
- DO NOT abstract the CI YAML/Ruby — write it concretely.
- ALWAYS show the command before running it.
