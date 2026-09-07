#!/usr/bin/env python3
"""Lamp session store. Local files only. No network."""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE_DIR = Path.home() / ".local" / "state" / "omarchy" / "lamp"
DEFAULT_SHARE_DIR = Path.home() / ".local" / "share" / "omarchy-lamp"
SESSION_PATH = STATE_DIR / "session.json"
MAX_TARGET_SECONDS = 24 * 60 * 60


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def today_stamp() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%d")


def format_duration(total_seconds: int) -> str:
    total = clamp_seconds(total_seconds)
    hours, rest = divmod(total, 3600)
    minutes, seconds = divmod(rest, 60)
    parts = []
    if hours:
        parts.append(f"{hours}h")
    if minutes:
        parts.append(f"{minutes}m")
    if seconds:
        parts.append(f"{seconds}s")
    return " ".join(parts)


def clamp_seconds(value) -> int:
    try:
        return max(0, min(MAX_TARGET_SECONDS, int(value)))
    except (TypeError, ValueError):
        return 0


def session_target(session: dict) -> int:
    """Target in seconds, tolerating sessions written before seconds existed."""
    seconds = clamp_seconds(session.get("targetSeconds"))
    if seconds:
        return seconds
    return clamp_seconds(clamp_seconds(session.get("targetMinutes")) * 60)


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


def resolve_journal_dir(raw) -> Path:
    """Where the journal lands. Empty or unset keeps the historical location."""
    candidate = (raw or "").strip()
    if not candidate:
        return DEFAULT_SHARE_DIR
    return Path(os.path.expanduser(os.path.expandvars(candidate)))


def append_journal(entry: str, share_dir: Path) -> Path:
    share_dir.mkdir(parents=True, exist_ok=True)
    path = share_dir / f"{today_stamp()}.md"
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


def cmd_light(intention: str, target_seconds: int = 0) -> int:
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
        "targetSeconds": clamp_seconds(target_seconds) or None,
    }
    save_session(session)
    print(json.dumps(session, ensure_ascii=False))
    return 0


def cmd_extinguish(close: str, share_dir: Path) -> int:
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
    target = session_target(session)
    if target:
        lines += ["", f"**Planned:** {format_duration(target)}"]
    if close:
        lines += ["", f"**What moved:** {close}"]
    path = append_journal("\n".join(lines), share_dir)
    out = dict(session)
    out["journal"] = str(path)
    print(json.dumps(out, ensure_ascii=False))
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        return cmd_status()
    action = argv[0]
    args = argv[1:]

    # "--journal-dir <path>" is honoured only immediately after the action, so a
    # free-form intention or close note may still contain the literal text.
    share_dir = DEFAULT_SHARE_DIR
    if len(args) >= 2 and args[0] == "--journal-dir":
        share_dir = resolve_journal_dir(args[1])
        args = args[2:]

    if action == "status":
        return cmd_status()
    if action == "light":
        target = 0
        # "light --for <seconds> <intention...>"; the flag is optional so the
        # older "light <intention...>" form still works.
        if len(args) >= 2 and args[0] == "--for":
            target = clamp_seconds(args[1])
            args = args[2:]
        return cmd_light(" ".join(args).strip(), target)
    if action == "extinguish":
        return cmd_extinguish(" ".join(args).strip(), share_dir)
    print(json.dumps({"error": "unknown-command"}))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
