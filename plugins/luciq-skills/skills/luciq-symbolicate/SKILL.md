---
name: luciq-symbolicate
description: Use when crash reports or stack traces are unreadable — obfuscated, minified, or showing raw hex addresses and memory offsets instead of class and method names — or when symbol files need to reach Luciq for a build. Covers uploading iOS dSYMs, Android ProGuard/R8 mapping files, NDK `.so` symbols, React Native source maps and Flutter Dart symbols, and wiring those uploads permanently into a release pipeline (GitHub Actions, Fastlane, Gradle, Bitrise, CircleCI, an Xcode build phase, cron). Triggers include "my crashes aren't symbolicated", "the stack trace is obfuscated / unreadable / just hex", "upload dSYMs / mapping / source maps to Luciq", "symbolicate in CI", "add symbol upload to our build", "deobfuscate our crashes", "our beta builds need symbols too". There is NO MCP tool for symbol uploads: the `luciq` CLI is the only path, and this skill installs, authenticates and drives it. For investigating why a crash happens once its trace is already readable use luciq-debug; for exports, scheduled reports or build gating on a metric use luciq-automate.
---

# Symbolicate Luciq crashes

An unreadable crash report is a missing upload, almost always. Symbol files are how Luciq turns `0x1004a2f18` back into `Checkout.applyPromo(Checkout.kt:214)`, and **there is no MCP tool for uploading them** — the `luciq` CLI is the only path. That makes this skill's job narrow and concrete: get the right symbols, for the right build, into the right place, and then make it permanent so nobody has to remember.

Fix the immediate build by hand first, then wire the pipeline. Never the other way round.

## Scope

| Situation | Here? |
| --- | --- |
| Traces are obfuscated, minified, or raw addresses | **yes** |
| Upload dSYM / mapping / NDK / RN source map / Flutter symbols | **yes** |
| Wire symbol upload into CI, Fastlane, Gradle, a release script, or cron | **yes** |
| Beta / staging builds symbolicating differently from production | **yes** |
| "Why is crash AB-1234 happening?" on a *readable* trace | no → `luciq-debug` |
| Export crashes, schedule a report, gate a build on a metric | no → `luciq-automate` |
| First-time SDK integration (the SDK, the `init` call, masking) | no → `luciq-setup`. This skill installs a *CLI*, not an SDK |

## The three invariants

1. **`luciq help` outweighs this skill.** The installed binary is the ground truth; these tables are a map of it. Any rejected flag, unknown subcommand, or surprising required option means: run `luciq upload help <subcommand>` and follow **that**. Never invent a flag, never guess an enum value, never paper over a rejection by retrying the same line.
2. **Never leak a token.** Do not echo, log, commit, or paste a token into a transcript, and do not run `luciq info` in shared output — it prints the configured token in plaintext. In CI, tokens come from the platform's secret store into the environment; a literal token in a workflow file, `Fastfile`, or `build.gradle` is a finding to report, not a step to write.
3. **Never fabricate CLI output.** If a command wasn't run — no auth, no network, user declined — say it wasn't run and show the command. Do not present a plausible-looking `✓ uploaded` line as if it came from the tool.

## Step 1 — install, authenticate, verify

Nothing below works until this does. Confirm it before running anything that talks to the API.

```
- [ ] 1. Is it installed? `luciq version` (also proves the binary resolves)
- [ ] 2. Install if missing — brew or gem
- [ ] 3. Get a CLI token in place — `luciq login`, or `LUCIQ_AUTH_TOKEN` for CI
- [ ] 4. Point at the right cluster if self-hosted (LUCIQ_URL = the API host)
- [ ] 5. Verify: `luciq whoami`. Never declare success without it
```

```bash
brew install luciqai/tap/luciq-cli   # macOS / Linux
gem install luciq-cli                # Ruby >= 2.7
```

