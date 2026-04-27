---
name: luciq-migrate
description: Migrate mobile codebases from Instabug to Luciq, or upgrade between Luciq SDK versions. Performs symbol renames (imports, classes, methods, packages), deprecated API replacements, and dependency manifest updates across iOS, Android, Flutter, React Native, KMP. Surfaces three sample diffs before bulk-applying. Verifies with a build. Use when the user says "migrate from Instabug to Luciq", "upgrade Luciq to [version]", "replace deprecated Luciq APIs", or "move us off Instabug".
---

<!--
Triggers (things the user might say):
- "migrate from Instabug to Luciq" / "move us off Instabug"
- "upgrade Luciq to [version]" / "bump Luciq SDK to [version]"
- "replace deprecated Luciq APIs"
- "rename Instabug symbols to Luciq"
- "migrate v1 to v2" / "Phoenix migration"
-->

# Luciq SDK Migration

Apply code transforms to migrate or upgrade the Luciq SDK.

## Workflow checklist

```
Migration Progress:
- [ ] 1. Detect platform
- [ ] 2. Detect current SDK + version
- [ ] 3. Choose transform set
- [ ] 4. Show 3 sample diffs (HARD GATE)
- [ ] 5. Apply in waves (deps → imports → types → metadata)
- [ ] 6. Build verify
- [ ] 7. Surface manual-review checklist
```

## 1. Detect platform

Single Glob.

## 2. Detect current SDK + version

| Platform | Source |
|---|---|
| iOS | `Podfile.lock` — look for `Instabug` or `Luciq` pod |
| Android | `app/build.gradle*` + `gradle.lockfile` — look for `com.instabug.*` or `com.luciq.*` |
| Flutter | `pubspec.lock` — look for `instabug_flutter` or `luciq_flutter` |
| React Native | `package-lock.json` / `yarn.lock` — relevant package |
| KMP | both Android + iOS sources |

Report: SDK name + version + count of call sites.

## 3. Transform set

| Intent | Transform set |
|---|---|
| Instabug → Luciq | Rename `Instabug*` symbols, imports, packages, dependency entries |
| vN → vN+1 | Apply known deprecations between those versions |
| "v1 → v2" / "Phoenix" | v1 → v2 API surface — fetch via `luciq-docs` |

ALWAYS look up version-specific transforms via `luciq-docs`. NEVER hardcode rename tables here — they go stale.

## 4. Show 3 sample diffs first (HARD GATE)

Before bulk-applying:
1. Use Grep to find the first 3 call sites
2. Generate the diff for each
3. Show all 3 to the user
4. Wait for sign-off

This is a hard rule. Bulk renames without preview corrupt repos.

## 5. Apply in waves

Order matters:

1. **Dependency manifest** — `Podfile`, `build.gradle`, `pubspec.yaml`, `package.json`
2. **Imports** — every file referencing the old symbol
3. **Type names** — class refs, method calls
4. **Project metadata** — group names, build phases

After each wave, sanity check: open a sample file, confirm the transform applied cleanly.

## 6. Build verify

| Platform | Command |
|---|---|
| iOS | `pod install && xcodebuild -workspace ... -scheme ... build` |
| Android | `./gradlew :app:assembleDebug` |
| Flutter | `flutter pub get && flutter analyze && flutter build apk --debug` |
| React Native | `npm install && npx react-native run-android` (or `run-ios`) |
| KMP | both Android and iOS builds |

STOP and surface errors. NEVER claim "done" if the build is broken.

## 7. Manual-review checklist

Some transforms are pure renames; others have semantic differences (changed parameters, callback shapes, default behaviors). Output a checklist:

```
MANUAL REVIEW REQUIRED:
- [ ] <api>: <what changed>  [<file>:<line>]
- [ ] <api>: <what changed>  [<file>:<line>]
```

Source this list from the migration guide via `luciq-docs`.

## Style

- ALWAYS show 3 sample diffs before bulk-apply.
- DO NOT claim "done" if the build is broken.
- DO NOT invent a rename mapping — fetch from `luciq-docs`.
- ALWAYS flag ambiguous renames for manual review.
