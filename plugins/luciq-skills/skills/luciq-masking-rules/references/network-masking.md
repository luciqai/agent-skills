# Network Log Masking

The second surface. Network logs are captured client-side and masked client-side — masked data never leaves the device. Two layers: automatic key masking (default-on from SDK 14.2.0) and manual obfuscate/omit.

Verify the live key list, SDK version baseline, and per-platform call signatures against the live docs before quoting them in the conversation.

## Layer 1 — Automatic header & query-parameter masking

Default-on starting SDK **14.2.0**. The SDK strips values for a known-sensitive key set from headers and query parameters before the log is written. The key name still appears on the dashboard; the value is replaced with `*`.

### Default masked key list

| Category | Keys |
|---|---|
| Authorization | `authorization_token`, `auth_token`, `auth`, `access_token`, `token`, `oauth_token`, `bearer_token`, `refresh_token`, `jwt_token`, `jwt` |
| Login | `username`, `password`, `pwd` |
| API keys | `api_key`, `apikey` |
| Secrets | `secret`, `client_secret`, `app_secret`, `consumer_secret` |

### Extending the list

The list is configurable **server-side**. New keys can be added without a code change and apply from the next session. The audit cannot apply this — surface it as a support-ticket request in the handoff, with the proposed keys named:

> *"Email Luciq support to add the following keys to the automatic network mask list for app `<token>`: `x-patient-id`, `x-org-id`. These can't be configured from the client."*

### Disabling auto-mask (only if absolutely necessary)

State the consequence before applying. Disabling means raw `authorization` / `password` / `api_key` values reach Luciq storage — that's almost never the right call. Surface as a red flag.

```kotlin
Luciq.setNetworkAutoMaskingState(Feature.State.DISABLED)
```
```swift
NetworkLogger.autoMaskingEnabled = false
```

Objective-C equivalent: `IBGNetworkLogger.autoMaskingEnabled = false;`

## Layer 2 — Manual obfuscate / omit

Two operations:

- **Obfuscate** — rewrite sensitive request/response content before it's logged. The log is still captured; the values change.
- **Omit** — drop the log entirely. Use when even the URL or status code is sensitive (e.g., a `/patients/{mrn}/diagnosis` endpoint).

### Flutter

```dart
NetworkLogger.obfuscateLog(request);  // rewrite
NetworkLogger.omitLog(request);       // drop
```

Verify per-platform call signatures against the live docs.

### When to propose each

| Signal | Recommend |
|---|---|
| URL path contains a PII identifier (`/users/{email}/...`, `/patients/{mrn}/...`) | **Omit** |
| Request body has a high-sensitivity field not in the default key list (e.g. `dateOfBirth`, `taxId`) | **Obfuscate** (rewrite that field) |
| Response body contains PHI / financial data the dashboard doesn't need | **Obfuscate** or **Omit** depending on whether status/timing matters |
| Internal admin endpoint a developer doesn't want noisy in production | **Omit** |

### Payload masking — three options

1. **Whole-payload omit** — `omitLog(request)` based on URL or method match.
2. **Selective rewrite** — `obfuscateLog(request)` mutating specific fields, leaving structure intact.
3. **Pass-through with auto-mask only** — the default; relies on layer 1.

For sensitive endpoints, propose option 2 over option 1 — debuggability matters too. Reserve option 1 for endpoints where even the metadata is sensitive.

## SDK version gate

Confirm the SDK version before recapping. Read from:

| Platform | File |
|---|---|
| iOS | `Podfile.lock`, `Package.resolved` |
| Android | `build.gradle(.kts)` dependency declaration |
| Flutter | `pubspec.lock` |
| React Native | `package.json` / `yarn.lock` / `package-lock.json` |

Below 14.2.0 → auto-masking is **not** default-on. Surface as a "Close now" item: either upgrade the SDK (route to `luciq-migrate`) or explicitly enable auto-masking. State which.

## What the network layer does NOT cover

- **Screenshots and Session Replay frames.** Different surface — see `auto-mask-types.md`.
- **Backend processing.** Masking happens before storage; once a request has been logged with an unmasked value (older SDK, auto-mask disabled), the value is in storage. Forward-only fix.
- **Custom logging your app does outside Luciq's capture.** Console logs, third-party crash reporters, debug builds — none of these are touched by Luciq's network mask.
