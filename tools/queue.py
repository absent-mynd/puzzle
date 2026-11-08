#!/usr/bin/env python3
"""The work queue: markdown tickets in queue/, read and moved by this one script.

The rules (states, who may move what, how rulings work) are in queue/README.md.
This file is their only implementation; if the two disagree, this is the bug.

    ./tools/queue.py board                  every open ticket, by state
    ./tools/queue.py inbox                  what waits on the owner, most urgent first
    ./tools/queue.py next                   what the agent should pick up, in order
    ./tools/queue.py show 0007
    ./tools/queue.py new "Title" [--kind bug] [--priority 2]
    ./tools/queue.py move 0007 review [--note ...] [--branch b] [--pr url] [--blocked-by 0003]
    ./tools/queue.py rule 0007 build ["note"]
    ./tools/queue.py lint
    ./tools/queue.py html -o board.html

Stdlib only. QUEUE_DIR and QUEUE_TODAY override the folder and the date (tests).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

STATES = ["new", "ruling", "ready", "building", "review", "verify",
          "blocked", "parked", "done", "dropped"]
OWNER_STATES = {"ruling", "review"}
AGENT_STATES = {"new", "ready", "building", "verify"}
CLOSED = {"done", "dropped"}
KINDS = {"bug", "design", "feature", "chore", "playtest", "art"}
LOOPING_AT = 3

# Moves the agent may make. Nothing here leads to `ready`: only a ruling does.
AGENT_MOVES = {
    "new": {"ruling", "blocked"},
    "ready": {"building", "ruling"},
    "building": {"review", "ruling", "blocked"},
    "verify": {"done", "ruling"},
    "blocked": {"new"},
}

# Owner verdicts: verb -> (states it applies to, resulting state, note required).
VERDICTS = {
    "build":   ({"new", "ruling", "parked", "blocked"}, "ready", False),
    "answer":  ({"ruling"}, "new", True),
    "approve": ({"review"}, "verify", False),
    "rework":  ({"review"}, "ready", True),
    "park":    (set(STATES) - CLOSED - {"parked"}, "parked", False),
    "drop":    (set(STATES) - CLOSED, "dropped", False),
    "reopen":  ({"parked", "done", "dropped"}, "new", False),
}

REQUIRED_SECTION = {"ruling": "Decision needed", "review": "What was built"}
HEADER_ORDER = ["id", "title", "state", "priority", "kind", "updated",
                "waiting_since", "asks", "blocked_by", "branch", "pr"]


def queue_dir() -> Path:
    return Path(os.environ.get("QUEUE_DIR", ROOT / "queue"))


def today() -> str:
    return os.environ.get("QUEUE_TODAY") or dt.date.today().isoformat()


class QueueError(Exception):
    pass


@dataclass
class Ticket:
    path: Path
    meta: dict
    body: str

    id = property(lambda s: s.meta.get("id", ""))
    title = property(lambda s: s.meta.get("title", ""))
    state = property(lambda s: s.meta.get("state", ""))

    @property
    def priority(self) -> int:
        try:
            return int(self.meta.get("priority", 3))
        except ValueError:
            return 9

    @property
    def asks(self) -> int:
        try:
            return int(self.meta.get("asks", 0))
        except ValueError:
            return 0

    def section(self, name: str) -> str:
        m = re.search(rf"^## {re.escape(name)}\s*\n(.*?)(?=^## |\Z)",
                      self.body, re.M | re.S)
        return m.group(1).strip() if m else ""

    def days_waiting(self) -> int:
        since = self.meta.get("waiting_since") or self.meta.get("updated")
        try:
            return (dt.date.fromisoformat(today()) - dt.date.fromisoformat(since)).days
        except (TypeError, ValueError):
            return 0

    def question(self) -> str:
        """The first line a reader needs: the decision, or what was built."""
        sec = self.section(REQUIRED_SECTION.get(self.state, "Context"))
        for line in sec.splitlines():
            line = line.strip().lstrip("-* ").strip()
            if line:
                return line
        return ""

    def text(self) -> str:
        keys = [k for k in HEADER_ORDER if self.meta.get(k) not in (None, "")]
        keys += [k for k in self.meta if k not in HEADER_ORDER and self.meta[k] != ""]
        head = "\n".join(f"{k}: {self.meta[k]}" for k in keys)
        return f"---\n{head}\n---\n\n{self.body.strip()}\n"

    def save(self) -> None:
        self.path.write_text(self.text(), encoding="utf-8")

    def log(self, who: str, what: str) -> None:
        entry = f"- {today()} · {who} · {what}"
        if re.search(r"^## Log\s*$", self.body, re.M):
            self.body = self.body.rstrip() + "\n" + entry
        else:
            self.body = self.body.rstrip() + "\n\n## Log\n" + entry
        self.meta["updated"] = today()

    def set_state(self, new: str, who: str, note: str = "") -> None:
        old = self.state
        self.meta["state"] = new
        if new in OWNER_STATES:
            self.meta["waiting_since"] = today()
            self.meta["asks"] = str(self.asks + 1)
        else:
            self.meta.pop("waiting_since", None)
        if new != "blocked":
            self.meta.pop("blocked_by", None)
        self.log(who, f"{old} → {new}" + (f": {note}" if note else ""))


def parse(path: Path) -> Ticket:
    raw = path.read_text(encoding="utf-8")
    m = re.match(r"---\n(.*?)\n---\n?(.*)", raw, re.S)
    if not m:
        raise QueueError(f"{path.name}: no --- header")
    meta = {}
    for line in m.group(1).splitlines():
        if line.strip():
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip()
    return Ticket(path, meta, m.group(2))


def load_all() -> list[Ticket]:
    return [parse(p) for p in sorted(queue_dir().glob("[0-9][0-9][0-9][0-9]-*.md"))]


def find(tickets: list[Ticket], tid: str) -> Ticket:
    tid = tid.zfill(4)
    for t in tickets:
        if t.id == tid:
            return t
    raise QueueError(f"no ticket {tid}")


def unblocked(t: Ticket, by_id: dict) -> bool:
    b = by_id.get(t.meta.get("blocked_by", ""))
    return t.state == "blocked" and b is not None and b.state in CLOSED


# ---------------------------------------------------------------- ordering

def inbox(tickets: list[Ticket]) -> list[Ticket]:
    """Owner items: priority, then looping ones, then finished work before
    questions (built work rots), then the longest-waiting."""
    items = [t for t in tickets if t.state in OWNER_STATES]
    return sorted(items, key=lambda t: (
        t.priority, t.asks < LOOPING_AT, t.state != "review", -t.days_waiting(), t.id))


def agent_next(tickets: list[Ticket]) -> list[Ticket]:
    """Finish before starting: verify, then building, then ready, then research."""
    by_id = {t.id: t for t in tickets}
    rank = {"verify": 0, "building": 1, "ready": 2, "new": 3, "blocked": 4}
    items = [t for t in tickets
             if t.state in AGENT_STATES or unblocked(t, by_id)]
    return sorted(items, key=lambda t: (rank[t.state], t.priority, t.id))


# ---------------------------------------------------------------- lint

def lint(tickets: list[Ticket]) -> list[str]:
    errs = []
    seen = {}
    by_id = {t.id: t for t in tickets}
    for t in tickets:
        n = t.path.name
        for k in ("id", "title", "state", "priority", "kind", "updated"):
            if not t.meta.get(k):
                errs.append(f"{n}: missing '{k}'")
        if t.id and not n.startswith(t.id + "-"):
            errs.append(f"{n}: id {t.id} does not match the file name")
        if t.id in seen:
            errs.append(f"{n}: id {t.id} also used by {seen[t.id]}")
        seen[t.id] = n
        if t.state not in STATES:
            errs.append(f"{n}: unknown state '{t.state}'")
        if t.meta.get("kind") and t.meta["kind"] not in KINDS:
            errs.append(f"{n}: unknown kind '{t.meta['kind']}'")
        if t.priority not in (1, 2, 3, 4):
            errs.append(f"{n}: priority must be 1-4")
        need = REQUIRED_SECTION.get(t.state)
        if need and not t.section(need):
            errs.append(f"{n}: state '{t.state}' needs a '## {need}' section")
        if t.state == "ruling" and "**Recommendation:**" not in t.section("Decision needed"):
            errs.append(f"{n}: '## Decision needed' has no **Recommendation:**")
        if t.state == "review" and not t.meta.get("branch"):
            errs.append(f"{n}: state 'review' needs a branch")
        if t.state == "blocked" and t.meta.get("blocked_by") not in by_id:
            errs.append(f"{n}: blocked_by must name an existing ticket")
    return errs


# ---------------------------------------------------------------- commands

def slugify(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:48] or "ticket"


def cmd_new(a) -> Ticket:
    tickets = load_all()
    nid = str(max([int(t.id) for t in tickets if t.id.isdigit()] + [0]) + 1).zfill(4)
    if a.kind not in KINDS:
        raise QueueError(f"kind must be one of {sorted(KINDS)}")
    t = Ticket(queue_dir() / f"{nid}-{slugify(a.title)}.md",
               {"id": nid, "title": a.title, "state": "new",
                "priority": str(a.priority), "kind": a.kind, "updated": today()},
               "## Context\n\n" + (a.context or "(to research)") + "\n")
    t.log(a.by, "created")
    t.save()
    print(t.path.relative_to(ROOT) if t.path.is_relative_to(ROOT) else t.path)
    return t


def cmd_move(a) -> Ticket:
    tickets = load_all()
    t = find(tickets, a.id)
    if a.to not in AGENT_MOVES.get(t.state, set()):
        allowed = sorted(AGENT_MOVES.get(t.state, set())) or "nothing (owner's turn)"
        raise QueueError(f"{t.id}: the agent cannot move {t.state} → {a.to}; "
                         f"from {t.state} it may move to {allowed}")
    if a.branch:
        t.meta["branch"] = a.branch
    if a.pr:
        t.meta["pr"] = a.pr
    if a.to == "blocked":
        if not a.blocked_by:
            raise QueueError("moving to blocked needs --blocked-by")
        find(tickets, a.blocked_by)
    t.set_state(a.to, "agent", a.note or "")
    if a.to == "blocked":
        t.meta["blocked_by"] = a.blocked_by.zfill(4)
    errs = lint([t] + [x for x in tickets if x.id != t.id])
    errs = [e for e in errs if e.startswith(t.path.name)]
    if errs:
        raise QueueError("refused, the ticket would be invalid:\n  " + "\n  ".join(errs))
    t.save()
    print(f"{t.id} → {t.state}")
    return t


def cmd_rule(a) -> Ticket:
    t = find(load_all(), a.id)
    if a.verdict not in VERDICTS:
        raise QueueError(f"verdict must be one of {sorted(VERDICTS)}")
    applies, to, needs_note = VERDICTS[a.verdict]
    if t.state not in applies:
        raise QueueError(f"{t.id} is '{t.state}'; '{a.verdict}' applies to {sorted(applies)}")
    if needs_note and not a.note:
        raise QueueError(f"'{a.verdict}' needs a note: it is the instruction")
    note = a.note or ("take the recommendation" if a.verdict == "build"
                      and t.state == "ruling" else "")
    t.set_state(to, "owner", f"{a.verdict}" + (f" — {note}" if note else ""))
    t.save()
    print(f"{t.id} → {t.state}")
    return t


def fmt_row(t: Ticket, extra: str = "") -> str:
    return f"  {t.id}  P{t.priority}  {t.meta.get('kind', ''):<8} {t.title}{extra}"


def cmd_board(_a) -> None:
    tickets = load_all()
    by_id = {t.id: t for t in tickets}
    for s in STATES:
        if s in CLOSED:
            continue
        group = sorted([t for t in tickets if t.state == s], key=lambda t: (t.priority, t.id))
        if group:
            print(f"\n{s.upper()} ({len(group)})")
            for t in group:
                flag = "  ← unblocked" if unblocked(t, by_id) else ""
                print(fmt_row(t, flag))
    closed = sum(t.state in CLOSED for t in tickets)
    print(f"\n{closed} closed. Owner inbox: {len(inbox(tickets))}.")


def cmd_inbox(_a) -> None:
    items = inbox(load_all())
    if not items:
        print("Inbox empty. Nothing waits on you.")
        return
    print(f"{len(items)} waiting on you, most urgent first:\n")
    for i, t in enumerate(items, 1):
        verb = "REVIEW" if t.state == "review" else "RULE"
        loop = "  ⚠ LOOPING: rule, park or drop" if t.asks >= LOOPING_AT else ""
        print(f"{i:>2}. {verb:<6} {t.id}  P{t.priority}  {t.title}"
              f"  ({t.days_waiting()}d, asked {t.asks}×){loop}")
        if t.question():
            print(f"           {t.question()[:110]}")


def cmd_next(_a) -> None:
    items = agent_next(load_all())
    if not items:
        print("Nothing for the agent. Everything open waits on the owner.")
    for t in items:
        print(fmt_row(t, f"  [{t.state}]"))


def cmd_show(a) -> None:
    print(find(load_all(), a.id).text())


def cmd_lint(_a) -> int:
    errs = lint(load_all())
    for e in errs:
        print(e)
    print(f"{len(errs)} problem(s)." if errs else "Queue is valid.")
    return 1 if errs else 0


def cmd_html(a) -> None:
    tickets = load_all()
    order = {t.id: i for i, t in enumerate(inbox(tickets))}
    data = []
    for t in tickets:
        data.append({
            "id": t.id, "title": t.title, "state": t.state, "priority": t.priority,
            "kind": t.meta.get("kind", ""), "updated": t.meta.get("updated", ""),
            "days": t.days_waiting(), "asks": t.asks, "looping": t.asks >= LOOPING_AT,
            "branch": t.meta.get("branch", ""), "pr": t.meta.get("pr", ""),
            "blocked_by": t.meta.get("blocked_by", ""), "question": t.question(),
            "inbox": order.get(t.id, -1), "body": t.body.strip(),
            "file": f"queue/{t.path.name}",
        })
    payload = json.dumps({"built": today(), "commit": _head(), "tickets": data,
                          "verdicts": {k: {"from": sorted(v[0]), "note": v[2]}
                                       for k, v in VERDICTS.items()}})
    payload = payload.replace("</", "<\\/")
    template = (Path(__file__).parent / "queue_viewer.html").read_text(encoding="utf-8")
    out = template.replace("/*__QUEUE_DATA__*/null", payload)
    Path(a.output).write_text(out, encoding="utf-8")
    print(a.output)


def _head() -> str:
    try:
        head = (ROOT / ".git" / "HEAD").read_text().strip()
        if head.startswith("ref: "):
            ref = ROOT / ".git" / head[5:]
            if ref.exists():
                return ref.read_text().strip()[:7]
            packed = (ROOT / ".git" / "packed-refs").read_text()
            m = re.search(rf"^(\w+) {re.escape(head[5:])}$", packed, re.M)
            return m.group(1)[:7] if m else ""
        return head[:7]
    except OSError:
        return ""


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="The work queue (see queue/README.md).")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("board").set_defaults(fn=cmd_board)
    sub.add_parser("inbox").set_defaults(fn=cmd_inbox)
    sub.add_parser("next").set_defaults(fn=cmd_next)
    sub.add_parser("lint").set_defaults(fn=cmd_lint)
    s = sub.add_parser("show"); s.add_argument("id"); s.set_defaults(fn=cmd_show)
    s = sub.add_parser("new")
    s.add_argument("title"); s.add_argument("--kind", default="feature")
    s.add_argument("--priority", type=int, default=3, choices=[1, 2, 3, 4])
    s.add_argument("--context"); s.add_argument("--by", default="agent")
    s.set_defaults(fn=cmd_new)
    s = sub.add_parser("move")
    s.add_argument("id"); s.add_argument("to", choices=STATES)
    s.add_argument("--note"); s.add_argument("--branch"); s.add_argument("--pr")
    s.add_argument("--blocked-by")
    s.set_defaults(fn=cmd_move)
    s = sub.add_parser("rule")
    s.add_argument("id"); s.add_argument("verdict"); s.add_argument("note", nargs="?")
    s.set_defaults(fn=cmd_rule)
    s = sub.add_parser("html"); s.add_argument("-o", "--output", required=True)
    s.set_defaults(fn=cmd_html)
    a = p.parse_args(argv)
    try:
        rc = a.fn(a)
    except QueueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    return rc if isinstance(rc, int) else 0


if __name__ == "__main__":
    sys.exit(main())
