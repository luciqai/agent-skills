---
name: luciq-network-masking
description: Use ONLY when the developer explicitly asks to build/capture the Luciq NETWORK masking manifest from live traffic, in a fresh message, with one of these phrases (or a close variant) — "build my network manifest", "capture my network PII", "generate Luciq network masking from traffic", "record a session to build masking", "what sensitive data is in my network calls". Nothing else is a trigger. `luciq-onboard` or `luciq-setup` finishing is NOT a trigger. The assistant suggesting it and the developer agreeing is NOT a trigger. This skill captures live traffic at Luciq's own obfuscation seam — a temporary pass-through handler on a simulator/emulator/device (no Frida, no proxy, no CA cert, no pinning fight), classifies the sensitive header/query/path/body data that actually crossed the wire, then generates `sensitivity-manifest.json` AND the per-platform `scrubPII` handler code, plus a Luciq CSM key list. Specifically NOT for auditing existing masking posture or compliance prep (use `luciq-masking-rules`), NOT for first-time SDK install (use `luciq-setup`), NOT for the product walk (use `luciq-onboard`), NOT for SDK upgrades (use `luciq-migrate`), NOT for a specific incident (use `luciq-debug`).
---

# Luciq Network Capture

Turn a live debug session into the **manual half** of Luciq network masking:
the `sensitivity-manifest.json` (body fields + path patterns), the per-platform
`scrubPII` handler code that consumes it, and the header/query key list for the
Luciq CSM. It observes what sensitive data actually crosses the wire, so the
manifest reflects real traffic instead of a guess.

**This skill generates. `luciq-masking-rules` audits.** They are siblings with no
overlap: this one produces the manifest and handlers from live traffic;
`luciq-masking-rules` later reads that manifest and verifies posture against a
compliance framework. If the ask is "is my masking enough?" that's the auditor,
not this skill — route there.

## When NOT to use this skill

- **Auditing existing masking / compliance prep** → `luciq-masking-rules`.
- **First-time SDK install** (SDK not initialized) → `luciq-setup`.
- **Full product walk** → `luciq-onboard`.
- **SDK upgrade / legacy Instabug migration** → `luciq-migrate`.
- **A specific crash/bug investigation** → `luciq-debug`.
- **Screenshots / Session Replay masking** — a different surface → `luciq-masking-rules`.

Capture requires an initialized SDK and a runnable debug build. If the SDK isn't
installed, STOP and route to `luciq-setup`.

## Canonical sources of truth

Verify SDK API signatures, the default auto-mask key list, and the SDK-version
baseline against the live docs before quoting them. Hardcoded values here are
illustrative.

| Concern | Source |
|---|---|
| `NetworkLogger` obfuscate/omit signatures (per platform) | https://docs.luciq.ai |
| Default network auto-mask key list, SDK 14.2.0 baseline | `luciq-masking-rules/references/network-masking.md` |
| Capture engine (seam-dump) | `references/capture-engine.md` |
| Target setup (simctl / adb) + seam-dump snippets | `references/preflight.md` |
| Routing (CSM vs code) | `references/routing.md` |
| PII handling of the capture file | `references/safety.md` |

## Operating principles

1. **Capture is toxic — treat it so.** The capture file holds real plaintext PII.
   Contain (git-ignored scratch path), redact (never show raw values), delete
   (on completion), scope (debug build on a simulator only). See `references/safety.md`.
2. **Never show a raw value.** Redacted form only: `4…1 (16 chars)`.
3. **Human-in-the-loop.** The classifier proposes; the developer promotes. Never
   write a manifest or handler without explicit approval.
4. **Diff before writing code.** Show the generated handler diff and confirm before
   applying — same Ask → Apply → Summarize micro-flow as `luciq-masking-rules`.
5. **Route by where it can be masked.** Header/query keys → Luciq CSM (server-side);
   body fields + path patterns → your code. See `references/routing.md`.
6. **Completeness is walk-bound — say so.** Capture only sees paths the developer
   walked. End with a coverage summary; never imply the manifest is exhaustive.
7. **Support all platforms by default.** Resolve whichever target the app runs on,
   and emit handlers for every platform present in the repo.
