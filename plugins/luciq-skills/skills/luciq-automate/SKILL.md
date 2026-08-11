---
name: luciq-automate
description: Use when the answer has to leave the conversation — into a file, another tool, a scheduled job, or a build's exit code — rather than being read by a person. Covers exporting or dumping large sets of Luciq data (all crashes, all bugs, every app) to CSV or JSON, counting and aggregating across many records or several apps, feeding Luciq data into a script or spreadsheet, running a report unattended or on a schedule, gating a release on a metric, and turning any Luciq question into a repeatable `luciq ...` command that can be committed, diffed and re-run. Triggers include "export all ...", "dump ... to CSV", "how many ... per version", "totals by ...", "across all our apps", "every Monday", "on a cron", "in our pipeline", "fail the build if ...", "pipe into ...", "what's the luciq command for X", "script this Luciq query", "automate Luciq". Drives the `luciq` CLI, which it installs and authenticates, and aggregates in the pipe rather than reading records in order to count them. For a one-off conversational answer about a single crash, bug or app use luciq-debug or luciq-readout; for uploading symbol files use luciq-symbolicate.
---

# Automate and export Luciq data

Drive Luciq from a shell so the output can go somewhere other than a chat window: a file, a script, a scheduled job, a build gate.

Every data command here proxies to the **same server-side tool** the Luciq MCP server exposes, under the *same* role permissions and plan entitlements. So the CLI's value is never extra data. It is three things the MCP cannot do:

- **Determinism and composability** — an exact command you can commit, diff, schedule and pipe.
- **Volume** — the MCP returns whole records into the conversation, so answering "how many per version" through it means reading every record in order to count them. The CLI can do the counting before anything reaches the conversation.
- **Exit codes** — the MCP has none, so it cannot gate a build.

## Is this skill's job?

The test is not how the request was phrased, it is **what the job actually needs**. Reach for the CLI whenever the answer needs *many* records but the user wants *few* (a count, a total, a breakdown), spans several apps, has to land in a file or another tool, has to run unattended or on a schedule, or has to gate something on an exit code — even though nobody said "command".

| Situation | Instrument |
| --- | --- |
| "Give me a command I can re-run / commit / schedule" | **CLI** |
| Export or dump a large set to a file or spreadsheet | **CLI** |
| A count, total, or breakdown that needs many records to compute | **CLI** — aggregate in the pipe |
| Anything spanning several apps at once | **CLI** |
| Output must pipe into `jq`, a shell script, or another tool | **CLI** |
| Must run on a schedule or unattended | **CLI** — no MCP client in cron |
| Must gate a build on the result | **CLI** — the MCP has no exit code |
| Non-interactive environment (CI job, cron, container) with no MCP client | **CLI** |
| "Why is crash AB-1234 happening?" — root-cause with repo context | MCP → `luciq-debug` |
| "How is the app doing this week?" — a readout for humans | MCP → `luciq-readout` |
| Author or audit alert rules conversationally | MCP → `luciq-alert-config` / `luciq-alert-gaps` / `luciq-alert-noise` |
| Deduplicate the bug list by a custom rule | MCP → `luciq-group-bugs` |
| Upload symbol files, or wire uploads into CI | → `luciq-symbolicate` |

A genuinely conversational one-off about a single item is still MCP's job: one crash, one bug, one readout for a human. Shelling out to the CLI to answer it is slower, needs a separate token, and produces the same numbers.

Both paths hit the same backend, so **never** present the CLI as a workaround for missing MCP access to data: if a permission or plan blocks the MCP tool, it blocks the CLI command too.

## The three invariants

1. **`luciq help` outweighs this skill.** The installed binary is the ground truth; these tables are a map of it. Any rejected flag, unknown subcommand, or surprising required option means: run `luciq <group> help <subcommand>` and follow **that**. Never invent a flag, never guess an enum value, never paper over a rejection by retrying the same line.
2. **Never leak a token.** Do not echo, log, commit, or paste a token into a transcript, and do not run `luciq info` in shared output — it prints the configured token in plaintext. In CI, tokens come from the platform's secret store into the environment; a literal token in a workflow file is a finding to report, not a step to write.
3. **Never fabricate CLI output.** If a command wasn't run — no auth, no network, user declined — say it wasn't run and show the command. Do not present a plausible-looking JSON body or crash count as if it came from the tool.

