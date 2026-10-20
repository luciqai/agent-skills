---
description: Cut a new luciq-skills release — bump both version manifests, commit, tag, push, create the GitHub Release, and publish to npm.
argument-hint: "[major|minor|patch|x.y.z] (optional — inferred from commits if omitted)"
---

Cut a new release of `luciq-skills`. Requested bump: **$ARGUMENTS** (if empty, infer it in step 2).

Work through the phases in order. Do not skip the confirmation gate.

## 1. Survey

Run these together and read the results before deciding anything:

- `git status -sb` — the tree must be clean and on `main`, up to date with `origin/main`. If it is dirty, stop and report; never sweep unrelated changes into a release commit.
- `git tag --sort=-v:refname | head -3` and `node -p "require('./package.json').version"` — the current version.
- `git log --format='%s' <last-tag>..HEAD` — what is actually being released.
- `npm view luciq-skills version` — what the registry already has.
- `npm whoami` and `gh auth status` — which of the two publish paths will work.

## 2. Choose the version

If the user named a level or an explicit version, use it. Otherwise infer from the commit subjects since the last tag:

- any `feat` → **minor**
- only `fix` / `docs` / `chore` → **patch**
- a breaking change → **major**, and say why

State the target version and the reasoning in one line. If the inference is genuinely ambiguous — for instance a `feat` that is really a docs addition — ask rather than guess.

## 3. Bump both manifests

The version lives in **two** places and they must match:

- `package.json` → `version`
- `plugins/luciq-skills/.claude-plugin/plugin.json` → `version`

Edit both, then validate the JSON parses and both report the new version:

```bash
node -e 'const a=require("./package.json"),b=require("./plugins/luciq-skills/.claude-plugin/plugin.json");console.log(a.version,b.version)'
```

Do not use `npm version` — it only touches `package.json` and it creates the tag before you have confirmed the push.

## 4. Verify what npm would ship

```bash
npm publish --dry-run
```

`package.json` `files` is an allowlist, so confirm any newly added directories actually appear in the tarball. If this release added reference docs or a new skill, spot-check that those paths are listed. If expected files are missing, fix `files` before continuing — a published version cannot be replaced.

## 5. Confirmation gate

Before any outward-facing step, tell the user the target version, the release-note summary, and which of these you are about to do — then wait for a clear yes:

- push the commit and tag to `origin/main`
- create the GitHub Release
- publish to npm (**irreversible** — a published version number can never be reused)

Their answer may cover only part of that list. Honor exactly that scope.

## 6. Commit and tag

```bash
git add package.json plugins/luciq-skills/.claude-plugin/plugin.json
git commit -m "chore: release vX.Y.Z"
git tag -a vX.Y.Z -m "X.Y.Z"
```

Commits are SSH-signed through 1Password. If signing fails with `1Password: failed to fill whole buffer`, the vault is locked. `main` does not require signed commits, so retry with `--no-gpg-sign` — and state plainly in your summary that the commit is unsigned.

Tags are annotated, named `vX.Y.Z`, with the bare version as the message.

## 7. Push

```bash
git push origin main
git push origin vX.Y.Z
```

`main` requires a PR with code-owner approval, so expect a `Bypassed rule violations` warning on the push if the user is an admin. Report that it happened. If the push is *rejected* instead, stop and offer to open a release PR.

## 8. GitHub Release

Write notes to a scratch file and create the release against the pushed tag:

```bash
gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <path> --verify-tag
```

Group the notes under `## Features` / `## Fixes` / `## Docs` / `## Maintenance`, one bullet per user-visible change with its PR number, each written in terms of what it means for someone using the skills — not the commit subject verbatim. End with the compare link:

`**Full changelog:** https://github.com/luciqai/agent-skills/compare/vPREV...vX.Y.Z`

There is no `CHANGELOG.md` in this repo, so the GitHub Release is the only changelog. Write it accordingly.

## 9. npm

```bash
npm publish
```

If `npm whoami` failed back in step 1, **do not attempt to log in** — entering the user's npm credentials is theirs to do. Hand them `npm login && npm publish` and report the dry-run result as evidence the package is ready.

## 10. Report

State what landed and where, with the release URL and the published npm version. Call out explicitly anything you did *not* do (unpublished to npm, unsigned commit, skipped step) rather than letting a partial release read as complete.
