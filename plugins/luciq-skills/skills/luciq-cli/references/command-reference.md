# Command reference — data commands

Every data command, its typed flags, and the `--filters` keys it accepts. Uploads are in `upload-matrix.md`.

**This file can lag the installed binary.** `luciq <group> help <subcommand>` is authoritative. Use it whenever a flag is rejected.

Flags below are shown in CLI form (`--app-version`); the CLI maps them to the underlying tool's argument names for you.

## Global

| Command | Notes |
| --- | --- |
| `luciq login [--auth-token T]` | Writes `token=` to `~/.luciqrc`. Prompts when the flag is omitted |
| `luciq logout` | Removes the saved token |
| `luciq whoami` | Authenticated call — the only real proof the token works |
| `luciq info` | Version, API URL, and **the token in plaintext**. Never put in shared output |
| `luciq version` / `--version` | CLI version |
| `luciq help [COMMAND]` | Command list, or one command's full option set |

## Shared options

| Option | Applies to | Notes |
| --- | --- | --- |
| `--slug` | every data command except `apps list` | required; get it from `luciq apps list` |
| `--mode` | every data command except `apps list` | required; `production` \| `beta` \| `staging` \| `alpha` \| `qa` \| `development`. Separate dataset per mode |
| `--offset`, `--limit` | list commands | pagination; several commands cap `limit` at 50 |
| `--sort-by`, `--direction` | crashes, bugs | `asc` \| `desc` |
| `--sort-by`, `--sort-direction` | reviews, issues, alerts, incidents | note the different second flag name |
| `--filters '<json>'` | most commands | raw JSON **object**, merged with typed flags; **typed flags win** on key conflicts |

Array-valued typed flags take repeated values space-separated: `--status open in_progress`, `--rating 1 2`.

## `luciq apps`

`list` — the applications you can access. No `--slug` / `--mode`. Optional `--platform ios|android|react_native|flutter`, `--offset`, `--limit`.

Start here in any session: it is the only sanctioned way to learn a slug. Returns `{"applications": [{name, token, slug, mode, created_at, target_os, platform}, …]}` — one row per **app × mode**, so the same slug appears several times.

⚠️ **The response includes each app's SDK token.** Never paste it whole into a transcript, log, or issue; project what you need:

```bash
luciq apps list --limit 50 | jq -r '.applications[] | "\(.slug)\t\(.mode)\t\(.platform)"'
```

## `luciq crashes`

| Subcommand | Flags |
| --- | --- |
| `list` | `--status open\|closed\|in_progress`, `--platform IOS\|ANDROID\|DART\|JAVASCRIPT`, `--type CRASH\|ANR\|OOM\|NON_FATAL`, `--app-version`, page, sort |
| `show` | `--number N` (required) |
| `patterns` | `--number N` (required), `--pattern-key app_versions\|devices\|oses\|current_views\|app_status\|experiments`, `--sort-by occurrences_count\|last_seen\|first_seen`, `--direction` |
| `diagnostics` | `--number N` (required) |
| `hangs` | `--status`, `--platform`, `--app-version`, page, sort |
| `occurrence-tokens` | `--number N` (required), `--current-token`, `--direction first\|last` |
| `occurrence` | `--number N`, `--ulid U` (both required) |

Sort fields for `list` / `hangs`: `last_occurred_at`, `first_occurred_at`, `occurrences_counter`, `affected_users_counter`, `max_app_version`, `min_app_version`, `severity`.

`--filters` keys — `list` / `hangs`:

```
date_ms        {"gte": <ms>, "lte": <ms>}
status_id      [1,2,3]                      1=open 2=closed 3=in_progress
teams          ["<team-id>"]
app_versions   ["1.2.3"]
devices        ["iPhone15,2"]
os_versions    ["17.4"]
platform       ["IOS","ANDROID","DART","JAVASCRIPT"]
current_views  ["<screen-name>"]
type           ["CRASH","ANR","OOM","NON_FATAL"]        (list only)
subtype        ["CRITICAL","ERROR","WARNING","INFO"]    (list only; needs NON_FATAL in type)
feature_flags  ["<flag>" | "<flag> -> <variant>"]       (list only)
```

