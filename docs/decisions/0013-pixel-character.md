# ADR-0013: A pixel character that is also a gauge

- Status: Accepted
- Date: 2026-10-14, selectable characters added 2026-10-17

## Context

Tokta worked but felt generic. The idea was a character that *is* the gauge, rather than decoration next to one. Five rounds of pixel sketches (v1 to v5, of which only `design/pixel-character-v5` is kept) ended on a 16×16 Mac window with traffic-light buttons and a text-emoticon face.

## Decision

- How much of the window's screen is filled with light shows how much is left. The colors follow the user's palette.
- The face shows the state: `^_^` plenty, `•_•` normal or unknown, `>_<` with a sweat drop when low, `-_-` with a Z when used up, and `^o^` with sparkles within 30 minutes after a reset.
- Animation: blinking eyes, a blinking cursor, and the screen filling in four steps after a reset. It stays still when Reduce Motion is on.
- `Shared/PixelCharacter.swift` draws it from code as a 16×16 grid, matching `design/pixel-character-v5/sprites.py`. Larger sizes are integer scales.
- It appears in first-run setup, the empty menu, widgets, alert text, and optionally as the menu bar icon.

## Selectable characters (2026-10-17)

Six more characters can be chosen in Settings → General → Character: battery, chip, mug, potion, slime and robot. The Mac window stays the default. Every character follows the same rules, so all of them read the same way:

- 16×16 and flat colors, using shared inks: outline, light surface, gauge, plus one accent color per character.
- A gauge area inside the body fills with light as much as is left: bottom to top, or left to right for the battery.
- The same five faces in an 8×5 area that sits inside the gauge. The cursor appears only if it fits.
- Decorations (sweat, Z, sparks, steam) are drawn only on empty cells.

`design/pixel-character-v6/sprites.py` holds each character as a 16-line map and draws the reference sheet. `Shared/PixelCharacters.swift` carries the same maps, and `PixelCharacterTests` checks that the app's pixels match the design PNGs exactly.

The choice is stored in App Group defaults, so Mac widgets read it directly. The Mac also sends it in the synced widget data, and the iPhone saves it for its own widgets.

## Consequences

- One drawing function serves the Mac app, widgets and the iPhone app.
- A new character is a new map in both files plus a new design sheet. No drawing code changes.
