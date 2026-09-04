# Lamp

Light a session with one sentence of intention.

![Lamp in the Omarchy bar, lit, with the session panel open](preview.png)

The bar holds a quiet flame and an elapsed clock until you put it out. When you extinguish it, Lamp asks what moved, then appends a page to a local markdown journal. No account. No network. No extra packages.

This is the opposite of a streak tracker. It does not block websites, swap your wallpaper, or start a 25-minute timer. It gives the desktop a beginning and an end.

## Why this exists

The Omarchy marketplace already has clocks, sports scores, AI usage meters, marketplace browsers, website blockers, pomodoros, workspace modes, and desktop pets.

What it does not have is a *session*.

Omarchy is an agentic OS that still belongs to a person. Lamp is the human half of that sentence: you say what this stretch of time is for, you do the work, you write one line about what actually moved. Agents can keep running. The machine remembers the work as prose, not as a dashboard.

## Install

```bash
omarchy plugin add https://github.com/saipraneethpb1/omarchy-lamp.git --enable
```

Then place **Lamp** in the bar from `Setup > Plugins` if it is not already there, or:

```bash
omarchy plugin enable saipraneethpb1.lamp --section center
```

Summon without the bar:

```bash
omarchy-shell shell toggle saipraneethpb1.lamp '{}'
```

Optional keybind in `~/.config/hypr/bindings.lua` after checking `omarchy menu keybindings --print`:

```lua
o.bind("SUPER + SHIFT + L", "Lamp", "omarchy-shell shell toggle saipraneethpb1.lamp '{}'")
```

## Use

1. Click the bar or hit the keybind.
2. Type one sentence. Example: `Finish the marketplace submission for Lamp`.
3. Optionally give yourself a time: click `25m` / `50m` / `90m`, or press `↓`
   and fill in hours, minutes, and seconds. Leave them blank for no limit.
4. Enter lights it. The bar reads `◉ Finish the marketplace…  47m 12s`.
5. Past the time you set, the bar turns red — the lamp is still lit and the
   clock keeps running, you are just over. Nothing interrupts you.
6. Click again when you stop. Type what moved, or leave it blank.
7. Escape closes the overlay without changing the session.

## Files it writes

| Path | What |
|---|---|
| `~/.local/state/omarchy/lamp/session.json` | Current flame, with its time limit |
| `~/.local/share/omarchy-lamp/YYYY-MM-DD.md` | Daily journal |

Both stay on this machine. Removal does not delete them.

Example journal page:

```markdown
# 2026-09-04

## 2026-09-04T10:41:00+05:30 → 2026-09-04T12:03:00+05:30

**Intention:** Finish the marketplace submission for Lamp

**Planned:** 1h 30m

**What moved:** Manifest, overlay, and the first honest README
```

## Requirements

- Omarchy Quattro (`omarchy-shell`)
- Python 3 from the Omarchy install (stdlib only)
- No network, no extra packages, no sudo, no install hook

## Remove

```bash
omarchy plugin disable saipraneethpb1.lamp
omarchy plugin remove saipraneethpb1.lamp
```

Or by hand:

```bash
rm -rf ~/.config/omarchy/plugins/saipraneethpb1.lamp
omarchy-shell shell rescanPlugins
```

Optional cleanup of local pages:

```bash
rm -rf ~/.local/state/omarchy/lamp ~/.local/share/omarchy-lamp
```

## Validate

```bash
omarchy plugin validate .
```

## Security

Lamp runs inside `omarchy-shell` with your user permissions, like every other plugin. The helper `scripts/lamp.py` only reads and writes the two paths above. It does not spawn a shell, does not touch your theme, and does not call the network.

Marketplace listing is not a security audit. Read the three QML files and the helper before you enable it.

## License

MIT