`patterns`: `date_ms`, `app_versions`, `devices`, `os_versions`.
`occurrence-tokens`: `date_ms`, `app_versions`, `app_status` (`"foreground"|"background"`), `devices`, `os_versions`, `experiments`, `current_views`.

```bash
luciq crashes list --slug my-app --mode production --status open --limit 20
luciq crashes show --slug my-app --mode production --number 42
luciq crashes patterns --slug my-app --mode production --number 42 --pattern-key devices
```

`list` and `hangs` both return `{"crashes": [...]}`; `show` / `patterns` / `diagnostics` / `occurrence` return a JSON object.

`diagnostics` may answer `status: "generating"` with a `retry_after_seconds` — re-run the same command after that delay rather than treating it as an error.

## `luciq bugs`

| Subcommand | Flags |
| --- | --- |
| `list` | `--status new\|closed\|in_progress`, `--priority na\|trivial\|minor\|major\|blocker`, `--app-version`, page, sort |
| `show` | `--number N` (required) |
| `update` | `--number N` (required) + at least one change — see below |

`update` (**write**):

| Flag | Effect |
| --- | --- |
| `--status new\|closed\|in_progress` | new status |
| `--priority na\|trivial\|minor\|major\|blocker` | new priority |
| `--tags a b c` | tags to apply — **appends** to the existing set by default |
| `--tag-action append\|replace\|remove` | how `--tags` is applied: `append` (default, keeps existing), `replace` (sets `--tags` as the full list), `remove` (deletes just those). Cannot be combined with `--clear-tags` |
| `--clear-tags` | remove all tags |
| `--duplicate-of N` | mark this bug a duplicate of master `N` (implies `--action mark_as_duplicate`) |
| `--action mark_as_duplicate\|unmark_as_duplicate` | duplicate action on its own |

Rules the CLI enforces: at least one change, duplicate marking cannot be combined with `--status` / `--priority`, and `--clear-tags` cannot be combined with `--tag-action`. Touching tags needs `bugs.tags.modify` on top of `bugs.list.modify`.

`list` returns `{"bugs": [...]}`, one thin object per bug — `title`, `categories`, `type`, `duplicate_type`, `email`, `status_id`, `priority_id`, `number`, `reported_at`, `last_activity`, `duplicated_bugs_count`. `title` can be `null`. Anything else (tags, screen, app version, logs, team) comes from `show`.

`--filters` keys:

```
status_id    [1,2,3]                    1=New 2=Closed 3=In Progress
priority_id  [-1,1,2,3,4]               -1=N/A 1=Trivial 2=Minor 3=Major 4=Blocker
app_version  ["1.2.3"]
platform     ["ios","android"]          cross-platform apps
type         ["<type>"]
tag          [["login","auth"]]         inner array OR-ed, outer groups AND-ed
category     [["UI"]]
devices      ["iPhone 15 Pro"]
os_versions  ["iOS 17.0"]
experiments  ["<flag>"]
reported_at  {"from": <ms>, "to": <ms>}
```

```bash
luciq bugs update --slug my-app --mode production --number 7 --status closed --priority major
luciq bugs update --slug my-app --mode production --number 7 --duplicate-of 3
```

## `luciq apm`

Metrics: `network`, `launch`, `flows`, `screen_loading`, `frame_drop` — plus `funnels` for `groups` and `group`.

| Subcommand | Flags |
| --- | --- |
| `groups` | `--metric` (required), `--sort '{"by":…,"direction":…}'`, page, `--filters` |
| `group` | `--metric` (required), `--group-uuid` **or** `--group-url`, `--views '<json array>'` (default `["summary"]`), `--method GET\|POST\|…` (network), `--filters` |
| `occurrence` | `--metric` (required), `--selector worst\|by_token\|list` (required), `--group-uuid`/`--group-url`, `--method`, `--token` (by_token), `--current-token`/`--direction`/`--limit` (list), `--filters` |
| `funnel-events` | `--event-type network\|screen_loading`, `--q <substring>`, `--limit` (1–25, default 20) |
| `funnel-create` | `--name` (required), `--events '<json array>'` (required, 2–20 steps) — **write** |
| `funnel-update` | `--ulid` (required), `--name`, `--events` — **write**, `--events` replaces the whole set |
| `funnel-delete` | `--ulid` (required) — **write** |

