---
name: luciq-cli
description: Use when the deliverable is a terminal command, a build-pipeline step, or a script rather than a conversational answer — installing and authenticating the `luciq` CLI, uploading symbol files (iOS dSYMs, Android ProGuard/R8 mappings, NDK `.so` files, React Native source maps, Flutter Dart symbols), wiring those uploads into CI (GitHub Actions, Fastlane, Gradle, Bitrise, CircleCI, an Xcode build phase), or turning a data question into a repeatable `luciq ...` command that pipes into `jq`. Also use when the deliverable is DATA rather than an explanation and the volume or repetition makes the CLI the better instrument: exporting or dumping a large set (all crashes, all bugs, every app) to a file or spreadsheet, counting or aggregating across many records or several apps, feeding Luciq data into another script or tool, anything that must run on a schedule or unattended, and anything that needs an exit code to gate a build. Triggers include "export all ...", "dump ... to CSV", "how many ... per version", "totals by ...", "across all our apps", "every Monday", "on a cron", "in our pipeline", "fail the build if ...", "pipe into ...", "install the Luciq CLI", "luciq login", "upload dSYMs / mapping / source maps to Luciq", "my crashes aren't symbolicated", "symbolicate in CI", "automate Luciq", "what's the luciq command for X", "script this Luciq query". Symbol uploads have NO MCP equivalent — the CLI is the only path, so route every symbolication-upload request here. For a one-off answer about production data inside an IDE conversation, the MCP tools are the better instrument (luciq-debug, luciq-readout); for first-time SDK integration use luciq-setup.
---

# Luciq CLI

Drive Luciq from a shell: `luciq`. Two halves, with different auth and different reasons to exist.

- **Symbol uploads** (`luciq upload …`) — iOS dSYMs, Android ProGuard/R8 mappings, NDK `.so` files, React Native source maps, Flutter Dart symbols. **There is no MCP tool for uploads.** If a crash report is unsymbolicated, the CLI is the only fix, and a build pipeline is where it belongs.
- **Data commands** (`luciq crashes|bugs|apm|reviews|surveys|apps|issues|opportunities|alerts|incidents|insights`) — each one proxies to the *same server-side tool* the Luciq MCP server exposes, under the *same* role permissions and plan entitlements. The CLI's value over MCP is not extra data; it is **determinism, composability, and volume**. Determinism and composability are the primary case: an exact command you can commit, schedule, diff, and pipe. Volume is the quieter one: the MCP returns whole records into the conversation, so answering "how many per version" through it means reading every record in order to count them. The CLI can do the counting before anything reaches the conversation.

The skill turns on two questions, in order.

1. **Is the deliverable a command, a pipeline step, or a script?** If yes, this skill's job.
2. **If they asked a question, would the CLI still be the better instrument?** It is whenever the answer needs *many* records but the user wants *few* (a count, a total, a breakdown), spans several apps, has to land in a file or another tool, has to run unattended or on a schedule, or has to gate something on an exit code. Reach for the CLI in those cases even though nobody said "command".

A genuinely conversational one-off about a single item is still MCP's job: one crash, one bug, one readout for a human. **The test is not how the request was phrased, it is what the job actually needs.**

## CLI or MCP — decide before doing anything

| Situation | Instrument |
| --- | --- |
| Upload dSYMs / mapping / NDK / source maps | **CLI only** — no MCP tool exists |
| Wire symbolication into CI, Fastlane, Gradle, a release script, or cron | **CLI** |
| "Give me a command I can re-run / commit / schedule" | **CLI** |
| Output must pipe into `jq`, a shell script, or another tool | **CLI** |
| Export or dump a large set to a file or spreadsheet | **CLI** |
| A count, total, or breakdown that needs many records to compute | **CLI** — aggregate in the pipe |
| Anything spanning several apps at once | **CLI** |
| Must run on a schedule or unattended | **CLI** — no MCP client in cron |
| Must gate a build on the result | **CLI** — the MCP has no exit code |
| Non-interactive environment (CI job, cron, container) with no MCP client | **CLI** |
| "Why is crash AB-1234 happening?" — root-cause with repo context | MCP → `luciq-debug` |
| "How is the app doing this week?" — a readout for humans | MCP → `luciq-readout` |
| Author or audit alert rules conversationally | MCP → `luciq-alert-config` / `luciq-alert-gaps` / `luciq-alert-noise` |
| Deduplicate the bug list by a custom rule | MCP → `luciq-group-bugs` |

