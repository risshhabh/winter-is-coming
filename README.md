#           ❄︎ WinterIsComing ❄︎

Let it snow on your Mac! ☃️

Snow falls on your desktop, drifts on the wind and piles up on your windows and Dock. Every flake is drawn in code.

<!-- ![demo](docs/demo.gif) -->

## What it can do ✨

- 🌨️ **Natural snowfall**: fine specks, small clumps, the occasional big fluffy flake and a rare six-armed crystal, each with its own size, tumble and fall speed
- 🌬️ **Real wind**: a wind field that varies across the screen, with gusts that travel through it. Flakes near each other move alike; flakes far apart don't
- 🎚️ **Three kinds of weather**: Light Snow, Gentle Snowfall and Snowstorm. Switching eases over a few seconds
- 🏔️ **Snow piles up** on top of your windows, along the Dock and at the bottom of the screen, unevenly, the way drifts do
- 🪟 **Snow rides your windows**: move one slowly and the pile comes along. Move it briskly and powder trickles off, jerk it and part of the pile slides and breaks away, shake it and each jolt throws more than the last
- 🖥️ **Every display**: snow falls on all connected displays, with one shared weather, and piles follow windows from one display to another
- ⚓ **Any Dock**: bottom, left or right, auto-hidden or not. Its snow survives hiding, resizing and magnification
- 🔘 **Rounded corners**: the snow line follows a window's corners down instead of floating beside them
- ↔️ **Resize a window** and the snow stays where it was; only the part that lost its ledge falls
- 🫥 **Nothing is lost** when you switch Spaces or click between overlapping windows. Minimize or close a window and its snow falls
- 💧 **Gradual melting** (optional), so piles settle at a level instead of filling up
- 🖱️ **Clicks always pass through**. The cursor stirs nearby flakes, more the faster it moves, and you choose how much (or turn it off)
- 🎅 **Festive cursor** (optional): a little Santa sleigh pulled by two galloping reindeer follows your cursor, or a Santa hat perches on it, or it just leaves a trail of snowflakes or golden sparkles
- 🔔 **Sleigh bells** (off until you turn them on): a faint shimmer while the cursor moves and the occasional bell on a fast sweep, all synthesized in code
- 💡 **Christmas lights** (optional): warm white or multicolored strings under the menu bar and along the front window, twinkling gently and glowing on the snow beside them
- 🧊 **Window frost** (optional): branching frost creeps into the corners of windows that sit still, faster in heavy weather
- 🛷 **Santa flyovers and rare events** (optional): now and then a sleigh crosses the sky, a shooting star streaks past, a gust blows through or powder lifts off a snowy window
- ⛄ **Play Mode** (off until you turn it on): roll snowballs out of the snow, push them, carry them, and stack three into a snowman

## Try it 🚀

```sh
git clone https://github.com/risshhabh/winter-is-coming.git
cd winter-is-coming
zsh build.sh              # build and run from the terminal
# or
zsh Scripts/bundle.sh     # build WinterIsComing.app
open WinterIsComing.app
```

Use the ❄︎ in the menu bar to pause, pick the weather, turn melting or Play Mode on, clear the snow, or quit.

- No `swift`? Run `xcode-select --install` first.
- Want snow on the Dock too? Turn on **WinterIsComing** (or your terminal, if you ran `build.sh`) in System Settings → Privacy & Security → Accessibility.

## Menu

| Item | What it does |
|---|---|
| Light Snow / Gentle Snowfall / Snowstorm | Density, flake sizes, wind, fall speed and how fast snow builds up |
| Snow in Front of Windows | A sparse layer of small flakes falls over your windows as well as behind them. Turn it off to keep window contents clear |
| Gradual Melting | Piles slowly shrink, so they level off below their maximum |
| Cursor Stirs Snow | Off, Subtle, Normal or Strong |
| Cursor Effect | Normal Cursor, Santa Sleigh, Santa Hat, Snowflake Trail or Golden Sparkle Trail |
| Companion Size | Small, Medium or Large |
| Sleigh Bells, Mute, Volume | Movement-driven bells. Off by default; Mute and switching the effect off silence it at once |
| Decorations | Christmas Lights (off, warm, multicolored), brightness and density; Window Frost; Santa Flyovers frequency; Atmospheric Events; and two "now" items for trying them out |
| Play Mode (Snowballs) | Hover over snow and move sideways to roll a snowball; hold the mouse button to carry it. Always off at launch |

