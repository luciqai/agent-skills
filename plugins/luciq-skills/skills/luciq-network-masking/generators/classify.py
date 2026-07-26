#!/usr/bin/env python3
"""
classify.py — turn a captured debug session into a reviewed, routed PII list.

Reads a capture file (JSONL, one assembled HTTP flow per line, see FLOW SHAPE
below), scans every header / query / path / body field with two independent
signals, and emits a deduplicated review list. Nothing is written to the app
here — this only proposes. A human promotes the candidates.

This is the deterministic half of luciq-network-masking and is fully offline: no
Frida, no device, no network. It is safe to unit-test in CI.

FLOW SHAPE (one JSON object per line in the capture file):
  {
    "method":       "POST",
    "url":          "https://api.acme.com/v1/users/a@b.com/orders?token=ey..",
    "host":         "api.acme.com",
    "reqHeaders":   {"authorization": "Bearer ..", "x-acme-session": ".."},
    "reqBody":      "{\"password\":\"..\",\"profile\":{\"national_id\":\"..\"}}",
    "respHeaders":  {"content-type": "application/json"},
    "respBody":     "{\"user\":{\"email\":\"a@b.com\"}}"
  }
Any field may be missing. Bodies may be JSON strings, dicts, or plain text.

OUTPUT (stdout, JSON):
  {
    "findings":     [ {location, key, route, signals, count, example}, ... ],
    "hosts":        {host: flow_count, ...},
    "bodyCoverage": {host: {reqWithBody, respWithBody, flows}, ...},
    "summary":      {flows, endpoints, findings, bodiesSeen}
  }

bodyCoverage is the seam-health signal. If a host shows findings from
headers/query/path but reqWithBody == respWithBody == 0 while ANOTHER host on
the same run DID capture bodies, the empty bodies are a capture limitation for
that host (custom URLSessionDelegate session, or a self-signed / local HTTP
backend Luciq can't re-issue against) — NOT an absent PII. Do not silently ship
a body-less manifest; see the SKILL red flags.

Routing follows the Network Security Controls model:
  header key / query key  -> route "csm"   (Luciq server-side auto-mask list)
  body field              -> route "code"  (manifest.bodyFields, scrub handler)
  url path segment        -> route "code"  (manifest.pathPatterns, scrub handler)

Usage:
  python3 classify.py capture.jsonl [--hosts api.acme.com,auth.acme.com]
"""

from __future__ import annotations
import json
import re
import sys
from urllib.parse import urlsplit, parse_qsl

# --- Signal 1: sensitive key-name tokens (whole-token match, not substring) ---
# "pan" flags a "pan" field but NOT "companion"; "key" does NOT flag "monkey".
SENSITIVE_TOKENS = {
    "password", "passwd", "pwd", "secret", "token", "auth", "authorization",
    "session", "refresh", "apikey", "api_key", "ssn", "social", "pan", "card",
    "cardnumber", "cvv", "cvc", "pin", "email", "mail", "phone", "mobile",
    "msisdn", "dob", "birthdate", "dateofbirth", "national", "nationalid",
    "passport", "license", "otp", "bearer", "iban", "account", "taxid",
}

# Split an identifier into lowercase word tokens across camelCase, snake_case,
# kebab-case, and dotted paths so whole-token matching works on real keys.
_SPLIT = re.compile(r"[^A-Za-z0-9]+|(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])")


def tokens(name: str) -> set[str]:
    return {t.lower() for t in _SPLIT.split(name) if t}


def name_hits(name: str) -> set[str]:
    # Match on whole word tokens, AND on the separator-stripped collapsed form so
    # compound keys resolve: "apiKey"/"api_key" -> "apikey", "cardNumber" ->
    # "cardnumber". Collapsing never turns "companion" into a token match because
    # the collapsed string is checked against the set as a whole, not as a substring.
    hits = tokens(name) & SENSITIVE_TOKENS
    collapsed = re.sub(r"[^a-z0-9]", "", name.lower())
    if collapsed in SENSITIVE_TOKENS:
        hits.add(collapsed)
    return hits


# --- Signal 2: sensitive value shapes (only meaningful on pre-scrub data) ---
_EMAIL = re.compile(r"^[\w.+-]+@[\w-]+\.[\w.]+$")
_JWT = re.compile(r"^ey[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+$")
_SSN = re.compile(r"^\d{3}-\d{2}-\d{4}$")
_DIGITS = re.compile(r"^\d{9,}$")
_CARD = re.compile(r"^\d{13,19}$")


def _luhn(number: str) -> bool:
    total, alt = 0, False
    for ch in reversed(number):
        d = ord(ch) - 48
        if alt:
            d *= 2
            if d > 9:
                d -= 9
        total += d
        alt = not alt
    return total % 10 == 0


def value_shape(value) -> str | None:
    if not isinstance(value, str):
        return None
    v = value.strip()
    if _EMAIL.match(v):
        return "email"
    if _JWT.match(v):
        return "jwt"
    if _SSN.match(v):
        return "ssn"
    if _CARD.match(v) and _luhn(v):
        return "card"
    if _DIGITS.match(v):
        return "long-digit-run"
    return None


