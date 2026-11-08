---
id: 0008
title: Save points and checkpoints
state: new
priority: 2
kind: feature
updated: 2026-11-08
---

## Context

Undo is gone by design; respawn sends you to the region spawn. Save points are the
replacement, and they are also:

- the fix for stranding yourself (spend your last hands, walk where no seam reaches,
  and `R` is the only way back, costing position, fold configuration and any hand you
  dropped deliberately);
- what loose hands need to outlive a session. They are runtime-only
  (`FoldWorld.hand_pickups`), the first state that is not `(base, folds)`.

## Log
- 2026-11-08 · agent · created: migrated from STATUS.md when the queue was set up
