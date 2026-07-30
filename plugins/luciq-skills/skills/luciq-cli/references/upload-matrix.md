# Symbol upload matrix

Every `luciq upload` subcommand, what file it wants, what flags it requires, and where the artifact usually lives.

There is **no MCP tool for uploads** — the CLI is the only path. `luciq upload help <subcommand>` is authoritative over this file.

## The command shape

```bash
luciq upload <SUBCOMMAND> FILE --slug my-app --mode production [options]
```

Uploads use the **same CLI login as every other command** — `luciq login` (or `LUCIQ_AUTH_TOKEN`). You never pass an application token: the server resolves the app from `--slug` + `--mode`, and rejects the upload if that exact pair isn't among the apps your token can reach. So a CI job that uploads needs a CLI token in its environment, and that token's owner needs access to the app in that mode plus `settings.mapping_files.modify`.

Output on success:

```
Uploading Android mapping file: mapping.txt

✓ Android mapping file uploaded successfully!
```

Failure prints `✗ Upload failed: <message>` and exits non-zero, so a failed upload fails the build step.

## Required flags by file type

Every command takes `--slug` and `--mode`. Beyond those:

| Type | Subcommand pattern | Also required | File format enforced locally |
| --- | --- | --- | --- |
| dSYM | `*-ios-dsym` | — | `.zip` |
| Mapping | `*-android-mapping` | `--version-name`, `--version-code` | any |
| RN source map | `react-native-*-sourcemap` | `--version-name`, `--version-code` (+ optional `--codepush`) | `.json` or `.txt` |
| Flutter Dart symbols | `flutter-*-sourcemap` | `--version-name`, `--version-code` | `.zip` |
| NDK | `*-ndk` | `--version-name`, `--arch` — **not** `--version-code` | `.zip` |

- `--version-name` — e.g. `1.0.0`
- `--version-code` — e.g. `1`
- `--arch` — `armeabi-v7a` | `arm64-v8a` | `x86` | `x86_64`
- `--codepush` — optional CodePush label, React Native source maps only

The CLI validates the file **before** any network call: it must exist, be readable, and match the extension its command expects. Those failures cost nothing, so a bad path or a `.zip`-vs-`.json` mixup surfaces instantly rather than as a server error.

**The version pair must match the build exactly.** A mismatch does not error — the upload succeeds and simply never deobfuscates anything. Read the values from the build system, not from memory:

| Platform | Source of truth |
| --- | --- |
| Android / Flutter Android | `versionName` / `versionCode` in `app/build.gradle(.kts)`, or `flutter build` output |
| iOS | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` (or `CFBundleShortVersionString` / `CFBundleVersion`) |
| React Native | native config above — `package.json`'s version is usually **not** what the SDK reports |
| Flutter | `version: 1.0.0+1` in `pubspec.yaml` → name `1.0.0`, code `1` |

## iOS

| Subcommand | File |
| --- | --- |
| `ios-dsym` | `.zip` containing the dSYM(s) |

```bash
luciq upload ios-dsym MyApp-dSYMs.zip --slug my-app --mode production
```

Typical locations — verify on disk before using any of them:

```bash
# from an archive
ls -d ~/Library/Developer/Xcode/Archives/*/*.xcarchive/dSYMs
# from a local build
find ~/Library/Developer/Xcode/DerivedData -name '*.dSYM' -maxdepth 6
# CI with an explicit archive path
ls -d "$ARCHIVE_PATH/dSYMs"
```

Zip before uploading — the command requires a `.zip`, not a `.dSYM` bundle:

```bash
cd "$ARCHIVE_PATH/dSYMs" && zip -r "$PWD/../dsyms.zip" .
```

If the build was uploaded with bitcode enabled, Apple re-links it and the useful dSYMs are the ones downloaded from App Store Connect (or fetched via `Xcode → Organizer → Download Debug Symbols`), not the ones your build produced.

## Android

| Subcommand | File |
| --- | --- |
| `android-mapping` | `mapping.txt` |
| `android-ndk` | `.zip` of `.so` files for **one** `--arch` |

```bash
luciq upload android-mapping app/build/outputs/mapping/release/mapping.txt \
  --slug my-app --mode production --version-name 1.0.0 --version-code 1

luciq upload android-ndk arm64-v8a.zip \
  --slug my-app --mode production --version-name 1.0.0 --arch arm64-v8a
```

Typical locations:

```bash
# mapping (per variant)
ls app/build/outputs/mapping/*/mapping.txt
# unstripped native libs
find app/build/intermediates -path '*merged_native_libs*' -name '*.so' | head
```

`--arch` is per-architecture: **one upload per ABI**, each zip containing only that ABI's `.so` files. Upload the *unstripped* libraries — stripped ones symbolicate to nothing.

## React Native

| Subcommand | File |
| --- | --- |
| `react-native-ios-dsym` | `.zip` of dSYMs |
| `react-native-ios-sourcemap` | `.json` / `.txt` source map |
| `react-native-android-mapping` | `mapping.txt` |
| `react-native-android-sourcemap` | `.json` / `.txt` source map |
| `react-native-ndk` | `.zip` of `.so` files for one `--arch` |

```bash
luciq upload react-native-ios-sourcemap main.jsbundle.map.json \
  --slug my-app --mode production --version-name 1.0.0 --version-code 1
