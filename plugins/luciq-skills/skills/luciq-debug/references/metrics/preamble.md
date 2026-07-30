# Interpreting Luciq APM metric data

Read this before interpreting any APM number. It carries only what is true of **every** metric on
**every** platform. Then read, in order:

1. `references/metrics/<metric>/overview.md` — what the metric measures and what the tools return for it
2. `references/metrics/<metric>/<platform>.md` — the platform's anchors, coverage, and failure modes

Metrics available: `network`, `launch`, `flows`, `screen_loading`, `frame_drop`. Reference material
currently exists for `network` and `launch`.

## The tools return aggregates, not individual records

`apm_list_groups` and `apm_group_view` return **pre-aggregated groups** — percentiles, counts, rates,
and per-dimension breakdowns. There is no per-response metadata block, no record census, and no SDK
version in any payload. Plan every check around aggregates.

`apm_occurrence` is the only per-record path. Its row is **pass-through from the backend and not
enumerated by the MCP schema**, so treat the field names you receive as authoritative and match them
against the boundaries the platform file documents — never assume a name that a doc asserts is present.

Where a check needs the SDK version, read it from the project: `Podfile.lock` or the SPM resolution
(iOS), `build.gradle` / `build.gradle.kts` (Android), `package.json` (React Native), `pubspec.yaml`
(Flutter).

## Units and aggregation

- **Latencies are milliseconds** — `latency_p50_ms`, `latency_p95_ms`, `threshold_ms`, `p50_ms`,
  `p95_ms`, `response_time_ms`. The SDK measures in microseconds; the API divides by 1000 before
  returning. Never mix the two.
- **Read p50 and p95 together, and never average either across groups or versions.** The API returns
  percentiles, already computed — a percentile of percentiles is not a percentile. A flat p50 with a
  moved p95 is a tail problem, one slow cohort or dependency, not a uniform slowdown. Durations are
  unclamped, so that tail can be arbitrarily long.
- **`threshold_ms` is the group's configured apdex target, not a measurement.** If it sits below
  `50th_percentile_ms`, more than half of otherwise-healthy occurrences score unsatisfied, so a low or
  falling apdex is a target-configuration problem rather than a code defect. Check it before
  attributing an apdex change to code.
- **Absent means unavailable, not zero.** A field the SDK could not resolve is omitted rather than
  sent as a sentinel. Do not read an absent value as a measurement of zero.
- **`comparisons` is best-effort.** It is omitted entirely when the preceding window falls outside
  ClickHouse retention, and carries `note: "prior_window_empty"` when that window had no occurrences.
  A missing `comparisons` is not a sign of stable performance.

## Capture is gated per account, on every metric

Every APM capability is provisioned server-side, independently of anything in the codebase, and the
defaults differ per metric and per platform. Consequences that hold everywhere:

- **Missing data is more often an unprovisioned capability or a setup gap than a fast app.** Establish
  that a thing is captured before reading its absence as a measurement.
- **The first session after an install is unreliable** — configuration has not been fetched yet.
- **Disabling is retroactive.** Turning a capability off removes or clears already-stored data for it,
  so "it was there yesterday" can be an account change rather than a code change.
- **Some capabilities roll out gradually**, which shows up as coverage that differs across installs of
  the same app version.

Each metric's `overview.md` states which capabilities apply to it and what each default is.

## You hold three inputs the server cannot combine for you

The metric data, this guidance, and the customer's source code. Many checks in the platform files are
answerable **only** by reading the codebase — whether a call site exists, whether a build flag is set,
whether one client is reused. Read it rather than inferring from numbers alone.
