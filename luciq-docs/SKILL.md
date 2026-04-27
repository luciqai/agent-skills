---
name: luciq-docs
description: Look up Luciq mobile SDK APIs, configuration, features, and platform support by fetching docs.luciq.ai. Use when the user asks "how do I X with Luciq", "what is the Luciq API for X", "does Luciq support X on [platform]", or any documentation question about the Luciq SDK. Returns a direct answer with a platform-targeted code snippet and a source URL. Used directly by engineers and indirectly by other Luciq skills (luciq-setup, luciq-debug, luciq-migrate, luciq-feature-flags) when they need to verify a Luciq API surface.
---

<!--
Triggers (things the user might say):
- "how do I [X] with Luciq"
- "what is the Luciq API for [X]"
- "does Luciq support [X] on iOS / Android / Flutter / RN / KMP"
- "show me the Luciq docs for [X]"
- any documentation question about the Luciq SDK
-->

# Luciq SDK Documentation Lookup

Answer Luciq SDK questions grounded in the official docs site at `https://docs.luciq.ai`.

## Workflow

1. Detect target platform (skip for conceptual questions)
2. Locate the right doc page via WebSearch or a known entry point
3. WebFetch that page (and linked sub-pages as needed) to extract the exact answer
4. Return: direct answer + platform code snippet + source URL

## 1. Detect platform (skip for conceptual questions)

Skip if the question is conceptual ("what is session profiler", "how do feature flags work").

For platform-specific questions, run a single Glob at workspace root: `{pubspec.yaml,package.json,*.xcodeproj,*.xcworkspace,build.gradle,build.gradle.kts,shared/build.gradle.kts}`. First match:

| File | Platform |
|---|---|
| `pubspec.yaml` | Flutter |
| `package.json` containing `"react-native"` | React Native |
| `shared/build.gradle.kts` with `kotlin("multiplatform")` | KMP |
| `*.xcodeproj` / `*.xcworkspace` only | iOS |
| `build.gradle*` only | Android |

If the user explicitly names a platform in their question, that wins over auto-detection.

## 2. Entry points

Always fetch live from `https://docs.luciq.ai`. NEVER rely on a local clone.

| Scope | Entry point |
|---|---|
| iOS | `https://docs.luciq.ai/ios` |
| Android | `https://docs.luciq.ai/android` |
| React Native | `https://docs.luciq.ai/react-native` |
| Flutter | `https://docs.luciq.ai/flutter` |
| KMP | `https://docs.luciq.ai/kmp` |
| Cross-cutting product guides (MCP, AI features, integrations) | `https://docs.luciq.ai/product-guides-and-integrations/product-guides` |

## 3. Find the exact page

Two strategies — pick whichever lands on the answer fastest:

**A. WebSearch first (preferred for narrow questions):**
- Query: `site:docs.luciq.ai <platform> <topic>` — e.g. `site:docs.luciq.ai ios auto-masking`
- WebFetch the top hit.

**B. Entry-point crawl (for broad / exploratory questions):**
- WebFetch the platform entry point (table above) to get the table of contents.
- Pick the most relevant linked page; WebFetch it.
- Follow one more hop if the answer lives in a sub-page.

Cap at 3 WebFetch calls per question. If you can't find the answer, say so — DO NOT guess.

## 4. Answer format

ALWAYS produce in this order:

1. **Direct answer** — one to three sentences. Don't restate the question.
2. **Code snippet** for the detected platform — copy-pasteable, taken directly from the doc page. Skip if the question is conceptual.
3. **Source** — the exact `docs.luciq.ai` URL used.

If a feature isn't supported on the user's platform, say so explicitly and link to the support matrix or the platform's docs index.

## Style

- DO NOT fabricate API names, method signatures, or flag names. Quote them from the page you fetched.
- DO NOT dump entire doc pages — extract the answer.
- DO NOT mix platforms (no Swift snippet for a Flutter project).
- DO NOT rely on memory of past doc structures — the docs evolve; always refetch.
- If WebFetch returns nothing useful after 3 attempts, surface that and stop.
