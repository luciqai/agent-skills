# Troubleshooting

Error → cause → fix, plus the permission model and unsymbolicated-crash triage.

## Reading a failure correctly

| Signal | Where it goes |
| --- | --- |
| CLI errors — `✗ Request failed (…)`, `✗ Not authenticated`, validation messages | **stdout** |
| Upload errors — same causes, but prefixed `✗ Upload failed: …` | **stdout** |
| Argument errors — `No value provided for required options '--mode'`, `Expected '--mode' to be one of …` | **stderr** |
| Any failure | exit code non-zero |

So **the exit code is the only reliable signal**. `cmd 2>/dev/null` still shows API errors; an empty stderr does not mean success. Capture stdout and check `$?`.

## Errors

| Message | Cause | Fix |
| --- | --- | --- |
| `✗ Not authenticated. Run: luciq login` | no token in `LUCIQ_AUTH_TOKEN` or `~/.luciqrc` | `luciq login`, or export the env var. In CI, confirm the secret is actually injected into *this* job |
| `✗ Request failed (401): {"error":"Invalid credentials"}` | token wrong, revoked, rotated, or from a different cluster | regenerate at `dashboard.luciq.ai/company/luciq-cli` and `luciq login` again. On self-hosted, confirm `LUCIQ_URL` matches the cluster the token came from |
| `✗ Request failed (403): You do not have permission to use the CLI` | account lacks `account_management.cli.view` | ask an admin to grant it — **final**, no retry will help |
| `✗ Request failed (403)` naming a permission or plan | role lacks that command's permission, or the plan doesn't include the feature | request the permission, or use a command the plan covers — **final** |
| `✗ Upload failed: Request failed (403): {"error":"Missing permission: settings.mapping_files.modify"}` | token may use the CLI, but not upload symbols | ask an admin for the Mapping Files *modify* permission. A working `luciq whoami` never implies this one |
| `✗ Upload failed: Request failed (404): {"error":"Application not found: my-app (staging)"}` | that **slug + mode pair** isn't in your accessible apps — usually a mode that doesn't exist for the app, or a typo | `luciq apps list` and match both fields; the app must exist in that exact mode |
| `✗ Upload failed: Request failed (400): {"error":"slug and mode are required"}` | flags reached the server empty | pass both explicitly; don't rely on a config default — there isn't one |
| `✗ Request failed (429): {"message":"Rate limit exceeded"}` | over 100 requests / 60 s **from this IP** | back off and retry; stagger scheduled jobs; stop parallelizing pagination |
| `✗ Request failed (404): {"error":"Unknown tool: …"}` | CLI newer than the server, or a stale/patched binary | reinstall/upgrade the CLI; on self-hosted, the cluster may predate the command |
| `✗ Request failed (422)` | arguments rejected by the tool's schema — bad enum, wrong type, out-of-range `limit` | re-read `luciq <group> help <subcommand>`; check `--filters` value types (arrays vs objects vs scalars) |
| `✗ Invalid --filters JSON: …` | malformed JSON, or shell-eaten quotes | wrap the whole object in single quotes: `--filters '{"key":["value"]}'` |
| `✗ --filters must be a JSON object` | passed an array or scalar | `--filters` is always an object; only `--sort`, `--views`, `--events`, `--pagination` take other shapes |
| `✗ Provide at least one change (…)` | `bugs update` with no change flags | add `--status`, `--priority`, `--tags`, `--clear-tags`, `--duplicate-of`, or `--action` |
| `✗ Duplicate marking cannot be combined with --status/--priority` | mixed a duplicate action with field edits | run them as two separate commands, or drop one |
| `Expected '--mode' to be one of beta, production, …` | invalid mode (e.g. `prod`) | use the full value — `production` |
| `No value provided for required options '--mode'` | missing required flag | every data command except `apps list` needs `--slug` **and** `--mode` |
| `can't find gem luciq-cli (>= 0.a) with executable luciq` | stale binstub after a Ruby/gem change | `gem install luciq-cli` again; check `which luciq` resolves into the active Ruby |
| `jq: error … Cannot index string with "…"` | piping `alerts list` / `incidents list` into `jq` | those two return CSV rows; use `show --ulid` for JSON, or parse the CSV |
| `jq` returns `null` / `Cannot iterate over object` | used `.[]` on an enveloped response | filter the envelope: `.bugs[]`, `.crashes[]`, `.<metric>_groups[]` |
| `ERROR: "luciq alerts list" was called with arguments [...]` | passed a flag the subcommand doesn't define (e.g. `--limit` on `alerts list`) | drop it — `alerts list` has no pagination flags |
| `✗ File not found:` / `✗ Cannot read file:` | upload path wrong or unreadable | local check, no request was made — fix the path |
| `✗ File must be a .zip archive:` | dSYM / NDK / Flutter-symbols command given a non-zip | zip it first |
| `✗ Source map must be a .json or .txt file:` | RN source-map command given a `.zip` or extensionless map | copy/rename to `.json`, or check you wanted the Flutter command |
| `✗ Invalid architecture:` | `--arch` outside `armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64` | use one of the four; NDK uploads are one per ABI |
| `✗ Upload failed: Request failed (502): {"error":"Upload could not be delivered. Please try again later."}` | gateway couldn't reach the backend symbol service | transient — retry; if it persists it's server-side, not your command |
| Command hangs, then times out | network/proxy, or wrong `LUCIQ_URL` | connect timeout is 30 s and read timeout 300 s (large uploads legitimately take minutes); verify `luciq info`'s URL |

