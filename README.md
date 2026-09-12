# mGBAHold

A ~210 KB menu-bar app that holds keys **inside mGBA only**, in the background, so you
can keep working while your Pokémon rack up steps.

Keystrokes are delivered with `CGEvent.postToPid()` straight into mGBA's process
queue. They never touch the app you're actually typing in — no global hotkey
hijacking, no focus stealing.

## Setup (one time)

1. `./build.sh` (already done — `mGBAHold.app` is next to this file)
2. Open `mGBAHold.app`. A game-controller icon appears in the menu bar.
3. Grant Accessibility: **System Settings → Privacy & Security → Accessibility →
   enable mGBAHold.** macOS requires this for any app that synthesises keystrokes.
   Quit and reopen mGBAHold after granting.
4. In mGBA: **Settings → Emulation** — make sure *Pause when minimized* won't bite you.
   Don't minimize mGBA while grinding; leaving it behind other windows is fine.

## Use

- Menu bar icon → **Start** / **Stop**.
- **⌃⌥⌘G** toggles from anywhere, so you can panic-stop without switching apps.
- **Profile** picks what to hold. **Turn interval** retunes the reversal timer without
  editing anything.
- Stopping (or quitting, or mGBA quitting) always releases every key. No stuck buttons.

## Profiles

| Profile | Holds | Cycle |
|---|---|---|
| `tunnel` *(default)* | Tab (fast-forward) | Up 1s ↔ Down 1s |
| `tunnel-long` | Tab | Up 4s ↔ Down 4s |
| `side-to-side` | Tab | Left 1s ↔ Right 1s |
| `mash-a` | Tab | X (= A button) tapped ~4×/s |
| `tunnel-normal-speed` | — | Up 1s ↔ Down 1s |

Short 1s legs make you ping-pong between two tiles, so you can never wall out and
stop earning steps. Long legs cover more corridor but need the interval tuned to the
corridor length — watch it once at normal speed and adjust.

## Config

`~/.config/mgbahold/config.json` — **Edit config…** in the menu opens it,
**Reload config** applies it.

```json
{
  "targetBundleID": "com.endrift.mgba-qt",
  "activeProfile": "tunnel",
  "refreshMillis": 500,
  "profiles": {
    "tunnel": {
      "hold": ["tab"],
      "cycle": [
        { "keys": ["up"],   "seconds": 1.0 },
        { "keys": ["down"], "seconds": 1.0 }
      ]
    }
  }
}
```

- `hold` — held down for the whole session (Tab = mGBA's fast-forward).
- `cycle` — steps run in order and loop. Each step holds `keys` for `seconds`, then
  releases whatever isn't in the next step or in `hold`. `"keys": []` = a pause,
  which is how `mash-a` gets a tap instead of a hold.
- `refreshMillis` — re-presses held keys this often. mGBA clears its key state when its
  window loses focus, so this is what keeps the hold alive after you click away. Set
  `0` to disable.

Key names: `up down left right`, `a`–`z`, `0`–`9`, `tab space return escape backspace`,
`f1`–`f12`, `shift control option command`, `home end pageup pagedown`,
`keypad0`–`keypad9`, and the punctuation keys.

mGBA's default GBA bindings: **X** = A, **Z** = B, **A** = L, **S** = R,
**Enter** = Start, **Backspace** = Select, **Tab** = fast-forward (hold).

## Notes

- Idles at 0% CPU. While running it posts ~2–4 events/sec.
- Rebuilding changes the code signature, so macOS may ask you to re-grant
  Accessibility (remove the old entry with `−`, re-add the new build).
- To start it at login: System Settings → General → Login Items → add `mGBAHold.app`.
