#!/usr/bin/env python3
"""
emit_manifest.py — write sensitivity-manifest.json from approved findings.

Input: a JSON file of APPROVED findings (the human-promoted subset of
classify.py's output — same object shape). Only findings routed to "code"
become the manifest; "csm" findings (header/query keys) are emitted as a
separate copy-paste list for the Luciq CSM, because they can't be masked in
client code.

Body fields  -> manifest.bodyFields   (deduped, lowercased)
Path shapes  -> manifest.pathPatterns  (regex, from a fixed shape->pattern map)
Header/query -> csm_keys.txt line list

Usage:
  python3 emit_manifest.py approved.json --out sensitivity-manifest.json \
      --csm-out csm-keys.txt [--version 1.0]
"""

from __future__ import annotations
import json
import sys

# Value-shape -> regex used in manifest.pathPatterns. Mirrors the patterns in
# the Network Security Controls doc so generated manifests match the reference.
SHAPE_TO_PATTERN = {
    "email": r"[\w.+-]+@[\w-]+\.[\w.]+",
    "ssn": r"\b\d{3}-\d{2}-\d{4}\b",
    "card": r"\b\d{13,19}\b",
    "long-digit-run": r"\b\d{9,}\b",
    "jwt": r"\bey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b",
}


def build(approved: list[dict], version: str):
    body_fields, path_patterns, csm_keys = set(), set(), []
    for f in approved:
        loc = f.get("location")
        if loc == "body":
            body_fields.add(f["key"].lower())
        elif loc == "path":
            for sig in f.get("signals", []):
                if sig.startswith("value:"):
                    shape = sig.split(":", 1)[1]
                    if shape in SHAPE_TO_PATTERN:
                        path_patterns.add(SHAPE_TO_PATTERN[shape])
        elif loc in ("header", "query"):
            csm_keys.append(f["key"])

    manifest = {
        "version": version,
        "bodyFields": sorted(body_fields),
        "pathPatterns": sorted(path_patterns),
    }
    # Dedup CSM keys case-insensitively, preserve first-seen casing.
    seen, csm = set(), []
    for k in csm_keys:
        if k.lower() not in seen:
            seen.add(k.lower())
            csm.append(k)
    return manifest, csm


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    args = argv[1:]
    src = args[0]

    def opt(flag, default=None):
        return args[args.index(flag) + 1] if flag in args else default

    out = opt("--out", "sensitivity-manifest.json")
    csm_out = opt("--csm-out", "csm-keys.txt")
    version = opt("--version", "1.0")

    with open(src, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    approved = data.get("findings", data) if isinstance(data, dict) else data

    manifest, csm = build(approved, version)

    with open(out, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")

    if csm:
        with open(csm_out, "w", encoding="utf-8") as fh:
            fh.write("# Send to Luciq CSM — add to the server-side auto-mask "
                     "key list (cannot be masked in client code):\n")
            for k in csm:
                fh.write(f"{k}\n")

    print(json.dumps({
        "manifest": out,
        "bodyFields": len(manifest["bodyFields"]),
        "pathPatterns": len(manifest["pathPatterns"]),
        "csm_keys": len(csm),
        "csm_out": csm_out if csm else None,
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
