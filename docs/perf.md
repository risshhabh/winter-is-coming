# Performance notes

Machine: MacBook with Apple M4, built-in 2560 × 1664 display, macOS 26.6.

## Where the time goes (stage 2, 2026-11-16)

Measured by the app itself; run `.build/release/WinterIsComing --smoke 10` to repeat it.

| System | Cost | Notes |
|---|---|---|
| Window poll (`CGWindowListCopyWindowInfo`) | about 1.7 ms each | The bottleneck. One system call, roughly 40 times the cost of a simulation step |
| Simulation step (wind, flakes, powder), live | about 0.04 ms | 60 per second |
| Simulation step, headless, Snowstorm on two displays | about 0.08 ms | 385 flakes plus 1,355 powder particles |
| Sprite sync per frame | about 0.06 ms | |
| Applying an unchanged window list | none | Skipped: 17,970 of 18,000 updates in a 5-minute headless run |

CPU in `top` during the live run was about 4-8% of one core. That run was at 30 fps with thinned
snow, because the machine was in a constrained power state, so it is not comparable with the
earlier 60 fps figures.

## What was done about it

- **Polling rate follows activity**: every frame while a mouse button is down, 30 Hz for a second
  after any window change, 10 Hz at rest. The live run made about 12 polls a second instead of 30.
- **Unchanged window lists are skipped** before any per-window work, and occlusion is only
  recomputed when geometry or order changes.
- **Wind grid** is refreshed 20 times a second, not 60.
- **Pile rendering** uploads one row of pixels per changed pile; unchanged piles cost nothing.
- **Budgets**: flakes per display scale with its area up to 2,600; powder is capped at 2,400.
- **Adaptive quality**: if simulation plus sprite sync exceeds 4 ms a frame, density is reduced
  (down to 35%) and restored slowly afterwards. In Low Power Mode or under thermal pressure, density
  is capped at 60% and rendering drops to 30 fps.

## Not yet measured

GPU time, WindowServer's share of compositing, energy impact, memory over hours, and anything on a
real second display. Polling still runs on the main thread; moving it off is the next step if 1.7 ms
spikes matter.

## Earlier: stage 1

Original single file about 12% of one core, stage 1 about 8-10%, from a few `top` samples at 60 fps
on the same desktop. Rough, not a benchmark.
