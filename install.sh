#!/usr/bin/env bash
# D&D Spell Binder — one-shot installer for macOS
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/pureinkart-tech/dnd-spell-binder/main/install.sh | bash

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/pureinkart-tech/dnd-spell-binder/main"
HS_DIR="$HOME/.hammerspoon"

echo "==> D&D Spell Binder installer"

# 1. Hammerspoon check
if ! [ -d "/Applications/Hammerspoon.app" ]; then
  echo "==> Hammerspoon not found. Installing via Homebrew..."
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required. Install it from https://brew.sh and re-run." >&2
    exit 1
  fi
  brew install --cask hammerspoon
  echo
  echo "    Launch Hammerspoon once and grant it Accessibility permission:"
  echo "    System Settings → Privacy & Security → Accessibility → enable Hammerspoon"
  echo
  open -a Hammerspoon || true
fi

# 2. Files
mkdir -p "$HS_DIR"
echo "==> Downloading files to $HS_DIR"
curl -fsSL "$REPO_RAW/dnd_spells.lua"      -o "$HS_DIR/dnd_spells.lua"
curl -fsSL "$REPO_RAW/dnd_spells_ui.html"  -o "$HS_DIR/dnd_spells_ui.html"

# 3. init.lua wiring
INIT="$HS_DIR/init.lua"
LINE='require("dnd_spells").start()'
touch "$INIT"
if ! grep -Fqx "$LINE" "$INIT"; then
  echo "==> Adding require line to $INIT"
  printf '\n%s\n' "$LINE" >> "$INIT"
else
  echo "==> $INIT already has the require line"
fi

# 4. Reload (first-time may fail if AppleScript isn't enabled yet; that's OK,
#    our module enables it on load, so subsequent reloads will work)
echo "==> Reloading Hammerspoon config"
if ! osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' 2>/dev/null; then
  echo "    (First install — auto-reload not yet permitted. Click the Hammerspoon"
  echo "     menu-bar icon → Reload Config to finish. After that, future updates"
  echo "     can auto-reload from the command line.)"
fi

echo
echo "✅ Done. Click the 🪄 in your menu bar → Settings… to bind keys."
echo "   Default bindings: F1-F5 → Wheel Q,  F6-F10 → Wheel E"
