# Routing — where each finding gets fixed

Every approved finding goes to exactly one of two places, decided by **where the
data lives**, not how sensitive it is. This mirrors the split in the Network
Security Controls model and the Chrome-extension prompt.

| Location | Manifest field | Route | Why |
|---|---|---|---|
| Request/response **header** key | — (server list) | **A — Luciq CSM** | Luciq auto-masks header/query keys from a server-side list. Adding a key is a config change, no app release. |
| **Query-parameter** key | — (server list) | **A — Luciq CSM** | Same server-side list as headers. |
| Request/response **body** field | `bodyFields` | **B — your code** | Luciq masks no body content. Only your scrub handler can. |
| **URL path** segment | `pathPatterns` | **B — your code** | Luciq masks no path content. Only your scrub handler can. |

## Route A — Luciq CSM (server-side auto-mask list)

`emit_manifest.py` writes these to `csm-keys.txt`. They are **not** code — surface
them as a copy-paste support request in the handoff:

> Email your Luciq CSM to add these keys to the automatic network mask list for
> app `<token>`: `x-acme-session`, `x-org-id`. These cannot be masked in client
> code and apply from the next session.

The default list already covers `authorization`, `token`, `password`, `api_key`,
`client_secret`, etc. (SDK ≥ 14.2.0). **Do not** route a key that's already in the
default list — check `references/network-masking.md` in `luciq-masking-rules`
first, and only send genuinely custom keys.

## Route B — your code (the generated scrub handler)

Body fields and path patterns go into `sensitivity-manifest.json` and are consumed
by the generated `scrubPII` handler:

- `bodyFields` → recursive field-name redaction at any nesting depth (`***`).
- `pathPatterns` → regex replacement in the URL path.

Obfuscate vs omit:

| Signal | Recommend |
|---|---|
| Body field is sensitive but the request is still useful for debugging | **Obfuscate** (default — redact the field) |
| Even the URL/metadata is sensitive (e.g. `/patients/{mrn}/diagnosis`) | **Omit** the whole request (`omitLog`) |

The generator defaults to **obfuscate**; propose **omit** only for endpoints where
the path or existence itself leaks. Debuggability matters — prefer redacting fields
over dropping whole logs unless the metadata is the problem.

## What routing does NOT decide

- **Screenshots / Session Replay.** A different surface — `luciq-masking-rules`.
- **Whether the SDK is ≥ 14.2.0.** If it's older, auto-masking (Route A) isn't
  default-on. Surface an SDK-version check and route to `luciq-migrate` if needed.
