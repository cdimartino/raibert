# Contributing to Rai*bert

Thanks for helping ship the pipeline. Open an issue before a large behavior or infrastructure change so the design can be agreed first.

## Development

Use Ruby 4.0.7 through mise, install the locked gems, then run `script/test`. Browser changes also require `npm ci --prefix web` and Playwright Chromium. Keep gameplay rules deterministic in `lib/game_state.rb`; rendering and input belong in `game.rb` or the narrow browser bridge.

Rebuild the committed Wasm runtime with `script/build_web` after changing Ruby game code, `lib/`, `config/controls.json`, or `web/`. HTML, CSS, and JavaScript-only changes do not require that build.

## Pull requests

- Add focused tests for behavior changes and keep both coverage gates at 100% executable lines.
- Run the complete suite and avoid committing local caches, credentials, or fake production scores.
- Update player-facing documentation for control, balance, architecture, or deployment changes.
- Keep commits reviewable and describe risk, verification, and screenshots in the PR.

By contributing, you agree that your work is licensed under the project’s MIT License.