Both paths hit the same backend, so **never** present the CLI as a workaround for missing MCP access to data: if a permission or plan blocks the MCP tool, it blocks the CLI command too. The one genuine capability gap runs the other way — uploads.

## When NOT to use this skill

- **First-time SDK integration** (adding the SDK, the `init` call, invocation, masking) → `luciq-setup`. This skill installs a *CLI*, not an SDK.
- **Investigating a signal and proposing a code fix** → `luciq-debug`.
- **Composing a report for an audience** → `luciq-readout`.
- **A conversational one-off question** the MCP can answer in one call. Shelling out to the CLI to answer it is slower, needs a separate token, and produces the same numbers.

If the request fits one of those, route there and stop.

## The three invariants

1. **`luciq help` outweighs this skill.** The installed binary is the ground truth; these tables are a map of it. Any rejected flag, unknown subcommand, or surprising required option means: run `luciq <group> help <subcommand>` (or `luciq upload help <subcommand>`) and follow **that**. Never invent a flag, never guess an enum value, never paper over a rejection by retrying the same line.
2. **Never leak a token.** Do not echo, log, commit, or paste a token into a transcript, and do not run `luciq info` in shared output — it prints the configured token in plaintext. In CI, tokens come from the platform's secret store into the environment; a literal token in a workflow file, `Fastfile`, or `build.gradle` is a finding to report, not a step to write.
3. **Never fabricate CLI output.** If a command wasn't run — no auth, no network, user declined — say it wasn't run and show the command. Do not present a plausible-looking JSON body, crash count, or `✓ uploaded` line as if it came from the tool.

## Pick a track

```
- [ ] A. Install / authenticate / verify         → the CLI isn't installed, isn't logged in, or 401s
- [ ] B. Symbol uploads + CI wiring              → unsymbolicated crashes, release pipeline work
- [ ] C. Query or script a data command          → "give me the command for X", jq pipelines
- [ ] D. A write command                          → bugs update, alerts/incidents, funnels  ⛔ approval gate
```

Tracks compose: B and C both require A to have succeeded. Always confirm A before running anything that talks to the API.

## Track A — install, authenticate, verify

```
- [ ] 1. Is it installed? `luciq version` (also proves the binary resolves)
- [ ] 2. Install if missing — brew, gem, or from source
- [ ] 3. Get a CLI token in place — `luciq login`, or `LUCIQ_AUTH_TOKEN` for CI
- [ ] 4. Point at the right cluster if self-hosted (LUCIQ_URL = the API host)
- [ ] 5. Verify: `luciq whoami`. Never declare success without it
```

**Install** (fastest first):

```bash
brew install luciqai/tap/luciq-cli   # macOS / Linux
gem install luciq-cli                # Ruby >= 2.7
```

From source when contributing to the CLI itself: clone, `bundle install`, `bundle exec rake install`.