```

A React Native release needs **both halves**: the JS source map (for the JS frames) and the native symbols (dSYM / mapping / NDK) for the native frames. Shipping only one leaves half of every mixed stack trace unreadable.

Source maps only exist if the bundle step was asked to emit them:

```bash
npx react-native bundle --platform ios --dev false \
  --entry-file index.js --bundle-output main.jsbundle \
  --sourcemap-output main.jsbundle.map.json
```

Android release builds commonly leave one at `android/app/build/generated/sourcemaps/react/release/index.android.bundle.map` — rename or copy it to `.json`/`.txt` if it lacks one of those extensions, since the CLI rejects anything else for RN source maps. With CodePush, tag each OTA upload with `--codepush <label>` so the right map is matched to the right revision.

## Flutter

| Subcommand | File |
| --- | --- |
| `flutter-ios-dsym` | `.zip` of dSYMs |
| `flutter-ios-sourcemap` | `.zip` of iOS Dart symbol files |
| `flutter-android-mapping` | `mapping.txt` |
| `flutter-android-sourcemap` | `.zip` of Android Dart symbol files |
| `flutter-ndk` | `.zip` of `.so` files for one `--arch` |

```bash
luciq upload flutter-ios-sourcemap dart-symbols-ios.zip \
  --slug my-app --mode production --version-name 1.0.0 --version-code 1
```

⚠️ **Flutter `*-sourcemap` commands take a `.zip` of Dart debug-symbol files. React Native `*-sourcemap` commands take a `.json`/`.txt` source map.** Same flag name, different artifact — and the CLI enforces the extension, so the wrong one fails immediately with `✗ File must be a .zip archive` or `✗ Source map must be a .json or .txt file`.

Dart symbols exist only for obfuscated builds:

```bash
flutter build ipa --obfuscate --split-debug-info=build/debug-info
flutter build appbundle --obfuscate --split-debug-info=build/debug-info
cd build/debug-info && zip -r ../dart-symbols.zip .
```

An obfuscated Flutter release also needs the native side: `flutter-android-mapping` when Android minification is on, `flutter-ios-dsym` for the iOS native frames, `flutter-ndk` for bundled `.so` files.

## What a complete release upload looks like

| Build | Upload |
| --- | --- |
| iOS native | `ios-dsym` |
| Android, minified | `android-mapping` (+ `android-ndk` per ABI if NDK) |
| React Native iOS | `react-native-ios-sourcemap` **and** `react-native-ios-dsym` |
| React Native Android | `react-native-android-sourcemap` **and** `react-native-android-mapping` (+ `react-native-ndk` per ABI) |
| Flutter iOS, obfuscated | `flutter-ios-sourcemap` **and** `flutter-ios-dsym` |
| Flutter Android, obfuscated | `flutter-android-sourcemap` **and** `flutter-android-mapping` (+ `flutter-ndk` per ABI) |

## Before wiring anything into CI

Run one upload by hand and confirm the `✓`. It validates the artifact path, the credentials, the app access, and the flag set in a single shot — and the error text tells you which of them was wrong. A pipeline step that has never uploaded successfully once is an untested change on a release path, and its failure mode is silent: an unreadable stack trace weeks later.
