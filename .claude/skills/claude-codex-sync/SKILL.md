---
name: claude-codex-sync
description: Use when `.claude/skills` or `.claude` context docs changed and the same repository knowledge should be mirrored into Codex-local skills under `~/.codex/skills`.
---

# Claude Codex Sync

## When to use
- `.claude/skills/*` changed and Codex should discover the same workflows
- `AGENTS.md`, `CLAUDE.md`, `.claude/SKILL_REFERENCE.md`, or other repo context docs changed
- After adding or renaming repo-local Claude skills

## Source of truth
- Claude-side source: `.claude/skills/`
- Claude-side context docs: `.claude/*.md`, `AGENTS.md`, `CLAUDE.md`
- Codex sync helper skill: `~/.codex/skills/claude-to-codex-sync/SKILL.md`

## Rules
- Do not edit `.claude/` as part of the sync output itself.
- Treat repo `.claude/skills` as the source of truth.
- Prefer syncing after a clean commit or after the intended skill/doc changes are complete.
- Mention in release/worklog notes when sync-relevant skill boundaries changed.

## Workflow
1. Review `.claude/SKILL_REFERENCE.md` and confirm preferred skill boundaries still make sense.
2. Run the Codex-side sync helper:
   ```bash
   ~/.codex/bin/sync-claude-to-codex.sh "$PWD"
   ```
3. Verify one mirrored repo skill and one mirrored context file exist under `~/.codex/skills/`.
4. Tell the user that new sessions are the safest way to pick up newly mirrored skills.

## Repository-specific guidance
- Prefer `kbo-runtime-data` over narrower runtime skills unless the task is specifically relay-only or direct-ASMX-only.
- Prefer `kbo-release-flow` over `mobile-preview-release` for current repo release work.
- Prefer `kbo-history-snapshot` for snapshot policy, and use `bootstrap-fallback-data` only for bundled asset generation.
