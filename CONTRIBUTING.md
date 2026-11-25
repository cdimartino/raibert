# Contributing to Rai*bert

Thanks for helping ship the pipeline. Open an issue before a large behavior or infrastructure change so the design can be agreed first.

## Development

Use Ruby 4.0.7 through mise, install the locked gems, then run `script/test`. Browser changes also require `npm ci --prefix web` and Playwright Chromium. Run one group with `script/test unit` (seconds), `script/test simulation` (full campaigns, about two minutes) or `script/test e2e` (Playwright; later arguments such as `--project=chromium` go to Playwright). Keep gameplay rules deterministic in `lib/game_state.rb`; rendering and input belong in `game.rb` or the narrow browser bridge.

Rebuild the committed Wasm runtime with `script/build_web` after changing Ruby game code, `lib/`, `config/controls.json`, or `web/`. HTML, CSS, and JavaScript-only changes do not require that build.

## Pull requests

- Add focused tests for behavior changes and keep both coverage gates at 100% executable lines.
- Run the complete suite and avoid committing local caches, credentials, or fake production scores.
- Update player-facing documentation for control, balance, architecture, or deployment changes.
- Keep commits reviewable and describe risk, verification, and screenshots in the PR.

By contributing, you agree that your work is licensed under the project’s MIT License.

### Where CI runs

The repository variable `RAIBERT_CI_POOL` controls both automatic CI jobs (`push` to `main` and pull requests). With the variable unset, jobs run on GitHub-hosted Ubuntu. Set it to `magneto` only after unattended runner registration and remote administration have been verified. Each job then requests its own disposable Linux x64 guest: one for unit tests and the campaign simulation, one to build the web runtime, and one per Playwright shard. Runner selection does not fall back automatically when a host is offline.

To roll back, delete `RAIBERT_CI_POOL` or set it to `hosted`, then trigger a **new workflow run**. Changing the variable does not move a job that is already queued. For manual diagnostics, dispatch `CI` on a non-main branch with `magneto` checked; leaving it unchecked always selects hosted Ubuntu. A manual dispatch on `main` always uses hosted Ubuntu and can trigger production deployment, so use a non-main ref for diagnostics.