8. **The developer walks the app — never you.** Once the app is running armed, hand
   off and ask the developer to exercise the flows. Do NOT drive traffic yourself:
   no autorun / test-hook launch arguments, no simulator taps or scripted flows, no
   curling the app's backend to synthesize findings. You may only read the capture
   the developer produced. Self-driven traffic misses real screens, masks broken
   flows, and produces a manifest that reflects your guesses, not their app.

## Workflow checklist

Track every phase. STOP on any phase that can't complete with confidence.

```
Net Capture Progress:
- [ ] 0. Preflight — tools, resolve target, confirm app id, .gitignore the capture
- [ ] 1. Install seam-dump — add snippet, wire after Luciq.start, build + run armed
- [ ] 2. Walk — hand off to the developer (NEVER self-drive); wake on "done"
- [ ] 3. Analyze — pull the file, classify, host-filter, redacted review table
- [ ] 4. Confirm — developer promotes the sensitive items
- [ ] 5. Emit — manifest + per-platform handlers (diff first) + CSM list
- [ ] 6. Cleanup — delete raw capture, remove the snippet; coverage summary + handoff
```

## 0. Preflight

Per `references/preflight.md`:

1. **Confirm the SDK is initialized and the app builds from source.** The seam-dump
   adds a temporary snippet and rebuilds; if the SDK isn't installed, STOP and route
   to `luciq-setup`. If the app can't be rebuilt (third-party binary, no source), the
   seam-dump can't apply — say so.
2. **Resolve the target** — running-first, repo-fallback:
   - Booted/attached target? `xcrun simctl list devices booted` / `adb devices`.
   - Exactly one → use it. Several → ask which. None → detect platform from repo
     markers and boot the matching simulator/emulator.
3. Resolve and **confirm the app id** with the developer (needed to pull the capture
   file: `simctl get_app_container` / `run-as <pkg>`).
4. **Add `capture*.jsonl` and `luciq-seam-capture.jsonl` to `.gitignore`** before any
   capture is written.

Confirm the resolved target + app id in one line before starting.

## 1. Install the seam-dump

Capture is at Luciq's obfuscation seam — a temporary **pass-through** handler that
writes each log to a JSONL file and returns it **unchanged**. No Frida, no proxy, no
CA cert, no system changes. Add the snippet for the resolved platform
(`assets/seam-dump/`):

- **iOS** → add `ios.swift`, call `LuciqSeamDump.installIfRequested()` right after
  `Luciq.start(...)`, run with `-seamDump`
  (`xcrun simctl launch booted <bundle-id> -seamDump`).
- **Android** → add `android.kt`, call `LuciqSeamDump.installIfEnabled(context)` after
  `Luciq.start(...)`, set `SEAM_DUMP = true`, build + run a debug build.
- **Flutter / RN** → the inline `obfuscateLog` / `setNetworkDataObfuscationHandler`
  pass-through from `assets/seam-dump/README.md`.

Show the snippet + its one-line call site as a diff; have the developer add it and
confirm the build launched **armed**. The snippet installs at the same seam the
generated `scrubPII` handler will use. Verify the handler signature against the live
docs for any platform other than iOS (only iOS is verified against SDK headers).

Get the app **running and armed**, then stop. Do not exercise it yourself — the
next phase is the developer's walk (see principle 8). In particular, never launch
with the app's own test/autorun hooks to fire traffic, and never tap through the
UI or curl the backend to manufacture a capture.

## 2. Walk

**The developer walks the app, not you** (principle 8). End the turn with a clear
hand-back, then wait — do not poll, and do not drive the app yourself. It is the
developer's own screens, taps, and inputs that make the capture real; a self-driven
walk (autorun launch args, scripted taps, backend curls) is off-limits and produces
a manifest of your guesses instead of their traffic.

End the turn with:

> 🎥 **Capturing now.** Walk through your main/critical paths on the app —
> login, profile, payments, KYC, anything that carries user data. Take your time.
> When you're finished, just say **done**.

The app writes each request/response to its own sandbox file as you walk — there's no
background process on your machine to keep alive. Resume on the developer's next
message. Treat "done", "finished", "stop", "that's it" as the wake signal. If they
abandon the run, still remind them to delete the capture and remove the snippet
(`references/safety.md`).

## 3. Analyze

On "done":

