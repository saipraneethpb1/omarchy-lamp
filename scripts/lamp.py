#!/usr/bin/env python3
"""Lamp session store. Local files only. No network."""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE_DIR = Path.home() / ".local" / "state" / "omarchy" / "lamp"
SHARE_DIR = Path.home() / ".local" / "share" / "omarchy-lamp"
SESSION_PATH = STATE_DIR / "session.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def today_stamp() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%d")


def load_session() -> dict:
    if not SESSION_PATH.exists():
        return {"lit": False}
    try:
        data = json.loads(SESSION_PATH.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
    except (OSError, json.JSONDecodeError):
        pass
    return {"lit": False}


def save_session(data: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = SESSION_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, SESSION_PATH)


def append_journal(entry: str) -> Path:
    SHARE_DIR.mkdir(parents=True, exist_ok=True)
    path = SHARE_DIR / f"{today_stamp()}.md"
    header_needed = not path.exists()
    with path.open("a", encoding="utf-8") as fh:
        if header_needed:
            fh.write(f"# {today_stamp()}\n\n")
        fh.write(entry.rstrip() + "\n\n")
    return path


def cmd_status() -> int:
    session = load_session()
    print(json.dumps(session, ensure_ascii=False))
    return 0


def cmd_light(intention: str) -> int:
    intention = " ".join(intention.split()).strip()
    if not intention:
        print(json.dumps({"error": "empty-intention"}))
        return 2
    if len(intention) > 160:
        intention = intention[:160].rstrip()
    session = {
        "lit": True,
        "intention": intention,
        "startedAt": now_iso(),
        "endedAt": None,
        "close": None,
    }
    save_session(session)
    print(json.dumps(session, ensure_ascii=False))
    return 0


def cmd_extinguish(close: str) -> int:
    session = load_session()
    if not session.get("lit"):
        print(json.dumps({"error": "not-lit", "lit": False}))
        return 1
    close = " ".join(close.split()).strip()
    session["lit"] = False
    session["endedAt"] = now_iso()
    session["close"] = close or None
    save_session(session)

    started = session.get("startedAt") or "?"
    ended = session.get("endedAt") or "?"
    intention = session.get("intention") or "(none)"
    lines = [
        f"## {started} → {ended}",
        "",
        f"**Intention:** {intention}",
    ]
    if close:
        lines += ["", f"**What moved:** {close}"]
    path = append_journal("\n".join(lines))
    out = dict(session)
    out["journal"] = str(path)
    print(json.dumps(out, ensure_ascii=False))
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        return cmd_status()
    action = argv[0]
    rest = " ".join(argv[1:]).strip()
    if action == "status":
        return cmd_status()
    if action == "light":
        return cmd_light(rest)
    if action == "extinguish":
        return cmd_extinguish(rest)
    print(json.dumps({"error": "unknown-command"}))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
