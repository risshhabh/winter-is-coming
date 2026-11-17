# Manual checks

Things the automated tests cannot see. Run after `zsh build.sh` (or open the bundled app).
Start with Snowstorm for a few minutes so the piles are worth moving.

## Dragging a window

- [ ] Drag slowly (a few centimetres a second): the pile rides along, attached to the top edge. No powder.
- [ ] Drag at a brisk, steady pace: a thin trickle of powder trails off; most of the pile stays.
- [ ] Start a drag with a sharp flick: part of the pile slides back along the top and some breaks away.
- [ ] Drag fast and stop dead: snow carries on forward off the window.
- [ ] Drag straight up or down quickly: same behaviour as sideways.
- [ ] While dragging, the pile does not visibly lag behind the window at slow speeds.

## Shaking

- [ ] One quick back-and-forth: some snow comes off as fine powder.
- [ ] Keep shaking for a second: each reversal throws more; the pile is nearly gone.
- [ ] Wait a few seconds, let snow rebuild, then nudge once: back to losing only a little.
- [ ] Powder spreads, drifts down and fades. No large white balls.

## Resizing

- [ ] Resize from the right edge, narrower: the snow that lost its ledge falls; the rest stays put.
- [ ] Resize from the left edge: the snow on the right does not move on screen.
- [ ] Make the window wider: existing snow stays; the new part starts bare.
- [ ] Resize only the height from the top edge: the pile moves with the top edge.

## Minimizing, closing, hiding, Spaces

- [ ] Minimize a snowy window: after a brief pause its snow falls as powder.
- [ ] Close a window: its snow falls.
- [ ] Hide an app (⌘H): its windows' snow falls.
- [ ] Switch to another Space and back: piles are as you left them (see limitations in the README).
- [ ] Enter and leave full screen: nothing strange is left behind.

## Overlap and edges

- [ ] Click between two overlapping windows several times: no snow disappears; covered snow returns when uncovered.
- [ ] At a window's rounded corners the snow line curves down with the corner and does not float off the side.
- [ ] Push a window halfway off the left, right and bottom of the screen: snow only builds on the visible part.
- [ ] Maximize a window: almost nothing falls behind it and CPU use drops.

## Dock (needs Accessibility permission)

- [ ] Bottom Dock: snow builds along the top of the icon area.
- [ ] Move the Dock to the left, then the right (System Settings → Desktop & Dock): a small cap of snow builds on top of it.
- [ ] Turn on auto-hide: the snow disappears with the Dock and is back, unchanged, when the Dock reappears.
- [ ] Open and quit an app so the Dock grows and shrinks: the snow stays; only the trimmed ends fall.
- [ ] Change the Dock size slider: same.
- [ ] Turn on magnification and sweep the cursor along the Dock: the snow is not thrown off.

## Multiple displays

- [ ] Snow falls on every display, with a snowbank along the bottom of each.
- [ ] Arrange a second display to the left of, above, and diagonally from the main one: piles sit exactly on window tops on both.
- [ ] Displays with different scaling (Retina beside non-Retina): snow is sharp on both and positions are right.
- [ ] Drag a snowy window from one display to the other: its pile goes with it.
- [ ] Leave a window straddling two displays: its pile shows on both halves.
- [ ] Unplug the second display: the main one carries on. Plug it back in: snow starts there again.
- [ ] Change a display's resolution: snow continues without a restart.
- [ ] Dock on the second display: snow builds on it there.

## Cursor

- [ ] Sweep the cursor quickly through falling snow: nearby flakes are pushed aside and dragged along a little.
- [ ] Move slowly: almost no effect.
- [ ] Stop: the flakes settle back into their normal drift within a second or two.
- [ ] Menu → Cursor Stirs Snow → Off, Subtle, Normal, Strong: the effect changes to match.
- [ ] Move back and forth over a pile: no snowball appears.
- [ ] Click title bar buttons, Dock icons and menu items under falling snow, on every display: every click lands.
- [ ] Play Mode on: rolling, pushing, carrying and stacking snowballs works on the display the cursor is on.

