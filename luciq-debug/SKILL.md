---
name: luciq-debug
description: Investigate any Luciq production signal end-to-end (crash, hang, bug report, performance regression, App Store rating drop) and propose a fix. Pulls stack trace, repro steps, session profiler, report logs, session replay context, and device/version distribution via the Luciq MCP. Symbolicates obfuscated traces (delegating to luciq-symbolicate). Maps onto the local repo, forms an evidence-backed hypothesis, and proposes a code fix with an optional failing test. Use when the user mentions a crash ID, bug ID, hang, says "why is this crashing/slow/hanging", "investigate", "debug", "what broke since [version]", or asks why an App Store rating dropped.
---

<!--
Triggers (things the user might say):
- "why is this crashing / slow / hanging"
- "investigate [crash ID / bug ID / hang ID]"
- "debug this Luciq crash / bug / hang"
- "what broke since [version]" / "regression since [version]"
- "why did our App Store rating drop"
- pasting a stack trace or fingerprint and asking what's wrong
- "look into this production issue"
-->

# Luciq Production Debugging

Investigate a production issue end-to-end. **Default to evidence-based reasoning — never guess.** Cite the MCP tool result that supports each claim.

## Workflow checklist

Copy this and check off as you go:

```
Debug Progress:
- [ ] 1. Detect platform
- [ ] 2. Verify Luciq MCP connected
- [ ] 3. Identify entry point
- [ ] 4. Pull context via Luciq MCP
- [ ] 5. Symbolicate if obfuscated
- [ ] 6. Map top frame to local repo
- [ ] 7. Form hypothesis with cited evidence
- [ ] 8. Propose fix (diff)
- [ ] 9. Generate failing test (optional)
- [ ] 10. Apply on user confirmation
```

## 1. Detect platform

Single Glob: `{pubspec.yaml,package.json,*.xcodeproj,*.xcworkspace,build.gradle,build.gradle.kts,shared/build.gradle.kts}`. First match wins. Platform changes how stack traces map to source.

## 2. Verify Luciq MCP connected

If the Luciq MCP server isn't authenticated, STOP and direct the user to `luciq-setup`.

## 3. Identify entry point

Ask if not given:

| Entry point | Required input |
|---|---|
| Crash | Crash ID, fingerprint, or pasted stack trace |
| Bug report | Bug report ID |
| Hang | Hang ID, or "investigate recent UI hangs" |
| Regression | Two version numbers (current + baseline) |
| Rating drop | Date range + platform |
| In-code error | Open file + line number + error text |

## 4. Pull context via Luciq MCP

Use Luciq MCP tools (qualified as `luciq:<tool_name>`). Discover exact tool names via the MCP tool list at runtime if uncertain.

| Entry point | Capabilities to query |
|---|---|
| Crash | List crashes (filter by ID), get crash details + stack trace, list occurrences, deep-dive one occurrence's session |
| Bug report | Get bug report (logs, repro steps, device context) |
| Hang | List app hangs, get hang details |
| Regression | List crashes filtered by version range; compare distributions |
| Rating drop | Query App Store reviews for the date window; correlate against crashes/bug reports in the same window |

For every entry point, capture: top frame, device/OS distribution, version distribution, occurrence count, first/last seen, repro steps if present.

## 5. Symbolicate if obfuscated

If frames look like hex addresses, `<obfuscated>`, or compiler-mangled names, delegate to `luciq-symbolicate`. Re-fetch crash details after upload to confirm resolution.

## 6. Map top frame to local repo

For the top symbolicated frame:
- Use Grep to find the symbol (class + method) in the repo
- Use Read on the matched file: 10 lines above and below the crashing line
- Cross-reference with repro steps if present

If multiple matches: prefer the file in the platform-specific source set (e.g. `iosMain/`, `androidMain/` for KMP).

## 7. Form hypothesis

Combine evidence into a structured hypothesis. **Cite each piece of evidence to the MCP result that produced it.**

Template:

```
HYPOTHESIS: <one sentence>
CONFIDENCE: <low / medium / high>

EVIDENCE:
- Top frame: <file>:<line> — <symbol>  [from: luciq:get_crash_details]
- Device/OS pattern: <e.g. only iOS 18.0+>  [from: luciq:list_occurrences]
- Repro steps: <e.g. user tapped Checkout → backgrounded → resumed>  [from: luciq:get_bug_report]
- Network state: <e.g. failed POST /v1/checkout returned 500>  [from: bug report network logs]
- Session profiler: <e.g. memory pressure spike 30s before crash>  [from: occurrence session]

ROOT CAUSE: <the specific defect>
```

Concrete example:

```
HYPOTHESIS: Crash is a force-unwrap of `cart` in CheckoutVC.checkoutTapped() after the view restores from a backgrounded state where the view model was deallocated.
CONFIDENCE: high

EVIDENCE:
- Top frame: ios/Checkout/CheckoutVC.swift:142 — checkoutTapped()  [from: luciq:get_crash_details]
- Device/OS pattern: 94% iOS 18.0+, no iOS 17 occurrences  [from: luciq:list_occurrences]
- Repro steps: tapped Checkout → backgrounded ~5s → resumed → tapped Checkout again  [from: luciq:get_bug_report logs]
- Session profiler: memory pressure spike 12s before crash  [from: occurrence session]

ROOT CAUSE: `cart!` on line 142 is force-unwrapped without checking that the parent view model survived the background-restore lifecycle.
```

If evidence doesn't support a high-confidence hypothesis, say so. NEVER invent reasoning.

## 8. Propose fix

Show a diff. Explain how the fix addresses the root cause. Highlight any side effects.

## 9. Failing test (optional)

Generate a unit or UI test reproducing the bug. Run it: confirm it fails before the fix, passes after.

## 10. Apply

Only after user confirmation.

## Branches by signal type

Different signals weight different evidence:

| Signal | Weight order |
|---|---|
| Crashes | Stack trace > device/OS distribution > repro steps |
| App hangs | Main-thread sample > what user was doing > network conditions |
| OOM | Session profiler memory trace > backgrounded? > device RAM tier |
| Bug reports | User repro description > screenshots/logs > network logs |
| Perf regression | Compare span timings across versions > correlate with code changes |
| Rating drop | Review text themes > correlate with crash/bug spikes in same window |

## Style

- DO NOT fabricate stack traces, line numbers, or counts.
- DO NOT propose a fix without naming the root cause.
- DO NOT apply edits without showing a diff and getting confirmation.
- DO NOT skip symbolication and reason about hex addresses.
- If MCP returns nothing for a query, surface that fact — don't fill in plausible-looking data.