**One credential for everything.** The CLI token is generated at [dashboard.luciq.ai/company/luciq-cli](https://dashboard.luciq.ai/company/luciq-cli) → *Generate authentication token* — one per user, shown in full only once — and it authenticates every command, uploads included. You never pass an application token; the server resolves the app from `--slug` + `--mode`.

Two consequences that shape every CI recipe: a CLI token carries the user's **own** dashboard role (it is not a service account, so a pipeline built on it breaks when that person rotates their token or leaves), and **uploads need `settings.mapping_files.modify`** on top of app access — a token that queries fine can still be refused for uploads.

```bash
luciq login                          # prompts, writes ~/.luciqrc
luciq login --auth-token "$TOKEN"    # non-interactive
export LUCIQ_AUTH_TOKEN="$TOKEN"     # or skip login entirely (CI-friendly)
```

**Self-hosted / single-tenant:** set `LUCIQ_URL` to the cluster's **API** host — `https://api.<cluster>.luciq.ai` — not its dashboard host. Env var beats `~/.luciqrc` beats the `https://api.luciq.ai` default. Generate the token from that cluster's own dashboard; a token from one cluster will 401 against another.

**Verify with `luciq whoami`.** It performs a real authenticated call, so it separates "token saved" from "token works". What it does *not* prove is authorization: it checks only that the token may use the CLI at all, so a green `whoami` says nothing about whether this token can read crashes or upload symbols. Those are separate per-command permissions, and the first real command is what surfaces them. `luciq info` shows version + URL + token — useful locally, never in shared output.

## Track B — symbol uploads and CI wiring

Unsymbolicated crashes are the symptom; a missing upload step is almost always the cause. Fix the immediate build by hand, then make it permanent in the pipeline.

```
- [ ] 1. Detect the platform (iOS / Android / React Native / Flutter) and the build system
- [ ] 2. Locate the real artifact for THIS build — never guess a path that isn't on disk
- [ ] 3. Pick the exact subcommand + required flags   → references/upload-matrix.md
- [ ] 4. Confirm the flag set against `luciq upload help <subcommand>`
- [ ] 5. Run one upload manually and confirm the ✓ before touching any CI file
- [ ] 6. Wire it into the pipeline, token from a secret   → references/ci-recipes.md
- [ ] 7. Show the diff, state where the secret must be configured, and stop
```

Step 5 is a **hard gate**: a committed pipeline step that has never successfully uploaded once is an untested change shipped into a release path. One manual run proves the artifact path, the credentials, the upload permission, the app/mode resolution, and the flag set in a single shot — and its failure message tells you which of them is wrong. `luciq whoami` proves none of that.

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

`--mode` is the environment the *build* reports to: a TestFlight/beta pipeline uploads to `beta`, not `production`. Symbols in the wrong mode symbolicate nothing in the mode where the crashes land.

`--version-name` / `--version-code` must match the build the crashes will come from, exactly. A mapping uploaded under the wrong version silently fails to deobfuscate anything — it doesn't error, so nothing tells you but the still-obfuscated stack trace weeks later. Read the version from the build system (`versionName`/`versionCode`, `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`, `pubspec.yaml`, `package.json` + native config), not from memory.

The CLI checks the file locally first — exists, readable, right extension — so a bad path or a `.zip`-vs-`.json` mixup fails instantly and for free. On success it prints `✓ … uploaded successfully!` and exits `0`; on failure, `✗ Upload failed: <message>` and non-zero, which is what makes a failed upload fail the CI job. Per-platform artifact locations, the Flutter `.zip`-vs-RN-`.json` trap, and the full subcommand matrix are in `references/upload-matrix.md`. Platform-specific pipeline snippets are in `references/ci-recipes.md`.

## Track C — query and script

```
- [ ] 1. Resolve the app: `luciq apps list` → real slug. Never guess or invent one
- [ ] 2. Confirm the mode (default `production`; each mode is a SEPARATE dataset)
- [ ] 3. Choose the command + typed flags   → references/command-reference.md
- [ ] 4. Anything with no typed flag goes through --filters '<json>'
- [ ] 5. Run it, or hand it over if the environment can't
- [ ] 6. Only pipe to jq after confirming the output is actually JSON
```

`--slug` and `--mode` are required on every data command except `apps list`. Modes are `production`, `beta`, `staging`, `alpha`, `qa`, `development`; querying the wrong mode returns real, correct, *irrelevant* data — which is worse than an error, so confirm it rather than assuming.

**Typed flags first, `--filters` as the escape hatch.** Common filters have flags (`--status`, `--platform`, `--type`, `--app-version`, `--priority`, `--rating`, …); everything else the underlying tool accepts goes in the raw JSON object, which is merged with the typed flags (**typed flags win** on key conflicts):

```bash
luciq crashes list --slug my-app --mode production --status open --limit 20 \
  --filters '{"devices":["iPhone15,2"],"os_versions":["17.4"]}'
```

**Aggregate on the command line, do not read records in order to count them.** When the user wants a number, a breakdown, or a short list, do the reduction in the pipe. Every record printed is a record read into the conversation, and on a real account that is hundreds of them for an answer three lines long.

```bash
# WRONG: pages every open crash into the conversation just to group them
luciq crashes list --slug my-app --mode production --status open --limit 50 --offset 0
luciq crashes list --slug my-app --mode production --status open --limit 50 --offset 50   # ...and so on

# RIGHT: same answer, reduced before it is ever read
for off in 0 50 100 150; do
  luciq crashes list --slug my-app --mode production --status open --limit 50 --offset $off
done | jq -s '[.[].crashes[]] | group_by(.app_version)
               | map({version: .[0].app_version, count: length}) | sort_by(-.count)'
```

On a 208-crash account the first form is roughly 39,000 characters and the second is under 200. The same rule covers exports and handoffs: redirect into the file the user asked for (`> crashes.csv`) or pipe straight into their tool. Do not print a large payload and then describe it.

**Output is mostly JSON, but not uniformly, and the JSON is enveloped.** The CLI pretty-prints whatever parses as JSON and passes anything else through verbatim. Verified against live data:

| Command | Output |
| --- | --- |
| `crashes list` / `crashes hangs` | `{"crashes": [...]}` |
| `bugs list` | `{"bugs": [...]}` |
| `reviews list` / `surveys list` | `{"reviews": [...]}` / `{"surveys": [...]}` |
| `apps list` | `{"applications": [...]}` — **includes each app's token; treat as secret** |
| `apm groups` | `{"<metric>_groups": [...], "next_offset", "total_groups_count"}` |
| `issues list` | `{"issues": [...], "issues_count", …_pagination_token}` |
| `opportunities list` | `{"opportunities": [...], "total_count", "enabled"}` |
| `alerts list`, `incidents list` | **CSV** — header row + one row per record |
| `show` / `diagnostics` / `insights` / `alerts init` / `funnel-events` | JSON object |

So a `jq` filter is `.bugs[]`, not `.[]` — and on `alerts list` / `incidents list` it fails outright, in a way that reads like an auth or empty-result problem. Check the first line of output before piping.

**Pagination and rate limits.** `--offset` / `--limit` page through results (`limit` caps at 50 on `crashes list`, `bugs list`, and `issues list`; `apm funnel-events` caps at 25). The gateway allows **100 requests per 60 seconds, keyed by source IP** — and that budget covers *every* command, uploads included, so a matrix build pushing symbols for several platforms and ABIs at once draws on the same allowance as a shared CI runner's queries. Page deliberately, don't fan out pagination in parallel, and treat `429` as back-off-and-retry, not as failure. When a scope needs more pages than you're willing to pull, say what you covered; never present a first page as the whole set.

## Track D — writes ⛔

`bugs update`, `alerts create|update|delete`, `incidents resolve|reopen`, and `apm funnel-create|funnel-update|funnel-delete` change production state. There is no `--dry-run` and no undo for most of them.

```
- [ ] 1. Confirm the target (slug, mode, number/ulid) against a read command first
- [ ] 2. For alerts: `luciq alerts init` FIRST — build --payload only from what init exposes
- [ ] 3. Show the exact command you intend to run, verbatim
- [ ] 4. ⛔ Wait for explicit approval. No approval, no write
- [ ] 5. Run one command at a time; report each result honestly, including failures
```

Never batch writes behind a single approval unless the user approved the batch and its contents. Specifics that bite:

- `bugs update` needs at least one change, and duplicate marking (`--duplicate-of` / `--action`) **cannot** be combined with `--status` / `--priority`. Marking a duplicate overwrites the duplicate's status, priority, and assignee from the master and is not fully reversible — for rule-based deduplication across many bugs, hand off to `luciq-group-bugs`, which has the plan-and-approve machinery for it.
- `alerts create|update` take a raw `--payload` JSON object. Guessing its shape wastes a write and can create a wrong alert; `luciq alerts init` returns the valid types, triggers, conditions, and actions for *that* app.
- `apm funnel-update --events` **replaces** the funnel's entire step set — it is not a merge.

## Grounding facts

| | |
| --- | --- |
| Config precedence | `LUCIQ_AUTH_TOKEN` / `LUCIQ_URL` → `~/.luciqrc` (`token=`, `url=`) → default `https://api.luciq.ai` |
| Exit codes | `0` success, non-zero failure. **The exit code is the reliable signal** — CLI errors (`✗ …`) print to stdout while Thor's argument errors go to stderr, so never infer success from an empty stderr |
| Authorization | `account_management.cli.view` gates the CLI itself; each command additionally needs its own role permission and plan entitlement, and uploads need `settings.mapping_files.modify`. Permission and plan errors are **final** — report them, don't retry |
| Rate limit | 100 requests / 60 s per source IP → `429 Rate limit exceeded` |
| `apps list` | the only data command with no `--slug` / `--mode` |

## Reference map

Load only what the current track needs:

| File | Use it for |
| --- | --- |
| `references/command-reference.md` | every group, subcommand, typed flag, sort field, and `--filters` key |
| `references/upload-matrix.md` | per-platform upload subcommands, artifact locations, required flags, file-format traps |
| `references/ci-recipes.md` | GitHub Actions, Fastlane, Gradle, Bitrise, CircleCI, Xcode build phase, cron |
| `references/troubleshooting.md` | error → cause → fix, per-command permissions, unsymbolicated-crash triage |

## Style

- Show the command before running it, and show it as it will actually be run — real slug, real path, secrets as `"$VAR"`.
- Prefer one correct command over a wall of alternatives.
- Quote the CLI's actual error text when something fails; don't paraphrase it into something friendlier and less diagnostic.
- Say "not run" plainly when you couldn't run it.
- When a flag doesn't exist, run `help` and correct the command — don't rationalize the rejection.

## Red Flags — STOP and surface to the user

If you catch yourself thinking any of these, stop:

- "There's probably a `--json` / `--since` / `--all` flag." There probably isn't. `help` is one call away, and an invented flag is a broken command handed to a user.
- "I'll put the token inline so the example is copy-pasteable." That's a leaked credential in a file or a transcript. Secret store → env var → `"$VAR"`, always.
- "I'll pass the app token to the upload." There is no `--app-token`. Uploads take `--slug` / `--mode` and use the CLI login, and they need `settings.mapping_files.modify`.
- "The upload path looks right, I'll commit the CI step." Not until one manual run printed `✓`. Untested release-path changes are how symbolication silently breaks.
- "Close enough on `--version-name` / `--version-code` / `--mode`." All three fail *silently* — the upload succeeds and nothing deobfuscates.
- "I'll pipe it to `jq` with `.[]`." The JSON is enveloped (`.bugs[]`, `.crashes[]`, `.network_groups[]`), and `alerts list` / `incidents list` aren't JSON at all.
- "I'll paste the `apps list` output so we can see the apps." It contains every app's token. Project the fields you need instead.
- "MCP is blocked, I'll shell out to the CLI instead." Same backend, same permissions, same plan gates — the block will hold. Report it.
- "I'll page all the records in and then count them." That is the CLI used as a slower MCP. If the user asked for a count, a total, or a breakdown, the counting belongs in `jq` before anything is read.
- "They asked a question, so this is MCP's job." Not if the answer needs hundreds of records, spans several apps, has to land in a file, or has to run unattended. Phrasing is not the test.
- "I'll paginate until it's all in." Watch the 100-req/60-s IP budget, and never pass off page one as the full set.
- "I'll just run the write; it's obviously what they meant." Writes are gated on explicit approval, shown verbatim first.
- "`luciq info` will help me debug this." It prints the token in plaintext. Use `luciq whoami`.

The pattern: every shortcut here trades a verifiable command for a plausible-looking one. A command that was never run, or a pipeline step that never uploaded, is the failure this skill exists to prevent.
