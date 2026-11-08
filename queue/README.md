# The queue

Every piece of work is a markdown ticket in this folder, and the state of the board
is whatever is committed here. Nothing important lives in a chat window or in
anyone's head: if a session dies, the queue is still here.

Two parties work it, and they never do each other's job:

- **The agent** researches, builds, tests and verifies, in cycles
  (`/queue-cycle`). It cannot decide.
- **The owner** decides. Everything that needs a decision lands in the
  **inbox** (`./tools/queue.py inbox`, or `/inbox` to be walked through it one
  item at a time). The owner also merges, and merging `main` is what deploys
  (`.github/workflows/deploy.yml`). The agent never merges.

The one habit that makes this work: **take one item, load its context, rule, and
close it.** A ruling puts the ticket back in the queue with your verdict on the
card, so nothing is left for you to remember.

## A ticket

`queue/NNNN-slug.md`, a small header and a markdown body:

```markdown
---
id: 0007
title: West's beat 4 is unreachable
state: ruling
priority: 2
kind: design
updated: 2026-11-08
---

## Context
What is true now, with file:line pointers. Enough to rule without opening the code.

## Decision needed
The question, the options, and **Recommendation:** the one the agent would take.

## What was built
(when in `review`) What changed, why, how it was checked, the branch and PR.

## Log
- 2026-11-08 · agent · new → ruling: researched; two options.
```

The header holds `id`, `title`, `state`, `priority` (1 = most urgent … 4), `kind`
(`bug`, `design`, `feature`, `chore`, `playtest`, `art`) and `updated`. The script
maintains `waiting_since`, `asks`, `branch`, `pr` and `blocked_by` when they apply.
Do not hand-edit `state`; move it with the script so the log records who moved it.

## States, and whose turn it is

| State | Whose turn | Means |
|---|---|---|
| `new` | agent | captured; research it and write the decision |
| `ruling` | **owner** | needs a decision; has `## Decision needed` |
| `ready` | agent | owner said build it |
| `building` | agent | on a `claude/*` branch |
| `review` | **owner** | built; has `## What was built`, a branch and a PR |
| `verify` | agent | merged; check it on `main` and the deployed build |
| `blocked` | — | waits on another ticket (`blocked_by`); the board flags it once that is done |
| `parked` | — | owner deferred it; out of every list until reopened |
| `done`, `dropped` | — | closed |

**Only the owner can make a ticket `ready`.** There is no path from research to
building that skips a ruling, which is what "safe to build" means here. Anything
touching the kernel, the world format or a rule in `AGENTS.md` §"Critical decisions"
must say so in its `## Decision needed`.

## Rulings

```bash
./tools/queue.py rule 0007 build                  # take the recommendation
./tools/queue.py rule 0007 build "but keep the pit width"
./tools/queue.py rule 0007 answer "spans should be shorter; re-research"
./tools/queue.py rule 0012 approve                # after merging the PR
./tools/queue.py rule 0012 rework "the HUD flash is too long"
./tools/queue.py rule 0007 park "after save points"
./tools/queue.py rule 0007 drop
./tools/queue.py rule 0007 reopen
```

`build` with no note means *take the recommendation*, so a well-written ticket is a
one-word ruling. `answer` and `rework` require a note: they send the ticket back to
the agent, and the note is the instruction.

## Keeping tickets out of loops

A ticket that keeps coming back to the owner is the thing that breaks this.

- `asks` counts how many times a ticket has entered the inbox. At **3** the inbox
  marks it **looping**: rule it, park it, or drop it; do not answer it again.
- The agent may only send a ticket back to `ruling` with something **new** in it,
  and always with a recommendation, so "take the recommendation" is always a
  possible answer.
- A question the agent can answer by reading the code, the tests or `git log` is
  not a question for the owner.

## The viewer

`./tools/queue.py html -o <file>` renders the whole board, with a review page per
ticket, as one self-contained page. The agent rebuilds and republishes it as a Claude
artifact at the end of every cycle. The page is only a viewer; it composes the
`rule` command for you to run (or paste to the agent), and **git is the record**.

Published at: https://claude.ai/artifact/WQtLDnnnk6W5D7Z1E3MCVi
