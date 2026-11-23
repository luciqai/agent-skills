# Capture engine — how the seam-dump capture works, and its limits

## Why the seam (no proxy, no CA cert, no Frida, pinning-proof)

TLS gives exactly three ways to reach plaintext:

1. **Terminate at a proxy** (Charles/mitmproxy/Proxyman) — needs the app to trust
   your CA cert, and fails on certificate pinning.
2. **Read inside the process** — the bytes are already decrypted in the app's own
   memory. No cert, and pinning is irrelevant to *reading*.
3. **Export TLS session keys** (`SSLKEYLOGFILE`) — iOS `URLSession` and Android
   `OkHttp` don't honour it.

This skill uses **(2)**, but through an API the SDK already exposes — Luciq's
**obfuscation seam** — rather than an external instrumentation tool. So it needs no
CA install, isn't blocked by pinning, and isn't subject to host-OS injection limits.

> **Why not Frida?** Frida is also path (2), but it *injects* into the process from
> outside, which the host OS can block. On macOS 26 + SIP, Frida 17.x cannot inject
> into iOS **Simulator** apps at all (`unexpected early end-of-stream`, even under
> `sudo`) because simulator apps are host processes and injection is blocked at the
> host level — the guest iOS version is irrelevant. The seam doesn't inject, so none
> of that applies. Frida support was removed from this skill for that reason.

## The mechanism

The app already routes every request/response through Luciq's obfuscation handler
(that's where masking happens). The seam-dump temporarily installs a **pass-through**
handler at that exact point: it appends each log to a JSONL file and returns it
**unchanged**. It captures literally what Luciq logs — the highest-fidelity data
possible, and the exact surface your real `scrubPII` handler will mask.

Capture and production wire into the **same entry point**: capture reads + returns
unchanged; production reads + scrubs + returns. See `../assets/seam-dump/` for the
per-platform snippets (iOS `ios.swift`, Android `android.kt`).

## The one cost, and how it's contained

The seam **edits app code and rebuilds** — the trade for never touching Frida, a
proxy, or a cert. It's contained by construction:

- **Pass-through only** — the handler returns the data unchanged; traffic is never
  altered.
- **Flag-gated** — inert unless armed (`-seamDump` launch arg on iOS; `SEAM_DUMP`
  const + `BuildConfig.DEBUG` on Android).
- **Temporary** — deleted after the manifest is built (the workflow ends on it).

## ⚠ Validation-critical — confirm before trusting output

1. **Handler signatures per platform.** Only the iOS snippet is verified against the
   SDK headers. Android/Flutter/RN mirror the shipped handler templates — confirm
   the setter and `LuciqNetworkLog` field names against https://docs.luciq.ai on a
   real build before trusting the capture.
2. **The handler must actually fire.** If Luciq network logging is disabled, the app
   token is a placeholder/invalid, or the app's traffic doesn't flow through Luciq's
   interception, the file stays empty. Sanity-check that the endpoint/host count
   matches what you actually walked; a suspiciously low count means the handler isn't
   firing (or paths weren't walked) — fix that rather than shipping a thin manifest.

   > **Don't be fooled by `-999`.** With a real token the app's own URLSession tasks
   > still log `NSURLErrorCancelled (-999)` — that's *normal*: Luciq cancels the
   > original task and re-issues the request internally, then logs it (firing the
   > seam). `-999` + a populated capture = healthy. `-999` + an **empty** capture =
   > almost always an invalid/placeholder token: Luciq intercepts but never completes
   > the re-issue, so nothing is logged. Verified live on iOS (SDK 19.8.1): placeholder
   > token → 0 captures; valid token → full capture, same `-999` in the logs.

## Completeness is walk-bound

Capture only sees traffic the developer exercises. A path not walked is a field not
masked. The skill must end with a coverage summary ("captured N endpoints across M
hosts") so the developer can judge what wasn't hit. An optional future net is
cross-checking against a backend contract (OpenAPI/GraphQL) — out of scope for v1,
noted so the limitation is explicit.
