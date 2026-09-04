#!/usr/bin/env bash
# Copy this plugin into the Omarchy plugin dir. The shell watches that path and
# hot-reloads on change; it does not follow symlinks, so this has to be a copy.
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$HOME/.config/omarchy/plugins/lamp.session"

rm -rf "$dest"
mkdir -p "$dest"
cp -r "$src"/*.qml "$src"/*.js "$src"/manifest.json "$src"/LICENSE "$src"/README.md "$dest/"
mkdir -p "$dest/scripts"
cp "$src/scripts/lamp.py" "$dest/scripts/"

echo "deployed to $dest"
