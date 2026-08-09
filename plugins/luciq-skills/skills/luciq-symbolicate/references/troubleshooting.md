# Troubleshooting symbol uploads

Error → cause → fix, plus the permission model and unsymbolicated-crash triage.

## Reading a failure correctly

| Signal | Where it goes |
| --- | --- |
| CLI errors — `✗ Request failed (…)`, `✗ Not authenticated`, validation messages | **stdout** |
| Upload errors — same causes, but prefixed `✗ Upload failed: …` | **stdout** |
| Argument errors — `No value provided for required options '--mode'`, `Expected '--mode' to be one of …` | **stderr** |
| Any failure | exit code non-zero |

So **the exit code is the only reliable signal**. `cmd 2>/dev/null` still shows API errors; an empty stderr does not mean success. Capture stdout and check `$?`.

## Auth and access

| Message | Cause | Fix |
| --- | --- | --- |
| `✗ Not authenticated. Run: luciq login` | no token in `LUCIQ_AUTH_TOKEN` or `~/.luciqrc` | `luciq login`, or export the env var. In CI, confirm the secret is actually injected into *this* job |
| `✗ Request failed (401): {"error":"Invalid credentials"}` | token wrong, revoked, rotated, or from a different cluster | regenerate at `dashboard.luciq.ai/company/luciq-cli` and `luciq login` again. On self-hosted, confirm `LUCIQ_URL` matches the cluster the token came from |
| `✗ Request failed (403): You do not have permission to use the CLI` | account lacks `account_management.cli.view` | ask an admin to grant it — **final**, no retry will help |
| `✗ Upload failed: Request failed (403): {"error":"Missing permission: settings.mapping_files.modify"}` | token may use the CLI, but not upload symbols | ask an admin for the Mapping Files *modify* permission. A working `luciq whoami` never implies this one |
| `✗ Request failed (429): {"message":"Rate limit exceeded"}` | over 100 requests / 60 s **from this IP** | back off and retry; stagger matrix builds; a multi-ABI NDK upload draws on the same allowance as everything else on that runner |

Permission and plan failures are **terminal**. Report them with the command that produced them; retrying or switching to the MCP will not route around them, and for uploads there is no MCP tool to switch to.

## Upload failures

| Message | Cause | Fix |
| --- | --- | --- |
| `✗ Upload failed: Request failed (404): {"error":"Application not found: my-app (staging)"}` | that **slug + mode pair** isn't in your accessible apps — usually a mode that doesn't exist for the app, or a typo | `luciq apps list` and match both fields; the app must exist in that exact mode |
| `✗ Upload failed: Request failed (400): {"error":"slug and mode are required"}` | flags reached the server empty | pass both explicitly; don't rely on a config default — there isn't one |
| `✗ File not found:` / `✗ Cannot read file:` | upload path wrong or unreadable | local check, no request was made — fix the path |
| `✗ File must be a .zip archive:` | dSYM / NDK / Flutter-symbols command given a non-zip | zip it first |
| `✗ Source map must be a .json or .txt file:` | RN source-map command given a `.zip` or extensionless map | copy/rename to `.json`, or check you wanted the Flutter command |
| `✗ Invalid architecture:` | `--arch` outside `armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64` | use one of the four; NDK uploads are one per ABI |
| `Expected '--mode' to be one of beta, production, …` | invalid mode (e.g. `prod`) | use the full value — `production` |
| `No value provided for required options '--mode'` | missing required flag | uploads need `--slug` **and** `--mode`, always |
| `✗ Upload failed: Request failed (502): {"error":"Upload could not be delivered. Please try again later."}` | gateway couldn't reach the backend symbol service | transient — retry; if it persists it's server-side, not your command |
| `✗ Request failed (404): {"error":"Unknown tool: …"}` | CLI newer than the server, or a stale/patched binary | reinstall/upgrade the CLI; on self-hosted, the cluster may predate the command |
| `can't find gem luciq-cli (>= 0.a) with executable luciq` | stale binstub after a Ruby/gem change | `gem install luciq-cli` again; check `which luciq` resolves into the active Ruby |
| Command hangs, then times out | network/proxy, or wrong `LUCIQ_URL` | connect timeout is 30 s and read timeout 300 s (large uploads legitimately take minutes); verify the configured URL |

## The failures that produce no error at all

These are the reason symbolication breaks quietly for weeks. The upload returns `✓` and exit `0`, and nothing deobfuscates.

| Mistake | What you see |
| --- | --- |
| `--version-name` / `--version-code` don't match the crashing build | `✓ uploaded successfully!`, traces stay obfuscated |
| `--mode` doesn't match where the crashes land (beta build uploaded to `production`) | `✓ uploaded successfully!`, traces stay obfuscated in the mode you care about |
| Right file, wrong app (`--slug` names a neighbouring app) | `✓ uploaded successfully!`, a different dataset gets symbolicated |
| Only half a hybrid app uploaded (JS/Dart but not native, or vice versa) | half the frames resolve, half don't |
| Stripped `.so` files uploaded for NDK | `✓ uploaded successfully!`, nothing to symbolicate with |

None of these can be caught by checking the exit code. They are caught by reading the version and mode off the build system and the crash report, before uploading.

## Permissions

| Command | Permission | Plan feature |
| --- | --- | --- |
| `apps list` | — | — |
| `upload *` | `settings.mapping_files.modify` (+ access to the target app) | — |

`account_management.cli.view` gates the CLI as a whole; uploads then need the mapping-files permission on top. A token that queries crashes fine can still be refused for uploads.

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
- `luciq version` tells you what's installed; `luciq upload help <subcommand>` tells you what that build supports. When this reference and `help` disagree, `help` wins.
- A stale `~/.rvm`/rbenv shim can leave `luciq` on `PATH` while the gem is gone (`can't find gem luciq-cli`). Reinstall the gem in the active Ruby rather than chasing the binstub.
