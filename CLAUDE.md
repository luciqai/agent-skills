# Working on the Luciq agent skills

The skills under `plugins/luciq-skills/skills/` ship to users through npm and the plugin marketplaces, and agents copy their code into real apps. A wrong API name in a skill becomes a broken build in someone's app. Nothing at the repo root or in `.claude/` ships.

Before opening a PR that touches `plugins/`, run `/review-skill-change`.

## Rules

1. **Always check every SDK or MCP name in the SDK codebase or the public docs at https://docs.luciq.ai/ before writing it.** Never write one from memory, from another skill, or from an old Instabug name. If you can't check it, leave it out or say it's unverified. In the PR, cite where each new name came from: the version and file:line, or the docs URL.
2. **When the docs and the code disagree, the code wins.** Report the docs page so it can be fixed.
3. **Don't assume one platform's API works on another.** Each platform (iOS, Android, React Native, Flutter, KMP) has its own names and setup steps. Check each one separately.
4. **Change the skills that share an API together.** luciq-setup writes code, luciq-verify checks for it, luciq-onboard and luciq-masking-rules recommend it, and luciq-debug explains it. They must name the same calls. Before committing, grep `plugins/` for every name you changed, old and new.
5. **Code in a skill must build** at the version you cite. Build it when you can. Test a release build or archive as well, because debug builds can skip build phases and code shrinking.
6. **Behavior claims need a source too.** What a call does, what it counts or which MCP actions exist all need evidence. For a limit you saw rather than read, write "observed <Mon YYYY>".
7. **Scripts never pass user input through a shell.** Pass arguments as an array, not an interpolated string. Validate any value pasted into a generated script.
8. **Skill descriptions** start with "Use when…" and use the words users actually type, not internal jargon. Keep them between 400 and 1,200 characters. A new skill needs a route from its neighbours' "When NOT" lists.

## Where to check names

Check every name in at least one of these places: the SDK codebase, or the public docs at https://docs.luciq.ai/. Use the code when it's available.

| Platform | SDK codebase | Public docs |
| --- | --- | --- |
| Flutter | `luciqai/luciq-flutter-sdk` at the release tag: the package source and its example app | docs.luciq.ai › Flutter |
| React Native | `luciqai/luciq-reactnative-sdk`: the module sources and exports | docs.luciq.ai › React Native |
| iOS | Binary SDK. Use the native bridges in the React Native and Flutter SDKs | docs.luciq.ai › iOS (the main source) |
| Android | Binary SDK. Use the native bridges in the React Native and Flutter SDKs, plus Maven Central for coordinates | docs.luciq.ai › Android (the main source) |
| MCP | A live `tools/list` | docs.luciq.ai › MCP Tools Reference |

- **Read an SDK file at a tag:** `gh api "repos/luciqai/<repo>/contents/<path>?ref=<tag>" --jq .content | base64 -d`.
- **Read a docs page as text:** find it in `https://docs.luciq.ai/llms.txt`, then `curl -s <page-url>.md`.

## Testing

- **Test the configuration apps ship**, release or archive, not only debug.
- **Xcode's script sandbox is off under `/tmp` and `/private/tmp`**, so test sandboxed builds in a folder under `$HOME`.
- **Never send real data from a test.** Put a stub CLI first on `PATH` and use the skill's skip or dry-run switch.
- **In the PR, say what you built or ran, and what you couldn't.**

## PRs

- Use conventional commits, for example `fix(<skill-name>): …`.
- PR body sections: **What was wrong / Evidence / What changed**. Evidence means version plus file:line or a docs URL, and what you built or ran.
- A fork PR can't be the base of another PR. A follow-up targets `main` and says "merge after #N".