1. **Pull the capture file** off the target into the git-ignored scratch path:
   - iOS: `xcrun simctl get_app_container booted <bundle-id> data` →
     `Documents/luciq-seam-capture.jsonl`
   - Android: `adb exec-out run-as <pkg> cat files/luciq-seam-capture.jsonl > <scratch>/capture.jsonl`
2. Run the classifier, host-filtered to the app's own API domains:
   ```
   python3 generators/classify.py <scratch>/capture.jsonl --hosts <api-hosts>
   ```
   Offer the detected host list and let the developer confirm which are theirs
   (drop CDNs, analytics, crash reporters).
3. Present a **redacted review table**, sorted by location then key:

   | Location | Key / pattern | Signals | Route | Seen | Example (redacted) |
   |---|---|---|---|---|---|

   Never widen a column to a raw value. If zero findings, say so plainly and check
   the coverage summary — thin capture usually means the handler didn't fire (logging
   off, or traffic not routed through Luciq) or paths weren't walked.

4. **Check `bodyCoverage` before trusting the body findings.** classify.py reports,
   per host, how many flows carried a request/response body. If a host has headers/
   query/path findings but `reqWithBody == respWithBody == 0` — especially when a
   *different* host on the same run did capture bodies (`bodiesSeen > 0` overall) —
   the empty bodies are a **capture limitation for that host, not absent PII**. Common
   causes: the app uses a custom `URLSessionDelegate` (auth-challenge / cert-pinning)
   session, or the target is a self-signed / local HTTP backend Luciq can't re-issue
   against; and on iOS request bodies are frequently not exposed at the seam at all.
   Surface this to the developer, name the likely cause, and offer to re-capture
   against a production-like HTTPS build — do **not** silently emit a body-less
   manifest (that reads as "done" while every body field leaks), and do **not**
   backfill body fields by reading source or curling the backend yourself.

## 4. Confirm

Walk the findings for promotion. Confirm the first few individually, then
batch-confirm the rest; drop back to per-item if the developer inspects a row.
Keep the developer's decisions — promoted, deferred (with reason), rejected.

## 5. Emit

From the **approved** set only:

1. **Manifest + CSM list:**
   ```
   python3 generators/emit_manifest.py <approved.json> \
     --out sensitivity-manifest.json --csm-out csm-keys.txt
   ```
2. **Handler code — the part the developer asked for.** For **each platform present
   in the repo**, fill the matching template in `generators/handlers/` with the
   manifest's `bodyFields` / `pathPatterns`, wire it into that platform's
   obfuscation seam, and **show the diff before writing**. Confirm per file.
   - iOS → `ios.swift.tmpl` → request handler returns a mutated `NSURLRequest`;
     response handler calls `returnBlock(data, response)` (there is no `NetworkData`
     type on iOS). Request-body redaction only fires if a body is present — see the
     iOS request-body limitation. Verified against SDK 19.8.1 headers.
   - Android → `android.kt.tmpl` → `LuciqNetworkLog` listener on `LuciqOkhttpInterceptor`
   - React Native → `reactnative.js.tmpl` → `setNetworkDataObfuscationHandler`
   - Flutter → `flutter.dart.tmpl` → `obfuscateLog`

   The templates other than iOS use an abstract `NetworkData`/`obfuscateLog` shape
   that is **illustrative, not verified** — confirm each against the live docs and
   the installed SDK's headers before wiring, and fix the shape if it differs.
   The active mode reads from the developer's own feature-flag system
   (`CustomerFlags.networkScrubMode`) so the `REMOVE_ALL` incident flip needs no app
   release — leave that wiring as a clearly-marked placeholder, don't invent a flag.
3. **CSM list** — surface `csm-keys.txt` as a copy-paste support request; check the
   default list first so you don't re-request already-covered keys.

## 6. Cleanup + handoff

