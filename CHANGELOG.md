# Changelog

Notable changes to Lamp. Versions follow the `version` field in `manifest.json`.

Lamp installs as a git checkout, so `omarchy plugin update saipraneethpb1.lamp`
moves you to the latest commit on `main` rather than to a tagged release. Tags
are here for pinning: `git -C ~/.config/omarchy/plugins/saipraneethpb1.lamp
checkout v1.1.1`.

## 1.1.1 — 2026-09-08

### Fixed

- **Security.** Lamp refused nothing about where the journal went. Because the
  daily page name is predictable (`YYYY-MM-DD.md`), anyone able to write into a
  shared journal folder could pre-create that name as a symlink and have Lamp
  append into a file elsewhere. The folder is now canonicalized, opened with
  `O_NOFOLLOW`, and checked on the descriptor for your ownership and for
  group/world write bits; the page is opened relative to that descriptor with
  `O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW|O_CLOEXEC` at mode `0600` and confirmed
  to be a regular file you own. The link count is checked too, since
  `O_NOFOLLOW` does not stop a hard link. A failed check reports why instead of
  writing, and the session is still closed. Reported during marketplace review.

  Only affects `journalDir` set to a folder others can write to. The default
  `~/.local/share/omarchy-lamp` was never exposed. Pointing `journalDir` at a
  symlinked vault still works.

### Added

- `scripts/test_lamp.py` — regression tests for the journal write path
  (symlinked page, hard-linked page, shared folder, symlinked folder). Standard
  library only; run with `python3 scripts/test_lamp.py`.

## 1.1.0 — 2026-09-07

### Added

- **Tab moves between fields.** `Tab` and `Shift+Tab` walk every control the
  mouse can reach — the sentence, the duration presets, and the
  hour/minute/second fields, plus the Write/Code/Read chips and the Light
  button in the overlay. Presets answer `Enter` and `Space` and paint a focus
  ring. In the bar panel, tabbing past either end still hands focus to the
  neighbouring panel; the overlay wraps.
- **Configurable journal folder.** Set `journalDir` on Lamp's entry in
  `~/.config/omarchy/shell.json` to keep sessions in an Obsidian vault or any
  other folder. Empty or unset keeps `~/.local/share/omarchy-lamp`, and pages
  already written stay where they are. The helper takes the same value as
  `--journal-dir`.

### Fixed

- `PanelKeyCatcher` stood down only for the sentence field, so it would have
  taken the keys back the moment focus reached a preset.
- The instructions called the third preset `90m`; it renders as `1h 30m`.

## 1.0.0 — 2026-09-04

First marketplace submission.

- Light a session with one sentence of intention; the bar holds the flame and
  an elapsed clock until you put it out.
- Optional time limit, by preset or by hours/minutes/seconds. Past it the bar
  turns red and the clock keeps running — nothing blocks or interrupts.
- Extinguishing appends a page to a local markdown journal.
- No network, no accounts, no external dependencies, no install hook, no sudo.
