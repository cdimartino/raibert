# Feedback release validation — October 7, 2026

This release addresses issues #5–#9 and #12 after the analytics prerequisite in #10.

## Game-over and replay (#5)

A 2.8-second animated ending (1.2 seconds with reduced motion) shows the outcome and counts up the final score before automatically opening the leaderboard. Players can continue immediately. Distinct four-note loss/victory tones honor mute. The leaderboard retains a visible loss/victory result, final score, and stage. Retry game resets the actual Ruby game; Refresh only fetches scores. An in-flight submission temporarily disables replay/close, with a 15-second timeout so a stalled request cannot trap the player. Offline failures preserve the run for retry, skip, or replay. Restarting through either the leaderboard or menu clears the old submission.

Playwright exposes the Ruby VM only through an intercepted test response. The production client contains no test-evaluation API. Tests complete a real Ruby fall or the last stage's final tile, wait for the actual game outcome, and exercise keyboard/touch replay. A fresh default run has three lives, stage 1, and **100 points**: reset clears the old score, then the starting tile awards 100. The issue brief's proposed zero-score assertion was inconsistent with the existing scoring rules.

## Contact investigation (#6)

A deterministic reproduction established a stale-motion defect:

| Case | Before | After |
| --- | --- | --- |
| Player finishes a hop at 420 ms; enemy starts at 500 ms and arrives at 750 ms | No hit at 750 ms; three lives remain | No hit at 749 ms; one life lost at 750 ms |
| Pickup arrives after the same completed hop | Retained player interval can miss the pickup | Pickup collected on arrival |
| Enemy reaches the tile the player already left | Historical motion must not be replayed | No false hit |

During an idle tick, the retained interval now describes stationary occupancy from the last collision check to the current time. Actual movement still supplies the hop interval to the existing crossing checks. Window-level regression checks confirm that life loss, hit sound, death animation, and published browser lives agree on the arrival frame.

The deliberate 420 ms hop and landing-time enemy scheduling remain unchanged. Existing tests still cover in-flight crossings, time-separated paths, pickups, invulnerability, and distinct-layer connections. The spawn-pressure fixture now explicitly grants invulnerability so it measures enemy scheduling independently of the fixed contact behavior.

This establishes a source-level defect consistent with the report, not the reporter's exact browser/device scenario. No reporter hardware or trace was available. Browser frame samples are recorded by the Playwright rescue-cue test; the patch does not attribute the original report to Wasm or low FPS.

## Rescue guidance (#7)

Every active ship now has a gold launch mark, a directional arrow, and a binding/swipe label. Layout sizing includes ship destinations so ships fit below the HUD. Guidance and markers disappear when rescues are consumed.

The exact origin/direction restriction is retained. Regression cases cover the eligible up-angle and ineligible down-angle approaches for stages 2–3 left and stage 4 right. Stage 1 left and stages 15/18 right retain their existing down-angle launches. Tests enumerate alternate approaches to all 40 ships across the 20 layouts and preserve one-use behavior, return to start, and the 250-point rescue bonus.

## Selection and keyboard controls (#8, #9)

Selection names Choose character, Change difficulty, and Start game separately, with binding-derived keyboard labels and explicit touch gestures. Controls show the four directions spatially and offer an optional Q/R-above-S/D preset, plus reset to defaults. This evaluates the suggested Q/S/D/R keys as an opt-in arrangement; the original defaults remain available.

Conflict checks use explicit selection/options/gameplay contexts. Movement can reuse selection-only keys but cannot duplicate another movement binding or an active global action. The browser leaderboard shortcut remains reserved. Presets and custom mappings persist; invalid stored conflicts fall back to safe defaults. The canvas accessibility label and in-game guidance reflect active bindings.

## Speed and skill scoring (#12)

Stage clears add up to 2,000 × stage for speed, decaying in 10-point increments over 1,200 ms per required tile increment, plus 500 × stage for no lives lost during that stage. Only completed stages award these bonuses. Base rewards remain intact. The HUD previews the potential award; stage-clear and terminal results show earned amounts. Pauses use the frozen game clock, so they do not consume bonus time. Retry resets accumulated bonuses.

Deterministic cases compare identical completion at different times, expired/maximum bounds, clean versus damaged runs, once-only awards, stage reset and game reset. Browser coverage checks pause behavior. The existing regression enemy appears from stage 3 and removes one tile increment; its new UNDO −1 label makes that role visible. Tests verify undoing a cleared tile, restoring it, and the zero lower bound.

## Verification

- GameState: 100% executable-line coverage (329/329).
- Board layouts: 100% (167/167).
- Leaderboard domain: 100% (27/27).
- Collector, browser-shim/window, HTTP integration, packaging, audio, touch input, and analytics-client checks pass.
- Full deterministic campaigns pass on easy, normal, hard, and default-life easy. All visit stages 1–20.
- All 30 browser scenarios pass. Browser coverage is Desktop Chrome and Pixel 7 Chromium emulation. Safari, Firefox, and physical mobile devices were not tested.
- The committed Wasm runtime is rebuilt from the changed Ruby source.
- Production leaderboard writes are mocked in tests; no synthetic production scores are submitted.

Headless frame samples (60 frames, video recording and two workers) had a 33.3 ms median in both profiles; desktop p95/max were 33.4/50.1 ms, mobile p95/max were 50/66.7 ms. These measurements describe the test runner, not physical-device performance.

## Visual evidence

- [Game over and replay, mobile](game-over-mobile.png)
- [Selection instructions, desktop](selection-desktop.png)
- [Movement preset, desktop](controls-desktop.png)
- [Down-angle rescue guidance, stage 15 mobile](rescue-stage-15-mobile.png)
- [Animated ending, mobile (during score count-up)](ending-mobile.png)
