---
name: luciq-release-check
description: Pre/post-release health gate. Compares a mobile release's production health (crashes, hangs, bug reports, App Store reviews) to the prior release using the Luciq MCP, computes deltas, and returns a clear ship/hold/rollback verdict with cited evidence. Use when the user asks "is [version] safe to roll out", "how is the latest release doing", "should I halt the rollout", or "compare [version] to [prior version]".
---

<!--
Triggers (things the user might say):
- "is [version] safe to roll out"
- "how is the latest release doing"
- "should I halt the rollout / continue the rollout"
- "compare [version] to [prior version]"
- "release health for [version]"
- "should we ship / hold / rollback [version]"
-->

# Luciq Release Health Check

Decide whether to ship, hold, or rollback a release based on Luciq production data.

## Workflow

1. Detect platform
2. Verify Luciq MCP connected (else direct to `luciq-setup`)
3. Identify current and baseline versions
4. Pull comparative data via Luciq MCP for both versions
5. Compute deltas
6. Form verdict
7. Output structured report

## 1. Detect platform

Single Glob. Mobile releases are typically per-platform — scope the check to one.

## 2. Identify versions

Read current version from project metadata:

| Platform | Source |
|---|---|
| iOS | `Info.plist` `CFBundleShortVersionString` (and build number) |
| Android | `app/build.gradle*` `versionName` |
| Flutter | `pubspec.yaml` `version:` |
| React Native | `package.json` `version` |

Ask the user for the **baseline** to compare against (default: previous patch or minor — whichever was last fully rolled out).

## 3. Pull data via Luciq MCP

For both current and baseline versions, use Luciq MCP tools (qualified `luciq:<tool_name>`):

| Signal | Capability |
|---|---|
| Crashes | List crashes filtered by version |
| Open bugs | List bug reports filtered by version |
| Hangs | List app hangs filtered by version |
| Reviews | List App Store reviews in the rollout date window |

Compute per-signal: count, top-5 by occurrence, deltas vs baseline.

## 4. Verdict thresholds

| Condition | Verdict |
|---|---|
| Crash-free session rate ↓ > 0.5% | hold |
| New top-5 crash with high occurrences inside 24h | rollback |
| Negative-review rate ≥ 2× baseline | hold |
| Major hang regression (P95 hang duration ↑ > 50%) | hold |
| All deltas neutral or positive | ship |

If conditions conflict, take the most cautious.

## 5. Output

ALWAYS use this format:

```
VERDICT: <ship / hold / rollback>
CONFIDENCE: <low / medium / high>

DELTAS (current vs baseline):
- Crashes: <count>, <delta>%, top new: <fingerprint>
- Hangs: <count>, <delta>%
- Bugs: <count>, <delta>%
- Reviews: avg <stars>, low-star rate <delta>%

EVIDENCE:
- <claim 1>  [from: luciq:list_crashes filter=version:<v>]
- <claim 2>  [from: luciq:list_reviews date=<window>]

CAVEATS:
- <e.g. APM span data not exposed via current MCP — perf regression check is partial>
```

Concrete example:

```
VERDICT: hold
CONFIDENCE: high

DELTAS (v4.3.0 vs v4.2.1):
- Crashes: 142, +37%, top new: ChooseAddressVC.swift:88 force-unwrap
- Hangs: 28, neutral
- Bugs: 19, +6%
- Reviews: avg 4.1 (down from 4.6), low-star rate 2.3× baseline

EVIDENCE:
- Crash count up 37% in 24h since v4.3.0 release  [from: luciq:list_crashes version=4.3.0]
- New top-3 crash in ChooseAddressVC absent from v4.2.1  [from: luciq:list_crashes diff]
- Low-star reviews mention "checkout broken"  [from: luciq:list_reviews window=last_24h]

CAVEATS:
- APM span data not exposed via current MCP — perf regression check is partial
```

## Style

- DO NOT soften a "hold" into "probably ship" because data is mixed.
- DO NOT claim a verdict without citing at least one piece of evidence.
- DO NOT reason about APM regressions if MCP doesn't surface them — say so.
- If user disagrees, ask what evidence would change their mind.
