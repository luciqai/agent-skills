# Seam-dump — how this skill captures traffic

This is **the** capture method. It reads traffic at Luciq's own **obfuscation
seam** — the exact `NetworkData` / `LuciqNetworkLog` your real `scrubPII` handler
will later mask. A temporary **pass-through** handler writes each log to a JSONL
file and returns it unchanged.

## Why the seam (and not a proxy or Frida)

To read HTTPS you must get past TLS, and there are only three ways: terminate at a
proxy (needs a CA cert), read inside the process, or export TLS keys (iOS/Android
don't). The seam is the **read-inside-the-process** path via an API the SDK already
gives you — so it:

- needs **no Frida, no proxy, no CA cert, no pinning bypass, no system changes**,
- is **not** subject to host-OS injection limits (e.g. Frida can't inject into iOS
  Simulator apps on macOS 26 — the seam doesn't care),
- captures the **highest-fidelity** data possible (literally what Luciq logs),
- works on device or simulator/emulator, any OS version, iOS and Android alike.

The one cost: it **temporarily edits app code and rebuilds**. Every handler is
**pass-through** — it reads and returns the data unchanged. Add → walk → pull →
**delete the edit**.

## Flow

1. Add the platform snippet to the app and call it right after Luciq starts.
2. Build + run a debug build with the capture flag on (`-seamDump` on iOS; flip
   `SEAM_DUMP` on Android).
3. Walk every critical path.
4. Pull the JSONL file off the device/simulator.
5. Feed it to `../../generators/classify.py` (same as any capture).
6. **Delete the snippet + its call site**, rebuild.

## Output format

Each network log is written in the flow shape `classify.py` consumes. iOS writes
request and response as **separate JSON lines** (`method/url/host/reqHeaders/reqBody`
for requests, `url/host/respHeaders/respBody` for responses); Android writes one
**combined** line per log. `classify.py` scans each line independently and dedupes
findings, so both are fine — verified to produce an identical manifest.

## Per-platform

| Platform | Pass-through handler to install (write the log to a file, return it unchanged) | Pull the file |
|---|---|---|
| **iOS** (verified) | `NetworkLogger.setRequestObfuscationHandler` + `setResponseObfuscationHandler` — see `ios.swift` | `xcrun simctl get_app_container booted <bundle-id> data` → `Documents/luciq-seam-capture.jsonl` |
| **Android** | `LuciqNetworkLog` listener on `LuciqOkhttpInterceptor` — see `android.kt` | `adb exec-out run-as <pkg> cat files/luciq-seam-capture.jsonl > capture.jsonl` |
| **Flutter** | `NetworkLogger.obfuscateLog((d) { append(d); return d; })` | from the app's documents dir |
| **React Native** | `NetworkLogger.setNetworkDataObfuscationHandler(async d => { append(d); return d; })` | from the app's documents dir |

The snippet installs at the **same seam** the generated `scrubPII` handler wires
into — capture and production use one entry point. Verify each platform's handler
signature against the live docs before use; the **iOS** snippet is checked against
the SDK headers, the **Android** snippet mirrors the shipped handler template and
should be confirmed on a real Android build.

## Safety

The file is **real plaintext PII**: write it to the app sandbox only, never show
raw values (the classifier redacts), delete it after the manifest is built, and
remove the injected snippet so it never ships. See `../../references/safety.md`.
