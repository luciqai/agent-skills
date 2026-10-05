---
name: review-skill-change
description: Use before opening or merging a PR that changes anything under plugins/luciq-skills/, or when asked to "review my skill change", "check this skill PR" or "is this safe to merge". Checks every SDK and MCP name the diff adds against the real SDK source, finds other skills that must change with it, checks that code blocks and scripts are sound, and returns a pass/fix list plus an Evidence section for the PR. For contributors to this repo; not part of the shipped skills.
disable-model-invocation: true
---

# Review a skill change

Work through the steps in order. The rules are in the root `CLAUDE.md`, so read it first. Report only what you checked. "Couldn't verify" is a valid result, and a guess is not.

## 1. Get the change

```bash
git fetch -q origin
git diff origin/main...HEAD --stat -- plugins/
git diff origin/main...HEAD -- plugins/
```

For a PR, use `gh pr diff <n> --repo luciqai/agent-skills` instead. A fork PR's head is at `refs/pull/<n>/head`.

## 2. List every name the diff adds or changes

Collect them from code blocks and backticks:

- **SDK calls:** methods, classes, modules, widgets and components, on every platform the diff touches
- **Config keys** (init options, Gradle DSL) and **package coordinates** (pub, npm, Maven, SPM)
- **MCP tool names, actions and parameters**
- **CLI commands and flags**

**If the diff edits a table or list of API names, check every name in that table, not only the changed rows.** Wrong names often sit next to the ones being fixed.

## 3. Check each name

For each name:

1. Check it in the SDK codebase or in the public docs at https://docs.luciq.ai/, at the SDK version the skill targets. The table in `CLAUDE.md` says where. Use the code when it's available. Never pass a name because it appears in another skill or "looks right".
2. Record the evidence: version plus file:line, or the docs URL. If the docs and the code disagree, the code wins. Add the docs page to the output as a docs bug.
3. Give a verdict: **verified**, **wrong** (with the real name), or **unverified**. An unverified name either comes out of the change or gets marked as unverified in the text.
4. If the change replaces a name, grep `plugins/` for the old one to confirm it's gone everywhere. A hit is fine only where the text warns against it.

## 4. Find the other skills that must change with it

```bash
git grep -n "<name or old name>" plugins/
```

Check that each pair still agrees:

- **luciq-setup ↔ luciq-verify:** setup writes the code and verify checks for the same call. A setup change with no matching extractor change, or the reverse, is a finding.
- **luciq-onboard and luciq-masking-rules ↔ luciq-setup:** what they recommend matches what setup installs.
- **Renamed MCP tools:** every skill that calls the old name is updated.

List each file that needs the same edit.

## 5. Check the code and scripts

- **Code blocks:** they must build at the cited version. Build them if a toolchain is available (`flutter analyze`, `xcodebuild`, `./gradlew assembleRelease`). Otherwise say they weren't built. Platform rules:
  - iOS: test Release or an archive, not only Debug. Sandbox tests run under `$HOME`, not `/tmp`.
  - Android: a minified release build catches R8 failures that Debug misses.
- **Changed scripts:**
  - Run `ruby -c` / `python3 -m py_compile` / `bash -n`.
  - Grep for shell interpolation of input: backticks, `system("…#{…}")`, `%x`, `eval`. Use argv calls instead.
  - Confirm that no real upload or network write happens in tests.

## 6. Check behavior claims

Any sentence about what a call does, when data is sent, or what the MCP can or can't do needs a source, or the wording "observed <Mon YYYY>". Flag anything that tells an agent to call an API on a path it doesn't cover, such as a "success" call placed on a failure or exit path.

## 7. If a SKILL.md frontmatter changed

- The description starts with "Use when…", uses the words users actually type, and is 400 to 1,200 characters long.
- Neighbouring skills route to it in their "When NOT" lists.

## Output

1. **Verdict:** safe to merge / merge after fixes / don't merge.
2. **Names table:** name | file:line | verified / wrong / unverified | evidence.
3. **Fix list:** blocking first, then suggestions, each with file:line and the exact change.
4. **Files that must change together** (step 4).
5. **Docs bugs:** pages on docs.luciq.ai that disagree with the SDK code, to report.
6. **Evidence section** ready to paste into the PR body: versions checked, sources used (SDK file:line or docs URL), and what was built or run.
