# Check Catalog

Every rule the audit can run, the channels each can pull evidence from, and the platform applicability matrix. Codes follow the customer-derived families: **E**nvironment, **C**apture, **S**ynthetic, **P**II, **A**ttributes, **T**racer (dashboard), **U**ser flow (dashboard).

## Table of contents

1. [Status taxonomy](#status-taxonomy)
2. [Environment (`E*`)](#environment-e)
3. [Occurrence identity (`C0*`)](#occurrence-identity-c0)
4. [Network capture (`C1`–`C7`)](#network-capture-c1c7)
5. [Feature flags / experiments (`C8*`)](#feature-flags--experiments-c8)
6. [SDK hygiene (`C9`)](#sdk-hygiene-c9)
7. [Synthetic markers (`S*`)](#synthetic-markers-s)
8. [PII (`P*`)](#pii-p)
9. [User attributes (`A*`)](#user-attributes-a)
10. [Manual dashboard checks (`T*`, `U*`)](#manual-dashboard-checks-t-u)
11. [Platform applicability matrix](#platform-applicability-matrix)
12. [Cross-occurrence sanity (optional)](#cross-occurrence-sanity-optional)

## Status taxonomy

Eight statuses; do not invent new ones. Match the rendered report exactly.

| Status | Meaning |
| --- | --- |
| `PASS` | Rule fired, evidence satisfies the assertion |
| `FAIL` | Rule fired, evidence violates the assertion — release-blocking |
| `WARN` | Rule fired, evidence is borderline — release with caveat |
| `INFO` | Informational signal, not an assertion |
| `SKIP` | Rule could not run — surfaces the reason (e.g. "evidence field missing", "apm tools unavailable") |
| `MANUAL` | Rule requires human dashboard verification — never auto-PASS |
| `DISABLED` | Rule is technically applicable but the feature it tests against is intentionally off. Two sources: (a) rule pack explicitly turns the rule off, or (b) the dashboard workspace has the feature toggled off (e.g. `user_steps` disabled at workspace level). The audit surfaces *why*. |
| `N/A` | Rule does not apply to this platform / SDK version |

A single `FAIL` blocks the release. `MANUAL` items do not block automatically but appear at the top of the report.

**Empty evidence is never PASS.** If the audit cannot find the field path it expects, the result is SKIP with reason "evidence field missing." Marking PASS-by-default would silently mask integration regressions.

**Distinguishing `DISABLED` from `FAIL`.** A feature toggled off at the workspace level is *intentional configuration*, not a regression. The audit reports `DISABLED` (with the source — "rule pack" or "workspace policy") and continues. If the audit instead emitted `FAIL`, every workspace that disabled `user_steps`, network logging, or any optional channel would produce a false-positive release block.

Detection heuristics:
- **Rule-pack source**: rule pack has `disabled: true` on the rule, or omits a required capability declaration.
- **Workspace source**: the SDK feature's evidence field is structurally present in the payload's schema but the captured data is empty *because the dashboard says it should be* — e.g. payload contains no `user_steps` key at all (vs. an empty array). When detected, mark `DISABLED` with reason `"workspace policy: <feature> disabled"` rather than SKIP-empty-evidence.

## Environment (`E*`)

| Code | Check | Evidence source |
| --- | --- | --- |
| `E1` | Test environment (backend host) identified | Static analysis of build config; cross-check `state.fields.bundle_id` matches `integration.bundle_ids.debug` from the rule pack |
| `E2` | App version identified, matches the version under test | `state.fields.app_version` |
| `E3` | Build variant is debug | Static analysis + `state.fields.bundle_id` ends with `.debug` (or matches rule-pack debug bundle ID) |
| `E4` | OS / device captured | `state.fields.os` (combined string like `"iOS 26.1"`) + `state.fields.device` |

## Occurrence identity (`C0*`)

| Code | Check | Evidence source |
| --- | --- | --- |
| `C0`  | Latest occurrence selected for audit | `list_occurrences_tokens.states_tokens[0]` (newest first). Response also includes `total_occurrences`. |
| `C0b` | Selected occurrence is recent. Source: parsed ULID timestamp (first 10 base32 chars of the token, Crockford's alphabet — see `payload-schemas.md` for the recipe). Thresholds are mode-dependent and rule-pack-overridable via `recency_thresholds: { warn_minutes, fail_minutes }`. | Parsed ULID timestamp |
| `C0c` | SDK version recorded matches the version under test | `state.fields.sdk_version` (e.g. `"19.6.1"`) |
| `C0d` | State token returned matches the ULID queried | `state.fields.state_token == <ulid>` — cross-app / cross-mode sanity check |

### `C0b` recency thresholds (defaults)

| Mode | WARN if older than | FAIL if older than | Rationale |
| --- | --- | --- | --- |
| `synthetic` | 5 min | 30 min | Smoke just ran; freshest occurrence should be brand new. |
| `prod-canary` | 12h | 24h | Audits real-user telemetry; lenient by design. |

Customers can override per environment via the rule pack:

```yaml
recency_thresholds:
  warn_minutes: 120        # e.g. 2h — reuse-mode workflows where engineers
  fail_minutes: 1440       #         smoke ahead of running the audit
```

Useful for reuse-mode setups that drive an existing in-house dev-tools surface — engineers often run the trigger sequence minutes-to-hours before invoking the audit, so the synthetic-mode defaults are too tight.

## Network capture (`C1`–`C7`)

Channel preference: **APM > Bug > Crash**. The skill picks the first channel that returned data.

| Code | Check | APM (primary) | Bug (dedicated `network_log` archive) | Crash (bundled `compressed_logs` archive) |
| --- | --- | --- | --- | --- |
| `C1`  | URL normalization: every captured URL matches the customer's allow-list / normalization pattern | `apm_group_view` group URL / pattern; `apm_occurrence.url` per row | URL entries in parsed `network_log` | URL entries in parsed `compressed_logs` |
| `C2`  | Required custom headers present on every request | `apm_occurrence` request headers | header entries in parsed `network_log` | header entries in parsed `compressed_logs` |
| `C3a` | Request body redacted (token from rule pack) on all entries | `apm_occurrence` request body | `network_log[*].request` (field name is `request`, not `request_body`) | same field inside decoded `compressed_logs.network_log[*].request` |
| `C3b` | Response body redacted on **successful** entries only; failures exempt | `apm_occurrence` response body, filtered via `failure_type` / `failure_name` | `network_log[*].response` + `status` | same fields inside decoded `compressed_logs.network_log[*]` |
| `C4`  | Sensitive headers (`Authorization`, `Cookie`, `Set-Cookie`, etc.) absent or redacted | `apm_occurrence` request + response headers | `network_log[*].headers` and `.response_headers` | same fields inside decoded `compressed_logs.network_log[*]` |
| `C5`  | Attachment URL paths redacted (no opaque IDs in path segments) | `apm_group_view` group URL pattern; `apm_occurrence.url` per row | `network_log[*].url` | same field inside decoded `compressed_logs.network_log[*]` |
| `C6`  | Task / trace correlation IDs captured (presence on every request) | `apm_occurrence` request headers (or `custom_attributes` if customer routes the trace ID there) | `network_log[*].headers` | same field inside decoded `compressed_logs.network_log[*]` |
| `C7`  | No Luciq self-traffic captured (SDK must not surveil itself) | `apm_list_groups` — no group should have a Luciq host pattern | `network_log[*].url` filtered against an exclude list | same field inside decoded `compressed_logs.network_log[*]` |

### Critical semantics observed live

`C3b` excludes failed responses by design — error bodies are intentionally captured for diagnostics. On APM, filter via `failure_type` / `failure_name`. On crash / bug, filter by HTTP `status >= 400` (or `status == 0` for network errors). The report footer states the exclusion count explicitly (e.g. "16 non-2xx / failed rows excluded from response-body redaction check").

**Three special string values** the SDK puts into the network log that the audit must recognize separately:

| Value | Where | Meaning | How `C3a` / `C4` should react |
| --- | --- | --- | --- |
| `"*****"` | `headers.<sensitive-header>` | SDK auto-redacted a sensitive header value | C4 PASS — the SDK did the right thing |
| `"Request body has not been logged because it exceeds the maximum size of 10240 bytes"` | `request` field | SDK truncated the body before the customer's redaction callback ran | C3a INFO (not PASS) — body bypassed customer redaction; raise visibility but don't FAIL |
| `<the customer's redaction token>` (e.g. `"WD-REDACTED"`) | `request` / `response` field | Customer's redaction callback ran and replaced the body | C3a / C3b PASS |

**`C7` (no SDK self-traffic) needs an exclude list**: outbound Luciq SDK requests to `api.instabug.com/api/sdk/v3/*` DO appear in the captured network log on this branch — the SDK does not self-filter. The customer's rule pack should specify `network.url_exclude_hosts` (e.g. `["api.instabug.com", "*.luciq.com"]`) for C7 to evaluate cleanly. Without an exclude list, C7 effectively can't PASS on a build that emits any SDK telemetry.

**`IBG-*` headers carry the app token plaintext**: outbound SDK requests carry `IBG-APP-TOKEN` (the dashboard credential), `IBG-CUUID`, `IBG-OS-VERSION`, etc., as plaintext headers. These are NOT auto-redacted to `*****`. If the customer wants the app token masked in the captured log, they add `IBG-APP-TOKEN` to `redaction.sensitive_headers` in the rule pack.

## Feature flags / experiments (`C8*`)

| Code | Check | Evidence source |
| --- | --- | --- |
| `C8`  | Feature flags / experiments logged (count > 0) | Bug path: root `experiments` value (object or `null`). Crash path: `state.logs.experiments` — if `is_empty_array: false`, fetch + parse the presigned `url`. APM path: `apm_group_view.views[].pattern_key: experiment` (dimensions view). |
| `C8b` | Flag / experiment key length within SDK truncation limit | Per-flag key length from whichever response carries it |

## SDK hygiene (`C9`)

| Code | Check | Evidence source |
| --- | --- | --- |
| `C9` | No Luciq SDK `warn` or `error` lines in the app log over the smoke window | Bug path: `state.logs.console_log.url` (device console log captured by the SDK, when configured) — grep for lines tagged with the Luciq logger prefix at level `w` or `e`. Crash path: scan inside decoded `compressed_logs` for SDK-tagged lines. **Do NOT use `instabug_log` for this** — that archive carries the customer's own `Luciq.log.X()` calls, not SDK-internal messages. |

## Synthetic markers (`S*`)

These confirm the smoke actually ran. They SKIP in tier T1 (telemetry-only mode).

| Code | Check | Evidence source |
| --- | --- | --- |
| `S1` | Harness marker present (`current_view == "LuciqVerifyHarness"`) | `state.fields.current_view` |
| `S2` | User steps / breadcrumbs captured at expected threshold | Bug path: `state.logs.user_events.url` — dedicated breadcrumbs archive. Crash path: inside `state.logs.compressed_logs` archive (fetch + parse). SKIP if archive `is_empty_array: true` |

## PII (`P*`)

PII regexes come from the rule pack. The skill must not invent them — false positives ("`name` is PII") are worse than the missing rule.

| Code | Check | Evidence source |
| --- | --- | --- |
| `P1` | PII regex scan over user steps clean | Bug path: `state.logs.user_events.url` (cleanest — dedicated archive). Crash path: text content of `state.logs.compressed_logs` archive; SKIP if `is_empty_array: true` |
| `P2` | PII regex scan over attribute values clean | `state.fields.user_attributes` (crash + bug) + bug path's `state.logs.user_data.url` + APM `user_attributes` / `custom_attributes` blocks |
| `P3` | PII regex scan over URL query strings clean | APM (primary); bug path's `network_log.url` (mid); crash path's `compressed_logs` (fallback) |
| `P4` | PII regex scan over identity fields | `state.user.email`, `state.user.name`, `state.fields.email`, `state.fields.user_name`. On bug payload, top-level `email` field also exists — scan that too. Empty values pass trivially; non-empty must not match regex |

## User attributes (`A*`)

APM splits attributes into two buckets with different shapes — the rule pack and the audit must respect this:

- **`user_attributes`**: identity-tier, **named** key/value pairs (tenant, locale, install source, persona). On APM's filter surface, `user_attributes` is an object keyed by attribute name. The rule pack enumerates required *names*.
- **`custom_attributes`**: feature-tier, attached to specific operations. On APM, custom attributes are addressed by **numbered slot 1–20** (`custom_attribute_1` ... `custom_attribute_20` per `apm_group_view.views[].pattern_key`). The dashboard maps each slot to a logical name; the customer's rule pack supplies that mapping so the audit can reference attributes by name.

Codes are templated per customer; the rule pack lists required keys / slots.

| Code | Check | Evidence source |
| --- | --- | --- |
| `A1`–`An` (user) | Required `user_attributes[<name>]` present per `attributes.user.required` | `state.fields.user_attributes` (object keyed by name; `{}` when none set) — crash path. APM path: `apm_occurrence` user_attributes block. |
| `Ax1`–`Axn` (custom) | Required `custom_attribute_<slot>` populated per `attributes.custom.required_slots` (with the slot→name mapping from the rule pack used for human-readable reporting) | APM only — `apm_occurrence` custom_attributes block. Crash payload does NOT carry custom_attributes inline; if APM is N/A or unavailable on the account, all `Ax*` rules SKIP with reason "custom attributes only visible via APM channel." |
| `Ay`  | All attributes (both buckets) scanned for PII | Both blocks against `pii.regex` |

### Custom-attribute slot mapping discipline

The slot→name mapping is **organization-wide dashboard configuration**, not per-build. The skill cannot infer it from telemetry alone. On first run, prompt the user to populate `attributes.custom.slot_map` in the rule pack; absent that, the audit emits SKIP with reason "custom-attribute slot mapping not configured" for every `Ax*` rule. Never guess a mapping — a wrong mapping creates permanent silent false positives.

## Manual dashboard checks (`T*`, `U*`)

These never auto-PASS. The report links them out to dashboard URLs and waits for human verification.

| Code | Check | What the user does |
| --- | --- | --- |
| `T1` | Task-ID / hostname tracer reaches dashboard | Open the network dashboard for the test app, confirm trace correlated |
| `U1` | User flow / flow attribute renders in APM Flows | Open the APM Flows view, confirm flow tagged correctly (note: APM `metric: flows` may not be GA yet — this is a placeholder for the upcoming metric) |

## Platform applicability matrix

Some rules do not apply on every platform. The audit emits `N/A` (not SKIP, not PASS) for rules that don't apply.

| Platform | `ANR` rules | `OOM` rules | APM channel | `current_view` semantics |
| --- | --- | --- | --- | --- |
| iOS (`IOS`) | N/A (no `ANR` type; iOS UI hangs via `list_app_hangs`) | Applicable | Eligible — probe to confirm | Top-most `UIViewController` class name |
| Android (`ANDROID`) | Applicable | Applicable (treated as `CRASH` until exposed otherwise) | Eligible — probe to confirm | Top-most `Activity` / `Fragment` |
| Flutter (`DART`) | Applicable | Applicable | **N/A permanently on this branch** — do not probe | Route name or widget |
| React Native (`JAVASCRIPT`) | Applicable | Applicable | **N/A permanently on this branch** — do not probe | Screen name or navigator route |

## Cross-occurrence sanity (optional)

If `list_occurrences_tokens` returns multiple recent occurrences from the smoke, the audit may also assert consistency: the customer's persona attribute should appear with the **same value** across all of them. Drift across the smoke session is itself a finding — surface as WARN or INFO depending on severity.