**One credential for everything.** The CLI token is generated at [dashboard.luciq.ai/company/luciq-cli](https://dashboard.luciq.ai/company/luciq-cli) → *Generate authentication token* — one per user, shown in full only once — and it authenticates every command, uploads included. You never pass an application token; the server resolves the app from `--slug` + `--mode`.

Two consequences that shape every CI recipe: a CLI token carries the user's **own** dashboard role (it is not a service account, so a pipeline built on it breaks when that person rotates their token or leaves), and **uploads need `settings.mapping_files.modify`** on top of app access — a token that queries fine can still be refused for uploads.

```bash
luciq login                          # prompts, writes ~/.luciqrc
luciq login --auth-token "$TOKEN"    # non-interactive
export LUCIQ_AUTH_TOKEN="$TOKEN"     # or skip login entirely (CI-friendly)
```

**Self-hosted / single-tenant:** set `LUCIQ_URL` to the cluster's **API** host — `https://api.<cluster>.luciq.ai` — not its dashboard host. Env var beats `~/.luciqrc` beats the `https://api.luciq.ai` default. Generate the token from that cluster's own dashboard; a token from one cluster will 401 against another.

**Verify with `luciq whoami`.** It performs a real authenticated call, so it separates "token saved" from "token works". What it does *not* prove is authorization: a green `whoami` says nothing about whether this token may upload symbols. That is a separate permission and the first real upload is what surfaces it.

## Step 2 — upload the symbols

```
- [ ] 1. Detect the platform (iOS / Android / React Native / Flutter) and the build system
- [ ] 2. Locate the real artifact for THIS build — never guess a path that isn't on disk
- [ ] 3. Pick the exact subcommand + required flags   → references/upload-matrix.md
- [ ] 4. Confirm the flag set against `luciq upload help <subcommand>`
- [ ] 5. Run one upload manually and confirm the ✓ before touching any CI file
```

The command shape is uniform:

```bash
luciq upload <SUBCOMMAND> FILE --slug my-app --mode production [--version-name … --version-code … --arch …]
```

Requirements by file type — the part people get wrong:

| Type | Subcommands | Required beyond `--slug` / `--mode` | Extension enforced |
| --- | --- | --- | --- |
| dSYM | `*-ios-dsym` | nothing | `.zip` |
| Mapping | `*-android-mapping` | `--version-name`, `--version-code` | any |
| RN source map | `react-native-*-sourcemap` | `--version-name`, `--version-code` (+ optional `--codepush`) | `.json` / `.txt` |
| Flutter Dart symbols | `flutter-*-sourcemap` | `--version-name`, `--version-code` | `.zip` |
| NDK | `*-ndk` | `--version-name`, `--arch` — **`--arch` instead of `--version-code`** | `.zip` |

**Three flags fail silently. They are the whole reason this skill exists.**

`--mode` is the environment the *build* reports to: a TestFlight/beta pipeline uploads to `beta`, not `production`. Symbols in the wrong mode symbolicate nothing in the mode where the crashes land.

`--version-name` / `--version-code` must match the build the crashes will come from, exactly. A mapping uploaded under the wrong version silently fails to deobfuscate anything — it doesn't error, so nothing tells you but the still-obfuscated stack trace weeks later. Read the version from the build system (`versionName`/`versionCode`, `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`, `pubspec.yaml`, `package.json` + native config), not from memory.

The CLI checks the file locally first — exists, readable, right extension — so a bad path or a `.zip`-vs-`.json` mixup fails instantly and for free. On success it prints `✓ … uploaded successfully!` and exits `0`; on failure, `✗ Upload failed: <message>` and non-zero, which is what makes a failed upload fail the CI job.

Per-platform artifact locations, the Flutter `.zip`-vs-RN-`.json` trap, and the full subcommand matrix are in `references/upload-matrix.md`.

## Step 3 — wire it into the pipeline

```
- [ ] 6. Wire it into the pipeline, token from a secret   → references/ci-recipes.md
- [ ] 7. Show the diff, state where the secret must be configured, and stop
```

Step 5 above is a **hard gate on this step**: a committed pipeline step that has never successfully uploaded once is an untested change shipped into a release path. One manual run proves the artifact path, the credentials, the upload permission, the app/mode resolution, and the flag set in a single shot — and its failure message tells you which of them is wrong. `luciq whoami` proves none of that.

Platform-specific pipeline snippets (GitHub Actions, Fastlane, Gradle, Bitrise, CircleCI, an Xcode build phase, cron) are in `references/ci-recipes.md`.

**Rate limit applies to uploads too.** The gateway allows 100 requests per 60 seconds keyed by source IP, and that budget covers *every* command. A matrix build pushing symbols for several platforms and ABIs at once draws on the same allowance as a shared CI runner's other traffic. Treat `429` as back-off-and-retry, not as failure.

## When a crash is still unreadable after an upload

Work down this list; the answer is nearly always #1 or #4. Full triage detail, per-error causes and fixes are in `references/troubleshooting.md`.

1. **Was anything uploaded for this build?** No upload step, or a step that only runs on debug/PR builds, is the most common cause.
2. **Did the step actually succeed?** Look for `✓` in the build log. A step wrapped in `|| true` / `continue-on-error` fails invisibly.
3. **Right subcommand for the artifact?** Flutter `*-sourcemap` wants a `.zip` of Dart symbols; React Native `*-sourcemap` wants a `.json`/`.txt` map. dSYMs must be zipped.
4. **Do `--version-name` / `--version-code` match the crashing build exactly?** Compare against the version the crash report itself shows.
5. **Does `--mode` match where the crashes land?**
6. **Both halves for hybrid apps?** React Native and Flutter need JS/Dart symbols *and* native symbols.
7. **NDK: one upload per ABI, unstripped?** Stripped `.so` files carry nothing to symbolicate.
8. **iOS with bitcode?** The useful dSYMs are the App Store Connect ones, not the local build's.
9. **Right app?** Confirm `--slug` against `luciq apps list`.

## Grounding facts

| | |
| --- | --- |
| Config precedence | `LUCIQ_AUTH_TOKEN` / `LUCIQ_URL` → `~/.luciqrc` (`token=`, `url=`) → default `https://api.luciq.ai` |
| Exit codes | `0` success, non-zero failure. **The exit code is the reliable signal** — CLI errors (`✗ …`) print to stdout while Thor's argument errors go to stderr, so never infer success from an empty stderr |
| Authorization | `account_management.cli.view` gates the CLI itself; uploads additionally need `settings.mapping_files.modify`. Permission and plan errors are **final** — report them, don't retry |
| Rate limit | 100 requests / 60 s per source IP → `429 Rate limit exceeded` |
| `apps list` | the only data command with no `--slug` / `--mode`; use it to resolve a real slug |

## Reference map

| File | Use it for |
| --- | --- |
| `references/upload-matrix.md` | per-platform upload subcommands, artifact locations, required flags, file-format traps |
| `references/ci-recipes.md` | GitHub Actions, Fastlane, Gradle, Bitrise, CircleCI, Xcode build phase, cron |
| `references/troubleshooting.md` | error → cause → fix, upload permissions, unsymbolicated-crash triage |

## Style

- Show the command before running it, and show it as it will actually be run — real slug, real path, secrets as `"$VAR"`.
- Prefer one correct command over a wall of alternatives.
- Quote the CLI's actual error text when something fails; don't paraphrase it into something friendlier and less diagnostic.
- Say "not run" plainly when you couldn't run it.
- When a flag doesn't exist, run `help` and correct the command — don't rationalize the rejection.

## Red Flags — STOP and surface to the user

- "There's probably a `--json` / `--since` / `--all` flag." There probably isn't. `help` is one call away, and an invented flag is a broken command handed to a user.
- "I'll put the token inline so the example is copy-pasteable." That's a leaked credential in a file or a transcript. Secret store → env var → `"$VAR"`, always.
- "I'll pass the app token to the upload." There is no `--app-token`. Uploads take `--slug` / `--mode` and use the CLI login, and they need `settings.mapping_files.modify`.
- "The upload path looks right, I'll commit the CI step." Not until one manual run printed `✓`. Untested release-path changes are how symbolication silently breaks.
- "Close enough on `--version-name` / `--version-code` / `--mode`." All three fail *silently* — the upload succeeds and nothing deobfuscates.
- "I'll paste the `apps list` output so we can see the apps." It contains every app's token. Project the fields you need instead.
- "MCP is blocked, I'll shell out to the CLI instead." For *data* that won't work: same backend, same permissions, same plan gates. Uploads are the one genuine capability the CLI has and the MCP doesn't.
- "`luciq info` will help me debug this." It prints the token in plaintext. Use `luciq whoami`.

The pattern: every shortcut here trades a verifiable command for a plausible-looking one. A command that was never run, or a pipeline step that never uploaded, is the failure this skill exists to prevent.
