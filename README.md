# D&D Spell Binder

Per-spell hotkeys for **Dark and Darker** Sorcerer on macOS. Bind any key or mouse button to instantly load a spell from either wheel — no more flick-and-pray.

> ⚠️ **Intended for private servers / friend lobbies only.** This tool synthesizes mouse motion to operate the in-game radial menu. On official servers with EasyAntiCheat enabled, that's an ToS / bannable category. Use it where you and your friends control the rules.

## What it does

Dark and Darker's Sorcerer spell wheel is a 5-slot radial menu opened with `Q` (Wheel I) or `E` (Wheel II). Selecting a spell means holding the wheel key, flicking the mouse in the spell's direction, and releasing. This tool collapses that into a single keypress (or mouse-button press) per spell.

- 10 directly-bindable slots (5 per wheel × 2 wheels)
- Capture-any-key / capture-any-mouse-button binding UI
- Modifier support (Shift+, Cmd+, etc.) on both keys and mouse
- Humanized motion: each cast uses a curved mouse path with randomized angle, radius, timing, and micro-wobble
- Aim restored after every cast — your reticle stays where you put it
- JSON config: shareable, hand-editable, exportable from the GUI

## Install (macOS)

One command:

```bash
curl -fsSL https://raw.githubusercontent.com/pureinkart-tech/dnd-spell-binder/main/install.sh | bash
```

The script installs Hammerspoon if needed, drops the two files into `~/.hammerspoon/`, wires up `init.lua`, and reloads. After it finishes, grant Hammerspoon Accessibility permission if you haven't already (System Settings → Privacy & Security → Accessibility → enable Hammerspoon), then click the 🪄 in your menu bar.

## Usage

1. Click the 🪄 menu-bar icon → **Settings…**
2. The GUI shows your current bindings. Click any **Key / Button** cell, then press the key or mouse button you want to bind. Press **Esc** to cancel.
3. Change wheel (Q/E) and slot (1–5) per binding with the dropdowns.
4. Add or remove bindings with the buttons at the top.
5. Changes auto-save and rebind live — no reload needed.

### Slot numbering

Slots are numbered clockwise from 12 o'clock:

```
       1
   5       2
   4       3
       (pentagon, point up)
```

| Slot | Position    |
|------|-------------|
| 1    | top         |
| 2    | upper-right |
| 3    | lower-right |
| 4    | lower-left  |
| 5    | upper-left  |

### Mouse button names

- `mouse3` = middle click (scroll-wheel press)
- `mouse4` = first thumb side button
- `mouse5` = second thumb side button
- `mouse6`–`mouse12` = additional side buttons (gaming mice with 6+ buttons)

## In-game setup

1. Set Wheel I keybind in D&D settings to `Q` (default) — or change `wheel` in your bindings to whatever key you use
2. Set Wheel II keybind to `E` — same caveat
3. Equip Spell Memory and Spell Memory II perks
4. Load all 10 spells into your wheels, then **memorize the slot order** — your bindings call positions, not spell names. If you reorder spells in-game, your hotkeys point at the new spells in those slots.

## Configuration file

Your bindings, geometry, and tuning live at:

```
~/.hammerspoon/dnd_spells.json
```

The GUI edits the `bindings` section. The `geometry` and `tuning` sections are hand-editable:

| Field | Default | Meaning |
|---|---|---|
| `geometry.slots` | `[-90, -18, 54, 126, -162]` | Slot angles in degrees (0=right, -90=up). Regular pentagon, point up. |
| `geometry.flick_radius` | `220` | Pixels from screen center to slot. Increase for higher resolutions. |
| `tuning.angle_jitter` | `8` | ± degrees of random angle wobble per cast |
| `tuning.radius_jitter` | `25` | ± pixels of random distance variation |
| `tuning.hold_ms` | `55` | Base milliseconds the wheel key is held |
| `tuning.steps` | `5` | Mouse path subdivisions (1 = teleport, 8+ = very smooth) |
| `tuning.curve_offset` | `18` | Sideways bow on the mouse path |

## Sharing your config with friends

1. In the GUI, click **Copy JSON to Clipboard**
2. Paste to your friend
3. They save it as `~/.hammerspoon/dnd_spells.json` and reload Hammerspoon (menu-bar icon → Reload Config)

Or just have each friend run the installer; the default 10-binding F1–F10 layout works out of the box.

## Compatibility

- Works inside **CrossOver** (input passes through to the bottled game normally)
- Does **not** work over **GeForce Now** — NVIDIA's client intercepts raw input before macOS event taps can synthesize. Use locally.
- Apple Silicon and Intel Macs both supported (Hammerspoon is universal)

## Files

- `dnd_spells.lua` — the runtime: macro engine, eventtap, menubar, webview launcher
- `dnd_spells_ui.html` — the binding editor served in a Hammerspoon webview
- `install.sh` — one-shot installer

## License

MIT. Do whatever; no warranty.