`--sort` is a JSON **object**; the CLI wraps it in the single-item array the API wants. Sortable `by` values: `failure_rate`, `p95`, `p50`, `apdex`, `apdex_change`, `occurrences`, `dissat_count`, `frozen_frames_percent`, `slow_frames_percent`, `count`, `conversion`, `drop_off`, `median_time` — availability varies by metric.

Funnel step shapes:

```json
{"type":"network","ulid":"<event-ulid>"}
{"type":"screen_loading","ulid":"<event-ulid>"}
{"type":"user_event","name":"<event-name>"}
```

`--filters` keys vary by metric; common ones are `date_ms`, `app_version`, `platform ["ios","android"]`, `device`, `os_version`, `country`, `carrier`, `radio`, `failure_name`, `failure_type`, `response_time_ms`, `custom_attributes`, `experiment`, plus `group_name`, `key_metric`, `count`, `dissat_count`, `apdex`, `apdex_change`, `teams` on `groups`.

```bash
luciq apm groups --slug my-app --mode production --metric network \
  --sort '{"by":"p95","direction":"desc"}'
luciq apm group --slug my-app --mode production --metric network \
  --group-uuid "$UUID" --views '["summary","chart"]'
```

## `luciq reviews`

`list` — `--rating 1..5`, `--country`, `--os ios|android`, `--sort-by date`, `--sort-direction`, page.
`--filters`: `date_ms`, `app_version`, `prompt_type ["custom","native","app_store"]`.

```bash
luciq reviews list --slug my-app --mode production --rating 1 2 --os ios
```

Returns `{"reviews": [{id, title, star_rating, body, …}, …]}`.

## `luciq surveys`

| Subcommand | Flags |
| --- | --- |
| `list` | `--type 0\|1\|2` (0=custom 1=NPS 2=app_store), `--status 0\|1\|2` (0=draft 1=published 2=paused), page |
| `show` | `--id N` (required), `--page` (paginates responses), `--filters` |

`show` `--filters`: `date_ms`, `search_words`, `response_status [0,1]`, `nps <0-10>`, `locale`, `app_versions`, `devices`, `os_versions`, `countries`, `platforms ["ios","android"]`.

`list` returns `{"surveys": [{id, title, type, status, responses_count, …}, …]}` — note `type` and `status` come back as strings (`"nps"`, `"draft"`) even though the flags take the numeric codes.

## `luciq insights`

`luciq insights --slug my-app --mode production` — aggregated app-health snapshot (no subcommand). `--filters`: `date_ms`, `app_version`.

Sections (crashes / bugs / apm / monitoring) can fail independently: one section returning an error while others return data is expected, not a broken command. Report the failed section as unavailable rather than reconstructing it from another command.

## `luciq issues`

`list` — issues across crashes, APM, AI-detected issues, and bugs, ranked by Apdex impact. `--limit` (1–50), `--sort-by apdex_impact|occurrences_counter`, `--sort-direction`, `--top-issues`, `--pagination '<json object of per-source cursor tokens>'`.

`--filters`:

```
date_ms          {"gte": <ms>, "lte": <ms>}    span must be >= 24h
search_tokens    ["<text>"]
app_version      ["1.2.3"]
teams            ["<team-id>"]
platform         ["IOS","ANDROID","DART","JAVASCRIPT"]
apm_types        ["networks","traces","launches","screen_loadings","frame_drops"]
crashes_types    ["CRASH","ANR","OOM","NON_FATAL"]
ai_issues_types  ["visual_issue","broken_functionality"]
bugs_types       ["<type>"]
apdex_severity   ["high","medium","low","no_impact"]
```

Returns `{"issues": [...], "issues_count": N}` plus a separate `*_pagination_token` per source (`apm_`, `crashes_`, `visual_issues_`, `broken_functionality_`, `bugs_`) — feed those back through `--pagination` to page.

## `luciq opportunities`

| Subcommand | Flags |
| --- | --- |
| `list` | `--status open\|in_progress\|closed\|dismissed`, `--priority 1\|2\|3\|4\|unset`, `--team-id <ulid>\|unassigned`, page |
| `show` | `--id N` (required) |

`list` returns `{"enabled": <bool>, "opportunities": [...], "total_count": N}` — when `enabled` is `false` the feature is off for the app and an empty list means nothing more than that.

## `luciq alerts` — alert rules