## Step 1 — install, authenticate, verify

Nothing below works until this does. Confirm it before running anything that talks to the API.

```
- [ ] 1. Is it installed? `luciq version` (also proves the binary resolves)
- [ ] 2. Install if missing — brew or gem
- [ ] 3. Get a CLI token in place — `luciq login`, or `LUCIQ_AUTH_TOKEN` for CI and cron
- [ ] 4. Point at the right cluster if self-hosted (LUCIQ_URL = the API host)
- [ ] 5. Verify: `luciq whoami`. Never declare success without it
```

```bash
brew install luciqai/tap/luciq-cli   # macOS / Linux
gem install luciq-cli                # Ruby >= 2.7
```

**One credential for everything.** The CLI token is generated at [dashboard.luciq.ai/company/luciq-cli](https://dashboard.luciq.ai/company/luciq-cli) → *Generate authentication token* — one per user, shown in full only once. You never pass an application token; the server resolves the app from `--slug` + `--mode`.

A CLI token carries the user's **own** dashboard role. It is not a service account, so **a scheduled job built on it breaks when that person rotates their token or leaves.** Say so out loud when wiring a cron job or a pipeline step: it is the failure mode people are most surprised by six months later.

```bash
luciq login                          # prompts, writes ~/.luciqrc
luciq login --auth-token "$TOKEN"    # non-interactive
export LUCIQ_AUTH_TOKEN="$TOKEN"     # or skip login entirely (CI/cron-friendly)
```

**Self-hosted / single-tenant:** set `LUCIQ_URL` to the cluster's **API** host — `https://api.<cluster>.luciq.ai` — not its dashboard host. Env var beats `~/.luciqrc` beats the `https://api.luciq.ai` default. A token from one cluster will 401 against another.

**Verify with `luciq whoami`.** It performs a real authenticated call, so it separates "token saved" from "token works". It checks only that the token may use the CLI at all, so it says nothing about whether this token can read crashes. Those are separate per-command permissions, and the first real command is what surfaces them.

## Step 2 — build the command

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

## Step 3 — reduce before anything is read

**Aggregate on the command line. Do not read records in order to count them.** When the user wants a number, a breakdown, or a short list, do the reduction in the pipe. Every record printed is a record read into the conversation, and on a real account that is hundreds of them for an answer three lines long.

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

**Output is mostly JSON, but not uniformly, and the JSON is enveloped.** The CLI pretty-prints whatever parses as JSON and passes anything else through verbatim:

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

**Pagination and rate limits.** `--offset` / `--limit` page through results (`limit` caps at 50 on `crashes list`, `bugs list`, and `issues list`; `apm funnel-events` caps at 25). The gateway allows **100 requests per 60 seconds, keyed by source IP**, and that budget covers *every* command — so a scheduled job on a shared CI runner shares its allowance with everything else on that IP. Page deliberately, don't fan out pagination in parallel, and treat `429` as back-off-and-retry, not as failure. When a scope needs more pages than you're willing to pull, say what you covered; never present a first page as the whole set.

## Step 4 — make it repeatable

The point of this skill is that the command outlives the conversation. Whatever the destination, the same rules apply.

- **A file or a spreadsheet** — redirect, don't print. CSV means shaping with `jq -r '… | @csv'`; say which fields you projected.
- **A scheduled job** — token from the environment, never inline. State the token-ownership caveat above. Prefer one command with a redirect over a script that needs its own maintenance.
- **A build gate** — the exit code is the contract. Compute the metric, compare it, `exit 1` on breach, and make the failure message say which threshold broke and what the actual value was.
- **A committed artifact** — put the command where the team will find it (a `Makefile` target, a `scripts/` entry, a documented one-liner in the README) so anyone pulls the same numbers the same way. Show the diff and stop.

## Writes ⛔

`bugs update`, `alerts create|update|delete`, `incidents resolve|reopen`, and `apm funnel-create|funnel-update|funnel-delete` change production state. There is no `--dry-run` and no undo for most of them.

```
- [ ] 1. Confirm the target (slug, mode, number/ulid) against a read command first
- [ ] 2. Show the exact command you intend to run, verbatim
- [ ] 3. ⛔ Wait for explicit approval. No approval, no write
- [ ] 4. Run one command at a time; report each result honestly, including failures
```

Never batch writes behind a single approval unless the user approved the batch and its contents.

**Most writes belong to another skill.** Rule-based deduplication across many bugs → `luciq-group-bugs`, which has the plan-and-approve machinery for it. Authoring or auditing alert rules → `luciq-alert-config` (and for alerts, `luciq alerts init` must run FIRST; build `--payload` only from what init exposes for that app). What is left here is APM funnels, where `apm funnel-update --events` **replaces** the funnel's entire step set rather than merging it.

## Grounding facts

| | |
| --- | --- |
| Config precedence | `LUCIQ_AUTH_TOKEN` / `LUCIQ_URL` → `~/.luciqrc` (`token=`, `url=`) → default `https://api.luciq.ai` |
| Exit codes | `0` success, non-zero failure. **The exit code is the reliable signal** — CLI errors (`✗ …`) print to stdout while Thor's argument errors go to stderr, so never infer success from an empty stderr |
| Authorization | `account_management.cli.view` gates the CLI itself; each command additionally needs its own role permission and plan entitlement. Permission and plan errors are **final** — report them, don't retry |
| Rate limit | 100 requests / 60 s per source IP → `429 Rate limit exceeded` |
| `apps list` | the only data command with no `--slug` / `--mode` |

## Reference map

| File | Use it for |
| --- | --- |
| `references/command-reference.md` | every group, subcommand, typed flag, sort field, and `--filters` key |
| `references/troubleshooting.md` | error → cause → fix, per-command permissions, output-shape and `jq` failures |

## Style

- Show the command before running it, and show it as it will actually be run — real slug, real path, secrets as `"$VAR"`.
- Prefer one correct command over a wall of alternatives.
- Quote the CLI's actual error text when something fails; don't paraphrase it into something friendlier and less diagnostic.
- Say "not run" plainly when you couldn't run it.
- When a flag doesn't exist, run `help` and correct the command — don't rationalize the rejection.

## Red Flags — STOP and surface to the user

- "They asked a question, so this is MCP's job." Not if the answer needs hundreds of records, spans several apps, has to land in a file, or has to run unattended. Phrasing is not the test.
- "I'll page all the records in and then count them." That is the CLI used as a slower MCP. If the user asked for a count, a total, or a breakdown, the counting belongs in `jq` before anything is read.
- "I'll pipe it to `jq` with `.[]`." The JSON is enveloped (`.bugs[]`, `.crashes[]`, `.network_groups[]`), and `alerts list` / `incidents list` aren't JSON at all.
- "There's probably a `--json` / `--since` / `--all` flag." There probably isn't. `help` is one call away, and an invented flag is a broken command handed to a user.
- "I'll paginate until it's all in." Watch the 100-req/60-s IP budget, and never pass off page one as the full set.
- "I'll put the token inline so the example is copy-pasteable." That's a leaked credential in a file or a transcript. Secret store → env var → `"$VAR"`, always.
- "I'll paste the `apps list` output so we can see the apps." It contains every app's token. Project the fields you need instead.
- "MCP is blocked, I'll shell out to the CLI instead." Same backend, same permissions, same plan gates — the block will hold. Report it.
- "I'll just run the write; it's obviously what they meant." Writes are gated on explicit approval, shown verbatim first.
- "`luciq info` will help me debug this." It prints the token in plaintext. Use `luciq whoami`.

The pattern: every shortcut here trades a verifiable command for a plausible-looking one. A command that was never run, or a scheduled job that has never once produced its file, is the failure this skill exists to prevent.
