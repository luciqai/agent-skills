# Troubleshooting data commands

Error → cause → fix, plus the per-command permission model and the output-shape traps.

## Reading a failure correctly

| Signal | Where it goes |
| --- | --- |
| CLI errors — `✗ Request failed (…)`, `✗ Not authenticated`, validation messages | **stdout** |
| Argument errors — `No value provided for required options '--mode'`, `Expected '--mode' to be one of …` | **stderr** |
| Any failure | exit code non-zero |

So **the exit code is the only reliable signal**. `cmd 2>/dev/null` still shows API errors; an empty stderr does not mean success. Capture stdout and check `$?`. This matters twice over in a scheduled job or a build gate, where nobody is reading the output at all.

## Auth and access

| Message | Cause | Fix |
| --- | --- | --- |
| `✗ Not authenticated. Run: luciq login` | no token in `LUCIQ_AUTH_TOKEN` or `~/.luciqrc` | `luciq login`, or export the env var. In CI or cron, confirm the secret is actually injected into *this* job |
| `✗ Request failed (401): {"error":"Invalid credentials"}` | token wrong, revoked, rotated, or from a different cluster | regenerate at `dashboard.luciq.ai/company/luciq-cli` and `luciq login` again. On self-hosted, confirm `LUCIQ_URL` matches the cluster the token came from. **A scheduled job that worked for months and now 401s is usually a rotated or departed owner's token** |
| `✗ Request failed (403): You do not have permission to use the CLI` | account lacks `account_management.cli.view` | ask an admin to grant it — **final**, no retry will help |
| `✗ Request failed (403)` naming a permission or plan | role lacks that command's permission, or the plan doesn't include the feature | request the permission, or use a command the plan covers — **final** |
| `✗ Request failed (429): {"message":"Rate limit exceeded"}` | over 100 requests / 60 s **from this IP** | back off and retry; stagger scheduled jobs; stop parallelizing pagination |
| `✗ Request failed (404): {"error":"Unknown tool: …"}` | CLI newer than the server, or a stale/patched binary | reinstall/upgrade the CLI; on self-hosted, the cluster may predate the command |
| `can't find gem luciq-cli (>= 0.a) with executable luciq` | stale binstub after a Ruby/gem change | `gem install luciq-cli` again; check `which luciq` resolves into the active Ruby |

Permission and plan failures are **terminal**. Report them with the command that produced them; retrying, changing filters, or switching to MCP will not route around them — the MCP tools enforce the same checks.

## Arguments and filters

| Message | Cause | Fix |
| --- | --- | --- |
| `No value provided for required options '--mode'` | missing required flag | every data command except `apps list` needs `--slug` **and** `--mode` |
| `Expected '--mode' to be one of beta, production, …` | invalid mode (e.g. `prod`) | use the full value — `production` |
| `✗ Request failed (422)` | arguments rejected by the tool's schema — bad enum, wrong type, out-of-range `limit` | re-read `luciq <group> help <subcommand>`; check `--filters` value types (arrays vs objects vs scalars) |
| `✗ Invalid --filters JSON: …` | malformed JSON, or shell-eaten quotes | wrap the whole object in single quotes: `--filters '{"key":["value"]}'` |
| `✗ --filters must be a JSON object` | passed an array or scalar | `--filters` is always an object; only `--sort`, `--views`, `--events`, `--pagination` take other shapes |
| `ERROR: "luciq alerts list" was called with arguments [...]` | passed a flag the subcommand doesn't define (e.g. `--limit` on `alerts list`) | drop it — `alerts list` has no pagination flags |

## Output shape and `jq`

| Message | Cause | Fix |
| --- | --- | --- |
| `jq: error … Cannot index string with "…"` | piping `alerts list` / `incidents list` into `jq` | those two return CSV rows; use `show --ulid` for JSON, or parse the CSV |
| `jq` returns `null` / `Cannot iterate over object` | used `.[]` on an enveloped response | filter the envelope: `.bugs[]`, `.crashes[]`, `.<metric>_groups[]` |

Check the first line of output before piping. The CLI pretty-prints whatever parses as JSON and passes anything else through verbatim, so a `jq` failure here reads exactly like an auth or empty-result problem and is neither.

## The failure that produces no error at all

**Querying the wrong `--mode`.** Each mode is a separate dataset, so `--mode staging` on an app whose traffic is in `production` returns real, correctly-formed, entirely irrelevant data with exit `0`. Worse than an error, because nothing signals it. Confirm the mode rather than assuming, especially in a scheduled job where nobody eyeballs the result.

The same applies to a first page passed off as the whole set. If a scope needs more pages than you pulled, say what you covered.

## Writes

| Message | Cause | Fix |
| --- | --- | --- |
| `✗ Provide at least one change (…)` | `bugs update` with no change flags | add `--status`, `--priority`, `--tags`, `--clear-tags`, `--duplicate-of`, or `--action` |
| `✗ Duplicate marking cannot be combined with --status/--priority` | mixed a duplicate action with field edits | run them as two separate commands, or drop one |

`apm funnel-update --events` **replaces** the funnel's entire step set rather than merging it. There is no `--dry-run` and no undo for most writes.

## Permissions per command

Every command runs as the token owner's dashboard role. `account_management.cli.view` gates the CLI as a whole; each command then needs its own permission, and some need a plan entitlement.

| Command | Permission | Plan feature |
| --- | --- | --- |
| `apps list` | — | — |
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

## Version drift

- The Homebrew formula can trail the RubyGems release by a version; `gem install luciq-cli` is the fresher path when you need a just-shipped command.
- `luciq version` tells you what's installed; `luciq help` and `luciq <group> help <subcommand>` tell you what that build supports. When this reference and `help` disagree, `help` wins.
- A stale `~/.rvm`/rbenv shim can leave `luciq` on `PATH` while the gem is gone (`can't find gem luciq-cli`). Reinstall the gem in the active Ruby rather than chasing the binstub.
- **Pin the CLI version in any scheduled job or pipeline** (`gem install luciq-cli -v X.Y.Z`). An unpinned install means a command that worked yesterday can change shape under you with nobody watching.
