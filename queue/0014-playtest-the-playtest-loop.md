---
id: 0014
title: Playtest the playtest loop
state: ruling
priority: 3
kind: playtest
updated: 2026-11-08
waiting_since: 2026-11-08
asks: 1
---

## Context

`F5` / `F6` and the launcher are new and have had no authoring session run through
them (`docs/features/SHELL.md` §"Known gaps"). Two cheap features are waiting on use
rather than guesswork.

## Decision needed

After one real authoring session, rule on each:

- Should "play from the cursor" (`F6`) remember where you last played from?
- Should a run be able to hand a cell back to the editor ("open the card I died on")?

**Recommendation:** Neither yet. Answer after a session; if either annoyed you, say
which and the agent builds it.

## Log
- 2026-11-08 · agent · created: migrated from STATUS.md when the queue was set up
