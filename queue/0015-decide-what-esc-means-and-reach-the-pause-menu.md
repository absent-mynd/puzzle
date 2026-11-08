---
id: 0015
title: Decide what Esc means, and reach the pause menu
state: ruling
priority: 2
kind: design
updated: 2026-11-08
waiting_since: 2026-11-08
asks: 1
---

## Context

The pause menu and settings screen are complete and wired but unreachable: nothing
opens `scenes/ui/PauseMenu.tscn`, so the volume sliders can only be set by hand in
`user://settings.json`. `Esc` currently leaves the run for whatever opened it
(`docs/features/SHELL.md` §"Known gaps").

## Decision needed

What should `Esc` do in a run?

- **A.** `Esc` opens the pause menu; the menu has "Back to editor" / "Back to launcher".
- **B.** Keep `Esc` = leave; bind the pause menu to another key.
- **C.** A only for runs started from the launcher; from the editor `Esc` keeps
  returning straight to the editor (the authoring loop stays one key).

Touches `Shell` and the screens' signals, not the kernel.

**Recommendation:** C. It keeps the editor loop fast and makes the menu reachable in
the build players see.

## Log
- 2026-11-08 · agent · created: migrated from STATUS.md when the queue was set up