## Permissions per command

Every command runs as the token owner's dashboard role. `account_management.cli.view` gates the CLI as a whole; each command then needs its own permission, and some need a plan entitlement.

| Command | Permission | Plan feature |
| --- | --- | --- |
| `apps list` | — | — |
| `upload *` | `settings.mapping_files.modify` (+ access to the target app) | — |
| `crashes list`, `crashes hangs` | `crashes.list.view` | `crash_reporting` / `app_hangs` |
| `crashes show`, `patterns`, `diagnostics` | `crashes.details.view` | `crash_reporting` |
| `crashes occurrence-tokens`, `occurrence` | `crashes.occurrences.view` | `crash_reporting` |
| `bugs list`, `bugs show` | `bugs.list.view` | — |
| `bugs update` | `bugs.list.modify` (+ `bugs.tags.modify` when touching tags) | — |
| `apm groups` | `<metric>.list.view` (`funnels` → `funnels.list.view`) | `apm` |
| `apm group` | `<metric>.details.view` (`funnels` → `funnels.list.view`) | `apm` |
| `apm occurrence` | `<metric>.occurrence_details.view` | `apm` |
| `apm funnel-events` | `network.list.view` + `screen_loading.list.view` (or just the `--event-type` given) | `apm` |
| `apm funnel-create`, `funnel-update` | `funnels.list.modify` | `apm` |
| `apm funnel-delete` | `funnels.list.delete` | `apm` |
| `reviews list` | `app_reviews.list.view` | — |
| `surveys list` | `surveys.list.view` | `surveys` |
| `surveys show` | `surveys.details.view` | `surveys` |
| `insights` | `app_health.insights.view` | — |
| `issues list` | `issues.list.view` | — |
| `opportunities list`, `show` | `opportunities.list.view` | — |
| `alerts *`, `incidents *` | no extra tool permission | — |

Permission and plan failures are **terminal**. Report them with the command that produced them; retrying, changing filters, or switching to MCP will not route around them — the MCP tools enforce the same checks.

## Unsymbolicated crashes — triage order

The crash is unreadable in the dashboard. Work down this list; the answer is nearly always #1 or #4.

1. **Was anything uploaded for this build?** No upload step, or a step that only runs on debug/PR builds, is the most common cause. Check the release path specifically.
2. **Did the step actually succeed?** Look for `✓` in the build log. A step wrapped in `|| true` / `continue-on-error` fails invisibly.
3. **Right subcommand for the artifact?** Flutter `*-sourcemap` wants a `.zip` of Dart symbols; React Native `*-sourcemap` wants a `.json`/`.txt` map. dSYMs must be zipped.
4. **Do `--version-name` / `--version-code` match the crashing build exactly?** A mismatch uploads fine and deobfuscates nothing — no error anywhere. Compare against the version the crash report itself shows.
5. **Does `--mode` match where the crashes land?** A beta build's symbols uploaded to `production` help nobody. Same silent failure as a version mismatch.
6. **Both halves for hybrid apps?** React Native and Flutter need JS/Dart symbols *and* native symbols. Half-uploaded means half-readable traces.
7. **NDK: one upload per ABI, unstripped?** Stripped `.so` files carry nothing to symbolicate.
8. **iOS with bitcode?** The useful dSYMs are the App Store Connect ones, not the local build's.
9. **Right app?** `--slug` names one app; uploading to a neighbouring app in the same company symbolicates a different dataset. Confirm against `luciq apps list`.

## Version drift

- The Homebrew formula can trail the RubyGems release by a version; `gem install luciq-cli` is the fresher path when you need a just-shipped command.
- `luciq version` tells you what's installed; `luciq help` and `luciq <group> help <subcommand>` tell you what that build supports. When this skill and `help` disagree, `help` wins.
- A stale `~/.rvm`/rbenv shim can leave `luciq` on `PATH` while the gem is gone (`can't find gem luciq-cli`). Reinstall the gem in the active Ruby rather than chasing the binstub.
