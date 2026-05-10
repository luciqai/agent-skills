---
name: luciq-test
description: Use only as part of testing the docs auto-sync routine. Triggers include phrases like "run a routine smoke test", "test the agent-skills docs sync", or "validate new skill generation end-to-end". Not for production use. This skill exists solely to verify that adding a new skill on agent-skills main causes the auto-sync routine to fire and generate the corresponding docs page on luciq-docs.
---

# Luciq Test Skill

Stub skill used to validate the docs auto-sync routine when introducing a new skill end-to-end. Not a real skill — has no production behavior. Will be removed in a follow-up PR after the routine smoke test completes.

## When NOT to use this skill

This skill is a test artifact, not a real workflow. Hand off in all cases:

- The user is asking about Luciq SDK setup, use `luciq-setup`.
- The user is investigating a crash, hang, or bug, use `luciq-debug`.
- The user wants to migrate or upgrade the Luciq SDK, use `luciq-migrate`.
- The user is doing literally anything other than testing the auto-sync routine, none of these.

If the user's request fits any real scenario, STOP and route them to the right skill rather than running this one.

## Workflow

### Step 1. Confirm this is a routine test

Confirm with the user that they are intentionally invoking the test skill as part of validating the docs auto-sync routine. If they aren't, stop and explain that this skill is a test artifact and shouldn't be invoked for real work.

### Step 2. Report back

Print: "luciq-test invoked. This is a test stub for the docs auto-sync routine. No real action taken."

## Style

- Don't actually do anything.
- This skill exists only to validate the auto-sync routine's NEW and REMOVED code paths.

## Red Flags - STOP and surface to the user

If you catch yourself thinking any of these, you're hallucinating this skill's purpose:

- "This skill looks like it does something useful." It doesn't. It's a stub.
- "I should invoke this skill for the user." Don't. It's a test artifact.
- "I'll extend this skill with real behavior." Don't. Delete it instead and write a real skill from scratch.
