# Grouping keys

The grouping key is a normalized, order-independent composite built from the exact fields the customer's logic names. Two bugs group **iff** their keys are byte-for-byte equal. The key is shown verbatim in the plan so every merge is auditable.

This file defines: the recipes (logic → filter set + key), the normalization rules, and which fields come from `list_bugs` vs. require a `bug_details` enrichment call.

## Recipes

| Customer logic | Filter set (`list_bugs`) | Key recipe (per bug) | Needs `bug_details`? |
| --- | --- | --- | --- |
| "same title" | — | `normalize_title(title)` | no |
| "same screen" | — | `current_view` | no (from `list_bugs` `current_views`) |
| "same screen + same failed requests" | — | `current_view` + `failed_requests_sig` | **yes** (network log) |
| "same failed request only" | — | `failed_requests_sig` | **yes** |
| "share a tag set" | `tag: [[...]]` (optional) | `sorted(tags)` | no |
| "same category" | — | `sorted(categories)` | no |
| "same crash on a version" | `app_version: ["X"]` | `current_view` + `normalize_title(title)` | no |
| "same user-attribute value" | (filter if the attr is filterable) | `user_attribute[<name>]` | **yes** (attributes) |
| "same screen + same user steps" | — | `current_view` + `user_steps_sig` | **yes** (user steps) |

Combinations join their parts with a stable separator (` | `) in a fixed field order, so `view+failed` always renders the same way regardless of input order.

## Normalization rules

Apply these consistently — they are the difference between "matches" and "almost matches":

- **Titles** (`normalize_title`): lowercase, trim, collapse internal whitespace to a single space. Optionally strip trailing punctuation. Two titles that differ only in case or spacing share a key.
- **URLs / endpoints**: host stripped, **path only**, query string removed (`…/authenticate?aid=x` → `…/authenticate`). This mirrors the production SPQ-350 URL normalizer, so the skill's behavior matches what customers see in automatic grouping.
- **Sets** (tags, categories, failed requests, steps): sorted before joining, so element order never affects the key.
- **Case**: identifiers compared case-insensitively unless the customer asks otherwise.

## Signal definitions

- **`failed_requests_sig`** — from the bug's network log, take **only non-2xx** entries, render each as `METHOD path STATUS` (path normalized as above), sort, and join. Example: `GET /tlp-digital/.../daily-maintenance 404, POST /transmit/.../authenticate 401`. Successful (2xx) requests are excluded — this is a *failure* signature, matching production grouping.
- **`user_steps_sig`** — from the bug's user steps, the condensed screen sequence plus the last couple of actions, e.g. `screen: HomeActivity → CheckoutActivity | last: tap pay_button, tap confirm_button`. De-duplicate consecutive repeated screens before rendering.
- **`user_attribute[<name>]`** — the value of the named user attribute (e.g. `plan`), normalized (lowercased, trimmed).

## Field source map

What `list_bugs` returns vs. what needs a `bug_details` enrichment call:

| Field | Available on `list_bugs`? | Notes |
| --- | --- | --- |
| title | yes | use `normalize_title` |
| `current_view` | yes (`current_views`) | screen the bug was reported from |
| tags | yes | already a set |
| categories | yes | already a set |
| app version | yes | |
| network log (failed requests) | **no** | requires `bug_details` per candidate |
| user steps | **no** | requires `bug_details` per candidate |
| user attributes | **no** (not exposed as a `list_bugs` filter today) | requires `bug_details`; if absent on a bug, it is skipped |

Only enrich (`bug_details`) when the chosen key recipe needs one of the **no** rows, and only for the candidates in scope.

## Missing fields → skipped, never catch-all

If a bug lacks a field the key requires (no network log, no such user attribute, empty user steps), it gets **no key**. It is reported on the plan's "skipped / not grouped" list with the reason (e.g. `skipped: no network log`). It is **never** placed in a default "everything else" group — a catch-all bucket would produce merges the customer never intended.

## Singletons

After keys are computed, any key held by only one bug is dropped. A group of one is not a duplicate. Only keys shared by ≥2 bugs become proposed merges.