## Snowfall and system

- [ ] Light Snow, Gentle Snowfall and Snowstorm look different and ease into each other.
- [ ] Light and dark mode: snow is visible over white and dark windows.
- [ ] Reduce Motion on: sparser, nearly windless snow, and the cursor no longer stirs it.
- [ ] Low Power Mode on: snow thins and the frame rate halves within a few seconds.
- [ ] Sleep and wake, lock and unlock: snow resumes without a burst.

## Festive cursor (menu → Cursor Effect)

### Santa sleigh

- [ ] Choose Santa Sleigh: a small sleigh with two reindeer appears beside the cursor. The system cursor itself is unchanged.
- [ ] Move the cursor: the sleigh follows a moment later and settles without bouncing.
- [ ] Move faster: the reindeer gallop faster. Move slowly: they trot.
- [ ] Sweep up and down: the sleigh noses up into climbs and down into dives, slightly.
- [ ] Reverse direction: the team wheels round and ends up behind the cursor on the other side. Tiny wiggles do not flip it.
- [ ] Stop: within a second it hovers gently and the reindeer shift their feet.
- [ ] The lead reindeer's nose never covers the pointer's tip.
- [ ] Companion Size → Small, Medium, Large: the size changes at once.
- [ ] Start typing: the sleigh fades back; it returns when you stop.
- [ ] Press ⌘0 with the menu open, or choose Normal Cursor: it disappears immediately.

### Clicks and focus, with the sleigh on

- [ ] Click buttons and links in a browser window directly under the sleigh.
- [ ] Open a menu bar menu and choose an item; open a context menu.
- [ ] Click into a text field, select text by dragging, double-click a word.
- [ ] Drag a window by its title bar; drag a file in Finder.
- [ ] ⌘Tab between apps: the front app changes normally and the overlay never takes focus.
- [ ] Hover over links and text: the system cursor still changes shape (hand, I-beam) as usual.

### Trail

- [ ] Behind the sleigh: a thin mix of gold sparkles, tiny snowflakes and the odd soft glow.
- [ ] Particles drift with the wind (try Snowstorm) and are gone in about a second.
- [ ] A slow cursor leaves almost nothing; a fast sweep leaves a light trail, never a thick ribbon.
- [ ] Snowflake Trail and Golden Sparkle Trail: the same, from the cursor itself, with no companion.

### Santa hat

- [ ] A small hat sits just above the pointer, swings back as you move and settles when you stop.

### Multiple displays

- [ ] Move the cursor to another display: the companion arrives there and is positioned correctly beside the cursor.
- [ ] Displays with different scaling: the companion is the same physical size relative to the cursor on both.

### Sleigh bells (menu → Sleigh Bells; off by default)

To hear every sound on its own first: `.build/release/WinterIsComing --audition 0.5`
plays the eight bell variants in turn, then the shimmer swelling and fading, and quits.

- [ ] With Sleigh Bells off (the default) there is no sound at all, whatever the cursor does.
- [ ] Turn it on with a cursor effect active. Move slowly: a very faint shimmer, no distinct bells.
- [ ] Sweep quickly: an occasional single bell over the shimmer. Bells differ slightly and come at irregular intervals.
- [ ] Scrub the cursor back and forth for 20 seconds: bells thin out; they never pile up or get loud.
- [ ] Stop moving: the shimmer fades over about half a second, with no click.
- [ ] Bells move left and right with the cursor's position.
- [ ] Volume slider: louder and quieter; at the top it is still quiet next to music.
- [ ] Mute (⌘M with the menu open): silence immediately. Unmute restores it.
- [ ] Choose Normal Cursor, or turn Sleigh Bells off, mid-sound: silence immediately.
- [ ] Play music in another app: it is not ducked, paused or rerouted.
- [ ] Typing produces no bells, even if the cursor is nudged.
- [ ] Reduce Motion on: no companion, no trail, no bells.