## How it is put together 🧩

```
Sources/WinterCore/        the simulation; no AppKit or SpriteKit, fully unit-tested
  WindField, Weather         wind field, presets and their slow natural variation
  FlakeSystem                falling flakes
  PowderSystem               loose powder and the rare compact fragment
  SnowField                  one pile: a height map with exact snow accounting
  SurfaceManager             piles for every window, the Dock and the ground; occlusion; collisions
  WindowKinematics           how a window's velocity and acceleration dislodge its snow
  QualityGovernor            thins the snowfall when frames get expensive
  CursorCompanion            how the sleigh or hat chases the cursor: spring, facing, tilt, gallop, idle
  BellSequencer, BellSynth   when a bell rings and how loud; the synthesized bell sounds
  Atmosphere                 EventDirector (what rare thing happens when) and light-string layout and twinkle
Sources/WinterIsComing/    the app
  SnowModel                  the one shared winter: fixed-step loop, window polling, per-display flakes
  OverlayController          one click-through overlay per display, kept in step with the display list
  SnowScene                  mirrors one display's part of the model into SpriteKit
  Render/                    procedural textures, particle sprites, the pile shader
  Play/                      snowballs and snowmen
  Festive/                   CursorTracker, FestiveArt, CompanionRenderer, BellAudio, Decorations (lights, frost)
  WindowSource, DockTracker  where the windows and the Dock are
Tests/WinterCoreTests/     73 tests: wind, accumulation, particles, window motion, Dock, displays, cursor, festive, atmosphere, cost
```

Run the tests with `swift test`.

## See it without watching the screen 📸

```sh
.build/release/WinterIsComing --snapshot out.png --preset storm --seconds 300
```

This runs the real model headlessly over a stand-in desktop and writes a PNG. Add `--light` for a light desktop, `--displays 2` for a second display, `--motion shake|jerk|slow|still` to choose what happens to one window just before the picture, `--lead 1.1` to take the picture later, `--melt` to turn melting on, and `--cursor sleigh|hat|snowTrail|goldTrail` to add a scripted cursor with that effect (`--rest` leaves it standing still, `--size 1.35` makes it large). `--lights warm|multi`, `--frost`, `--flyover` and `--events` add the decorations.

## What macOS does not let it do 🚧

- **The system cursor cannot be replaced** for other apps: every app sets its own cursor, and the public API only applies inside your own windows. So the sleigh and hat are companions drawn in the click-through overlay beside the real pointer, which keeps its arrow, I-beam and hand shapes. The companion trails the pointer by design, and sits behind it so it never covers the tip.
- **Everything is drawn in one layer above your windows**, so flyovers, shooting stars and frost pass in front of window content, not behind it. They are kept small, high up or in corners for that reason.
- **The overlay is below the menu bar and Dock**, so the companion slides under them when the cursor goes there.
- **Typing is detected only as "a key was pressed recently"** (no key contents, no permission needed); the companion fades back and bells pause for a moment after each key press.

- **Why a window left the screen** is not reported. The app infers it: gone means closed, a Space change at the same moment means it is on another Space (snow kept), anything else after 0.6 s means minimized or hidden (snow falls). A Space switch that macOS announces late could be mistaken for a minimize.
- **Window corner radius** is not available, so one value per macOS version is used (16 pt on macOS 26, 10 pt before). Windows with unusual corners will not match exactly.
- **Window positions are polled**, not pushed, so during a very fast drag the pile can trail the window by a frame or two.
- **Mission Control and Stage Manager** scale windows without changing their reported frames; piles stay where the frames say until you leave.
- **The Dock** can only be measured with Accessibility permission. A hidden Dock is recognised by being off its display, which can be wrong if another display sits just beyond that edge.
- **Displays stacked vertically**: snow falling off the bottom of the upper display does not continue onto the lower one.
- **Play Mode** snowballs stay on the display they were made on.

## License

[MIT](LICENSE). Based on [WINTER_IS_COMING](https://github.com/yike-shi/WINTER_IS_COMING) by Shi Yike, whose original copyright notice is kept in `LICENSE` and whose commit is the root of this repository's history. · Made with 💙 and a little help from Claude