| Subcommand | Flags |
| --- | --- |
| `list` | `--sort-by latest_creation_date\|last_edit_date\|highest_triggered_count`, `--sort-direction` |
| `show` | `--ulid U` (required), e.g. `crashes_01HX…` |
| `init` | none beyond app — returns the valid types, triggers, conditions, actions for this app |
| `create` | `--payload '<json object>'` (required) — **write** |
| `update` | `--ulid U`, `--payload` (both required) — **write** |
| `delete` | `--ulid U` (required) — **write** |

**Always run `init` before `create` / `update`** and build the payload only from what it exposes. Payload skeleton:

```json
{"type":"Crashes","trigger":"<trigger>","title":"…","operation":0,
 "conditions":[…],"actions":[…],"rule_owner":"<team-id>"}
```

`list` is one of the two commands that return **CSV**, not JSON: `id,type,title,status,trigger,conditions,actions,rule_owner,conditions_met_count`, where `conditions` and `actions` are quoted, serialized blobs inside the row. It also takes **no** `--offset` / `--limit` — passing them is a usage error. When you need structured data for one rule, use `show --ulid`, which returns a JSON object (its identifier field comes back as `id`, not `ulid`).

`init` returns a JSON object keyed by alert type (`"Bugs"`, `"Crashes"`, `"App launches"`, …), each with its `triggers`, `additional_conditions`, and `trigger_options`. Build the payload from those exact values.

For conversational alert authoring, gap analysis, or noise reduction, hand off to `luciq-alert-config` / `luciq-alert-gaps` / `luciq-alert-noise`.

## `luciq incidents` — triggered alerts

| Subcommand | Flags |
| --- | --- |
| `list` | `--sort-by first_triggered\|last_triggered\|count`, `--sort-direction`, `--status open\|manual_resolve\|automatic_resolve`, `--type …`, page, `--filters` |
| `show` | `--ulid U` (required) |
| `resolve` | `--ulid U` (required) — **write** |
| `reopen` | `--ulid U` (required) — **write** |

`--type` values: `overall_app`, `launch`, `screen_loading`, `network`, `trace`, `frame_drop`, `crash`, `anr`, `oom`, `non_fatal`, `fatal_ui_hang`, `feature_experiment`.
`--filters`: `date_ms`, `title ["<token>"]`.

`list` is the other **CSV** command: `ulid,type,title,group_name,status,last_value,first_triggered_ms,last_triggered_ms,count`. `show --ulid` returns JSON.

## Output shapes

Verified against live data. The JSON is enveloped, so `jq` filters key off the envelope, not `.[]`:

| Command | Shape |
| --- | --- |
| `apps list` | `{"applications": [...]}` — **contains app tokens** |
| `crashes list`, `crashes hangs` | `{"crashes": [...]}` |
| `bugs list` | `{"bugs": [...]}` |
| `reviews list` | `{"reviews": [...]}` |
| `surveys list` | `{"surveys": [...]}` |
| `issues list` | `{"issues": [...], "issues_count", …_pagination_token}` |
| `opportunities list` | `{"opportunities": [...], "total_count", "enabled"}` |
| `apm groups` | `{"<metric>_groups": [...], "next_offset", "total_groups_count"}` |
| `apm funnel-events` | `{"events": [...]}` |
| `alerts list`, `incidents list` | **CSV** — header + one row per record |
| `insights`, `alerts init`, any `show` / `patterns` / `diagnostics` / `occurrence` | JSON object |

## Composing with jq

```bash
# worst network endpoints by p95 — note the metric-specific envelope key
luciq apm groups --slug my-app --mode production --metric network \
  --sort '{"by":"p95","direction":"desc"}' --limit 10 \
  | jq '.network_groups[] | {name, p95, failure_rate}'

# blocker bugs still open
luciq bugs list --slug my-app --mode production --status new --priority blocker \
  | jq -r '.bugs[] | "\(.number)\t\(.title // "(untitled)")"'

# open incidents — CSV, so use a CSV tool, not jq
luciq incidents list --slug my-app --mode production --status open | cut -d, -f1,3,5
```

Check exit status, not stderr — CLI errors print to stdout:

```bash
if ! out=$(luciq crashes show --slug my-app --mode production --number 42); then
  echo "luciq failed: $out" >&2
  exit 1
fi
```