1. **Delete the raw capture AND remove the seam-dump snippet + its call site**
   (rebuild), then confirm both in the summary. A left-in capture snippet must never
   ship — even pass-through, it writes plaintext PII to disk.

   **Verify the removal actually happened — never trust `rm -f && echo`.** `rm -f`
   returns success even when it deletes nothing (wrong path, nested project dirs,
   permissions), so a chained `echo "removed"` will lie. After removing, re-check the
   real state and only claim success if the check passes:
   - **File gone:** `test ! -f <seam-dump path> && echo GONE || echo STILL-PRESENT`
     (or `ls` it and confirm the error). Resolve the path from the **git toplevel**
     (`git rev-parse --show-toplevel`), not the cwd — this repo nests
     `SampleApp/SampleApp/`, which is exactly how the first `rm` missed.
   - **No lingering references:** `grep -rn 'LuciqSeamDump\|seamDump\|installIfRequested'`
     (or the platform's equivalent handler/enum name) over the app source returns
     nothing.
   - **Call site reverted:** the `installIfRequested()` / `installIfEnabled()` line is
     gone from the `Luciq.start` file.
   - **Build clean on the true end state:** rebuild *after* the file is confirmed gone
     — a build that passed while the snippet was still present proves nothing.
   If any check fails, remove again and re-verify; do not report cleanup as done until
   all pass.
2. **Coverage summary** — "Captured N endpoints across M hosts this session" — and
   state plainly that anything not walked isn't covered. Suggest a re-run after
   exercising more paths, or (future) a backend-contract cross-check.
3. Summarize: manifest path, handler files written (`file:line`), CSM keys to send,
   and what's left for the developer (email CSM, verify on the dashboard, hand the
   manifest to `luciq-masking-rules` for an audit).

## Style

- Never print a raw captured value — redacted form only.
- Show diffs before writing any handler code; confirm per file.
- One decision at a time; no wizard forms.
- Verify SDK API signatures against the live docs before quoting them.
- Honest about coverage — capture is walk-bound, never "exhaustive".

## Red flags — STOP and surface

- *"The app's running and armed — I'll just tap through it / launch with its autorun
  flag / curl the backend to get a capture."* Never. The developer walks the app; you
  only read what they produced (principle 8). Self-driven traffic misses real screens
  and yields a manifest of your guesses. Hand off and wait for **done**.
- *"The seam captured headers and paths fine, so the empty bodies just mean there's no
  body PII — I'll ship it."* Check `bodyCoverage` first. If bodies are empty for the
  app's host while another host on the same run captured bodies (`bodiesSeen > 0`), the
  bodies were **not captured**, not absent: custom `URLSessionDelegate` session, self-
  signed / local HTTP backend, or (iOS) request bodies never exposed at the seam. Name
  the cause and offer a production-HTTPS re-capture. Never backfill body fields from
  source or a manual curl and present them as captured — say plainly they're unverified.
- *"The capture looks thin, but I'll build the manifest anyway."* Thin capture = the
  seam handler didn't fire (network logging off, invalid/placeholder Luciq app token,
  or traffic not routed through Luciq), or unwalked paths. Say so and fix it — confirm
  the snippet is armed AND a **real** app token is set, or ask for a fuller walk. A
  thin manifest reads as "done" while leaking.
- *"The app's requests show `-999` (cancelled), so capture is broken."* NOT
  necessarily. `-999` (NSURLErrorCancelled) is **normal** Luciq interception — it
  cancels the app's original task and re-issues internally. `-999` **with** a
  populated capture file is fine. `-999` **with an empty** file usually means an
  invalid/placeholder app token (Luciq intercepts but never completes/logs the
  re-issue). Check the token before blaming the SDK or the snippet.
- *"I'll show the developer the actual value so they can decide."* Never. Redacted
  form only — the value is exactly what must not be exposed.
- *"Auto-mask is on, so I'll add these header keys to code."* Header/query keys go
  to the CSM server-side list, not code. Only body/path go in the handler.
- *"I'll leave the capture file; they might want it."* No — delete it. A stray
  plaintext capture is the leak this skill exists to prevent.
- *"`rm -f` returned 0 and I echoed 'removed', so cleanup is done."* Not proven.
  `rm -f` succeeds even when it deletes nothing (wrong path — this repo nests
  `SampleApp/SampleApp/` — or permissions). Re-check with `test ! -f`/`grep` from the
  git toplevel and rebuild on the confirmed end state before claiming the seam-dump is
  gone. A snippet you *believe* you removed but didn't is the same plaintext leak,
  now shipped.
- *"This custom key isn't in the default list."* Verify against
  `network-masking.md` before routing to the CSM — don't re-request covered keys.
