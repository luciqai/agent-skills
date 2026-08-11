# CI and automation recipes

Pipeline snippets for symbol uploads and scheduled queries. Adapt paths and variant names to the repo you're in — never paste a path you haven't confirmed exists.

## Ground rules

1. **Everything authenticates with a CLI token.** Uploads and data commands use the same credential: `LUCIQ_AUTH_TOKEN` in the job environment, or `luciq login` locally. There is no separate app token.
2. **A CLI token represents a person, not a service account.** It carries that user's role and app access, and the job breaks when they rotate it or leave. Uploads additionally need `settings.mapping_files.modify` on the app. Say this out loud when wiring a pipeline — someone has to own that token.
3. **Tokens come from the platform's secret store**, exported into the job environment, referenced as `"$VAR"`. A literal token in a workflow file, `Fastfile`, or Gradle script is a leaked credential — report it rather than writing it.
4. **Let a failed upload fail the job.** The CLI exits non-zero; don't wrap it in `|| true` "so releases aren't blocked" — the point is to learn now rather than when the crashes arrive.
5. **Install the CLI in the job.** `gem install luciq-cli` is the portable path (Ruby ≥ 2.7 is preinstalled on GitHub/Bitrise macOS images); `brew install luciqai/tap/luciq-cli` on macOS runners with Homebrew warm. Pin a version when reproducibility matters: `gem install luciq-cli -v X.Y.Z`.
6. **Upload after the build, in the same job** — the artifact only exists there unless you explicitly persist it.

## GitHub Actions — Android

```yaml
- name: Upload ProGuard mapping to Luciq
  env:
    LUCIQ_AUTH_TOKEN: ${{ secrets.LUCIQ_AUTH_TOKEN }}
    VERSION_NAME: ${{ steps.version.outputs.name }}
    VERSION_CODE: ${{ steps.version.outputs.code }}
  run: |
    set -euo pipefail
    gem install luciq-cli --no-document
    luciq upload android-mapping app/build/outputs/mapping/release/mapping.txt \
      --slug my-app --mode production \
      --version-name "$VERSION_NAME" \
      --version-code "$VERSION_CODE"
```

`set -euo pipefail` matters: without it a mid-script failure can still exit `0` and the step passes while nothing uploaded.

`--mode` is the environment the *build* reports to — a beta/TestFlight pipeline uploads to `beta`, not `production`. Symbols uploaded to the wrong mode symbolicate nothing in the mode where the crashes land.

## GitHub Actions — iOS

```yaml
- name: Upload dSYMs to Luciq
  env:
    LUCIQ_AUTH_TOKEN: ${{ secrets.LUCIQ_AUTH_TOKEN }}
  run: |
    set -euo pipefail
    gem install luciq-cli --no-document
    cd "$ARCHIVE_PATH/dSYMs"
    zip -r "$RUNNER_TEMP/dsyms.zip" .
    luciq upload ios-dsym "$RUNNER_TEMP/dsyms.zip" --slug my-app --mode production
```

## GitHub Actions — React Native (both halves)

```yaml
- name: Upload React Native symbols to Luciq
  env:
    LUCIQ_AUTH_TOKEN: ${{ secrets.LUCIQ_AUTH_TOKEN }}
    VERSION_NAME: ${{ steps.version.outputs.name }}
    VERSION_CODE: ${{ steps.version.outputs.code }}
  run: |
    set -euo pipefail
    gem install luciq-cli --no-document
    cp android/app/build/generated/sourcemaps/react/release/index.android.bundle.map \
       "$RUNNER_TEMP/index.android.bundle.map.json"     # CLI requires .json/.txt for RN maps
    luciq upload react-native-android-sourcemap "$RUNNER_TEMP/index.android.bundle.map.json" \
      --slug my-app --mode production --version-name "$VERSION_NAME" --version-code "$VERSION_CODE"
    luciq upload react-native-android-mapping \
      android/app/build/outputs/mapping/release/mapping.txt \
      --slug my-app --mode production --version-name "$VERSION_NAME" --version-code "$VERSION_CODE"
```

## GitHub Actions — Flutter (obfuscated)

```yaml
- name: Build and upload Flutter symbols
  env:
    LUCIQ_AUTH_TOKEN: ${{ secrets.LUCIQ_AUTH_TOKEN }}
  run: |
    set -euo pipefail
    flutter build appbundle --obfuscate --split-debug-info=build/debug-info
    (cd build/debug-info && zip -r ../dart-symbols.zip .)
    gem install luciq-cli --no-document
    VERSION_NAME=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d+ -f1)
    VERSION_CODE=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d+ -f2)
    luciq upload flutter-android-sourcemap build/dart-symbols.zip \
      --slug my-app --mode production --version-name "$VERSION_NAME" --version-code "$VERSION_CODE"
```

