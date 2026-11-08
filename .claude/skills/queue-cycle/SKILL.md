---
name: queue-cycle
description: Run one agent cycle over the work queue in queue/ — verify merged work, build tickets the owner cleared, research new ones, then rebuild and republish the board viewer. Use when asked to "work the queue", "run a cycle", or under /loop.
---

# One cycle over the queue

The rules are in `queue/README.md`; read it first if you have not this session.
`tools/queue.py` is the only thing that moves a ticket. You research, build, test and
verify. **You never decide, and you never merge** (merging `main` deploys).

## 1. Sync and look

```bash
git fetch origin main && git status -sb
./tools/queue.py lint
./tools/queue.py next
```

`next` lists your work in the order to take it: finish before you start.

## 2. Take tickets in `next` order, until the cycle is a reasonable size

**verify** — the PR is merged. Check the change on `main`: run the tests it touched,
and if it is visible, run the game (`run` skill) and look. If the deploy workflow has
finished, note it. Then `move <id> done --note "checked: ..."`. If it is broken,
`move <id> ruling` with what you found and a recommendation.

**building / ready** — the owner cleared it; the log's last owner line is the brief.
1. `move <id> building --branch claude/<slug>` on a fresh branch from `main`.
2. Follow `AGENTS.md`: test first, the whole suite green (`HOME=/tmp/godot-home ./run_tests.sh`).
3. Write `## What was built` on the ticket: what changed and why, how you checked it
   (tests, a screenshot path, what you saw in the game), and anything you chose that the
   owner might choose differently.
4. Commit, push, open a PR, then `move <id> review --pr <url>`.
   If you hit a question only the owner can answer, stop and `move <id> ruling`.

**new** — research it. Read the code, the tests and `git log` until you can say what
is true and what the options are. Rewrite `## Context` so the owner can rule without
opening the code (file:line pointers, one screenful). Write `## Decision needed` with
the options and a `**Recommendation:**`. Say plainly if it touches the kernel, the
world format, or a rule in `AGENTS.md` §"Critical decisions". Then `move <id> ruling`.
If it depends on another ticket, `move <id> blocked --blocked-by <other>`.

**blocked, flagged unblocked** — `move <id> new` and research it again.

New work you discover goes in as `./tools/queue.py new "..." --kind ...`, not into
the ticket you are on.

## Rules that keep tickets out of loops

- Never send a ticket to `ruling` without something new in it and a recommendation.
- A question you can answer from the code, tests or history is not the owner's.
- Never touch a ticket in `ruling`, `review` or `parked` except to read it.

## 3. Close the cycle

```bash
./tools/queue.py lint
./tools/queue.py html -o /tmp/queue.html   # use your scratchpad directory
```

Commit the queue changes (`queue: cycle — <one line>`), push to your branch, and
republish the viewer as an artifact: the URL is at the bottom of `queue/README.md`.
Read that artifact first (`Artifact` action `read`), then publish the new file to the
same `url`. If no URL is recorded yet, publish a new one and write its URL into the
README in the same commit.

End with a short report: what moved, and `./tools/queue.py inbox` (what now waits on
the owner).