def redact(value) -> str:
    """First char .. last char + length — never the raw value."""
    if not isinstance(value, str):
        value = json.dumps(value)
    v = value.strip()
    n = len(v)
    if n <= 2:
        return f"** ({n} chars)"
    return f"{v[0]}…{v[-1]} ({n} chars)"


# --- Body walking: find sensitive leaf keys at any nesting depth -------------
def walk_body(node, on_field):
    """Call on_field(key, value) for every scalar leaf under a dict/list tree."""
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(v, (dict, list)):
                walk_body(v, on_field)
            else:
                on_field(k, v)
    elif isinstance(node, list):
        for item in node:
            walk_body(item, on_field)


def parse_body(body):
    if body is None:
        return None
    if isinstance(body, (dict, list)):
        return body
    if isinstance(body, str):
        s = body.strip()
        if not s:
            return None
        try:
            return json.loads(s)
        except (ValueError, TypeError):
            return None  # non-JSON body: key-name signal not applicable
    return None


# --- Finding aggregation ----------------------------------------------------
class Findings:
    def __init__(self):
        self._by_id = {}

    def add(self, location, key, route, signals, example):
        fid = (location, key.lower())
        f = self._by_id.get(fid)
        if f is None:
            f = {
                "location": location,
                "key": key,
                "route": route,
                "signals": set(),
                "count": 0,
                "example": example,
            }
            self._by_id[fid] = f
        f["signals"].update(signals)
        f["count"] += 1
        if example and (not f["example"] or f["example"].startswith("**")):
            f["example"] = example

    def as_list(self):
        order = {"header": 0, "query": 1, "path": 2, "body": 3}
        out = []
        for f in self._by_id.values():
            out.append({**f, "signals": sorted(f["signals"])})
        out.sort(key=lambda f: (order.get(f["location"], 9), f["key"].lower()))
        return out


def route_for(location: str) -> str:
    return "csm" if location in ("header", "query") else "code"


def classify_flow(flow: dict, findings: Findings):
    # Headers (both request and response) --> route csm
    for section in ("reqHeaders", "respHeaders"):
        for k, v in (flow.get(section) or {}).items():
            sig = set()
            if name_hits(k):
                sig.add("name")
            shape = value_shape(v)
            if shape:
                sig.add(f"value:{shape}")
            if sig:
                findings.add("header", k, "csm", sig, redact(v))

    # URL: query params --> csm ; path segments --> code (pathPatterns)
    parts = urlsplit(flow.get("url") or "")
    for k, v in parse_qsl(parts.query, keep_blank_values=True):
        sig = set()
        if name_hits(k):
            sig.add("name")
        shape = value_shape(v)
        if shape:
            sig.add(f"value:{shape}")
        if sig:
            findings.add("query", k, "csm", sig, redact(v))

    for seg in parts.path.split("/"):
        if not seg:
            continue
        shape = value_shape(seg)
        if shape:
            findings.add("path", f"<{shape}>", "code", {f"value:{shape}"}, redact(seg))

    # Bodies (request and response) --> code (bodyFields)
    for section in ("reqBody", "respBody"):
        parsed = parse_body(flow.get(section))
        if parsed is None:
            continue

        def on_field(k, v):
            sig = set()
            if name_hits(k):
                sig.add("name")
            shape = value_shape(v)
            if shape:
                sig.add(f"value:{shape}")
            if sig:
                findings.add("body", k, "code", sig, redact(v))

        walk_body(parsed, on_field)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    path = argv[1]
    host_filter = None
    if "--hosts" in argv:
        host_filter = set(argv[argv.index("--hosts") + 1].split(","))

    findings = Findings()
    hosts: dict[str, int] = {}
    # Per-host body-capture tally: [reqWithBody, respWithBody, flows].
    coverage: dict[str, list[int]] = {}
    flows = 0
    endpoints = set()

    def has_body(section) -> bool:
        b = flow.get(section)
        return isinstance(b, (dict, list)) or (isinstance(b, str) and bool(b.strip()))

    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                flow = json.loads(line)
            except ValueError:
                continue
            host = flow.get("host") or urlsplit(flow.get("url") or "").hostname or ""
            if host_filter is not None and host not in host_filter:
                continue
            flows += 1
            hosts[host] = hosts.get(host, 0) + 1
            cov = coverage.setdefault(host, [0, 0, 0])
            cov[2] += 1
            if has_body("reqBody"):
                cov[0] += 1
            if has_body("respBody"):
                cov[1] += 1
            parts = urlsplit(flow.get("url") or "")
            endpoints.add((flow.get("method", "GET"), host, parts.path))
            classify_flow(flow, findings)

    body_coverage = {
        h: {"reqWithBody": c[0], "respWithBody": c[1], "flows": c[2]}
        for h, c in sorted(coverage.items(), key=lambda kv: -kv[1][2])
    }
    bodies_seen = sum(c[0] + c[1] for c in coverage.values())

    result = {
        "findings": findings.as_list(),
        "hosts": dict(sorted(hosts.items(), key=lambda kv: -kv[1])),
        "bodyCoverage": body_coverage,
        "summary": {
            "flows": flows,
            "endpoints": len(endpoints),
            "findings": len(findings.as_list()),
            "bodiesSeen": bodies_seen,
        },
    }
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