Only reuse that `pubspec.yaml` parse if the version really is a literal `x.y.z+n` there — many projects inject it at build time instead.

## Fastlane

```ruby
lane :upload_luciq_symbols do
  archive = lane_context[SharedValues::XCODEBUILD_ARCHIVE]
  zip(path: "#{archive}/dSYMs", output_path: "dsyms.zip")

  sh("luciq", "upload", "ios-dsym", "dsyms.zip",
     "--slug", "my-app", "--mode", "production")
end
```

`luciq` reads `LUCIQ_AUTH_TOKEN` from the environment, so the token never appears in the lane. Call the lane after `gym`/`build_app`, in the same run.

## Gradle

```kotlin
// app/build.gradle.kts
tasks.register<Exec>("uploadLuciqMapping") {
    val variant = "release"
    commandLine(
        "luciq", "upload", "android-mapping",
        "app/build/outputs/mapping/$variant/mapping.txt",
        "--slug", "my-app", "--mode", "production",
        "--version-name", android.defaultConfig.versionName,
        "--version-code", android.defaultConfig.versionCode.toString()
    )
}

tasks.named("assembleRelease") { finalizedBy("uploadLuciqMapping") }
```

Pulling the version straight from `defaultConfig` is the point — it can't drift from the build the way a hand-maintained CI variable can. If flavors override the version, read it from the variant instead.

## Bitrise

```yaml
- script@1:
    title: Upload symbols to Luciq
    inputs:
    - content: |-
        #!/usr/bin/env bash
        set -euo pipefail
        gem install luciq-cli --no-document
        luciq upload ios-dsym "$BITRISE_DSYM_PATH" --slug my-app --mode production
```

Add `LUCIQ_AUTH_TOKEN` as a secret env var. `$BITRISE_DSYM_PATH` is already a zip from the Xcode Archive step.

## CircleCI

```yaml
- run:
    name: Upload mapping to Luciq
    command: |
      set -euo pipefail
      gem install luciq-cli --no-document
      luciq upload android-mapping app/build/outputs/mapping/release/mapping.txt \
        --slug my-app --mode production \
        --version-name "$VERSION_NAME" --version-code "$VERSION_CODE"
```

Store the token in a context or project env var.

## Xcode build phase (local / non-CI archives)

Only worth adding when engineers archive from their machines — each of them then uploads under their own CLI token. Guard it so it never runs on debug builds:

```bash
# Run Script phase, after "Copy Bundle Resources"
if [ "$CONFIGURATION" != "Release" ]; then exit 0; fi
if [ -z "${LUCIQ_AUTH_TOKEN:-}" ] && [ ! -f "$HOME/.luciqrc" ]; then
  echo "warning: no Luciq credentials, skipping symbol upload"; exit 0
fi
DSYM_ZIP="$TARGET_TEMP_DIR/dsyms.zip"
(cd "$DWARF_DSYM_FOLDER_PATH" && zip -qr "$DSYM_ZIP" .)
luciq upload ios-dsym "$DSYM_ZIP" --slug my-app --mode production
```

The `~/.luciqrc` fallback is what makes this workable locally: whoever ran `luciq login` is already authenticated, and nothing has to be committed.

## Scheduled queries (cron, scheduled workflows)

```bash
#!/usr/bin/env bash
set -euo pipefail
export LUCIQ_AUTH_TOKEN="$LUCIQ_CLI_TOKEN"   # from the secret store

out=$(luciq incidents list --slug my-app --mode production --status open)
# incidents list returns CSV: header + one row per incident
count=$(printf '%s\n' "$out" | tail -n +2 | grep -c . || true)
[ "$count" -gt 0 ] && printf 'open incidents: %s\n%s\n' "$count" "$out"
```

Keep scheduled jobs inside the **100 requests / 60 s per source IP** budget. That limit is keyed by IP, so every job on a shared runner shares it — stagger schedules, don't parallelize pagination, and back off on `429`.

For self-hosted clusters, also export `LUCIQ_URL=https://api.<cluster>.luciq.ai`.

## Reviewing an existing pipeline

Checks worth running when the ask is "why isn't this symbolicating":

- Is there an upload step at all, and does it run on the **release** path (not just debug/PR builds)?
- Is it wrapped in `|| true`, `continue-on-error`, or a `set +e` region that swallows failures?
- Does `--mode` match the environment the build reports to?
- Does `--version-name` / `--version-code` come from the build, or from a hand-maintained variable that drifted?
- React Native / Flutter: are **both** the JS-or-Dart symbols *and* the native symbols uploaded?
- NDK: one upload per ABI, and unstripped `.so` files?
- Is the token a real secret reference, and does its owner still have `settings.mapping_files.modify` on the app?
