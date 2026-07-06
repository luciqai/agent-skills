# Grouping keys

The grouping key is a normalized, order-independent composite built from the exact fields the customer's logic names. Two bugs group **iff** their keys are byte-for-byte equal. The key is shown verbatim in the plan so every merge is auditable.

This file defines: the recipes (logic → filter set + key), the normalization rules, and which fields come from `list_bugs` vs. require a `bug_details` enrichment call.

## Recipes

| Customer logic | Filter set (`list_bugs`) | Key recipe (per bug) | Needs `bug_details`? |
| --- | --- | --- | --- |
| "same title" | — | `normalize_title(title)` | no |
| "same category" | — | `sorted(categories)` | no |
| "same screen" | — | `current_view` | **yes** (`state.fields.current_view`) |
| "same screen + same failed requests" | — | `current_view` + `failed_requests_sig` | **yes** (current_view + network-log archive) |
| "same failed request only" | — | `failed_requests_sig` | **yes** (network-log archive) |
| "share a tag set" | `tag: [[...]]` (optional, narrows) | `sorted(tags)` | **yes** (`tags` not in `list_bugs` response) |
| "same issue on a version" | `app_version: ["X"]` (optional, narrows) | `app_version` + `normalize_title(title)` | **yes** (`app_version` not in `list_bugs` response) |
| "same user-attribute value" | — | `user_attribute[<name>]` | **yes** (`state.fields.user_attributes`) |
| "same screen + same user steps" | — | `current_view` + `user_steps_sig` | **yes** (current_view + user-steps archive) |

The customer can **combine** any of these — each chosen dimension contributes one component. Combinations join their parts with a stable separator (` | `) in a fixed field order, so `view + failed` always renders the same way regardless of input order.

## Normalization rules

Apply these consistently — they are the difference between "matches" and "almost matches":

- **Titles** (`normalize_title`): lowercase, trim, collapse internal whitespace to a single space. Optionally strip trailing punctuation. Two titles that differ only in case or spacing share a key.
- **URLs / endpoints**: host stripped, **path only**, query string removed (`…/authenticate?aid=x` → `…/authenticate`). Two requests to the same path with different query params collapse to one signature.
- **Sets** (tags, categories, failed requests, steps): sorted before joining, so element order never affects the key.
- **Case**: identifiers compared case-insensitively unless the customer asks otherwise.

## Signal definitions

- **`failed_requests_sig`** — from the bug's network log, take **only non-2xx** entries, render each as `METHOD path STATUS` (path normalized as above), sort, and join. Example: `GET /tlp-digital/.../daily-maintenance 404, POST /transmit/.../authenticate 401`. Successful (2xx) requests are excluded — this is a *failure* signature.
- **`user_steps_sig`** — from the bug's user steps, the condensed screen sequence plus the last couple of actions, e.g. `screen: HomeActivity → CheckoutActivity | last: tap pay_button, tap confirm_button`. De-duplicate consecutive repeated screens before rendering.
- **`user_attribute[<name>]`** — the value of the named user attribute (e.g. `plan`), normalized (lowercased, trimmed).

## Field source map

`list_bugs` returns a **CSV row** per bug with exactly these columns — nothing else:

```
priority_id, status_id, categories, email, number, reported_at, last_activity, title, type, duplicated_bugs_count, duplicate_type
```

Everything a richer key needs comes from `bug_details`:

| Field | Source | Notes |
| --- | --- | --- |
| title | `list_bugs` | use `normalize_title` |
| categories | `list_bugs` | already a set |
| type / duplicate_type / email / status_id / priority_id / number / reported_at / last_activity | `list_bugs` | other CSV columns |
| `current_view` | **`bug_details`** → `state.fields.current_view` | not in `list_bugs` (not even a filter) |
| tags | **`bug_details`** → top-level `tags` | `tag` is a `list_bugs` *filter* only; the value isn't returned |
| app version | **`bug_details`** → `state.fields.app_version` | `app_version` is a `list_bugs` *filter* only; the value isn't returned |
| user attributes | **`bug_details`** → `state.fields.user_attributes` | consent keys (`IBG_USER_CONSENT_*`) are stripped; absent → bug is skipped |
| network log (failed requests) | **`bug_details`** → `state.logs.network_log.url` | a signed **URL**, not data — fetch + parse (see below); needs `bugs.network_logs.view` |
| user steps | **`bug_details`** → `state.logs.user_steps.url` | a signed **URL**, not data — fetch + parse (see below); needs `bugs.user_steps.view` |

Only enrich (`bug_details`) when the chosen key recipe needs a `bug_details` row, and only for the candidates in scope. The inline rows (title, categories, current_view, tags, app version, user attributes) are read straight off the response; the two log rows require the extra fetch+parse step below.

## Fetching the log-archive signals

`failed_requests_sig` and `user_steps_sig` are the only keys whose data the MCP tools do **not** return inline. `bug_details` returns just a signed archive URL, so building these keys is a per-candidate procedure:

1. From `bug_details`, read `state.logs.network_log` (or `state.logs.user_steps`). If it's `{ is_empty_array: true }`, absent, or the permission isn't granted, the bug is **skipped** — never guessed.
2. Take the `url` and **fetch** it with a plain HTTPS GET. The URL is pre-signed (CloudFront), so no auth header is needed; this uses the host's web-fetch capability, not an MCP tool.
3. **Decompress + parse** the archive. In practice these are `base64 → zlib → JSON`; some come as plain JSON. Parse defensively.
4. Derive the signature (`failed_requests_sig` / `user_steps_sig`) from the parsed entries per the definitions above.

This is the same archive-fetch path `luciq-debug` and `luciq-verify` use. If the host has no web-fetch tool, the log-based recipes can't run — say so and fall back to an inline-field key only if the customer agrees.

## Missing fields → skipped, never catch-all

If a bug lacks a field the key requires (no network log, no such user attribute, empty user steps), it gets **no key**. It is reported on the plan's "skipped / not grouped" list with the reason (e.g. `skipped: no network log`). It is **never** placed in a default "everything else" group — a catch-all bucket would produce merges the customer never intended.

## Singletons

After keys are computed, any key held by only one bug is dropped. A group of one is not a duplicate. Only keys shared by ≥2 bugs become proposed merges.
