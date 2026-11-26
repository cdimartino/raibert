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

### Where CI runs

Only the repository owner is authorized to start or re-run CI. Owner-authored pull requests from branches in this repository run on GitHub-hosted Ubuntu. Keep **Require approval for all external contributors** enabled: fork pull requests can propose different workflow YAML, so job conditions in this repository do not enforce that boundary. Do not approve external runs or add writers without a change to the authorization policy.

For owner pushes to `main`, `RAIBERT_CI_POOL=magneto` selects disposable Linux x64 guests for both jobs. If guests are offline there is no automatic fallback. Delete the variable or set it to `hosted` for subsequent runs; queued jobs do not move. Manual `CI` runs are hosted unless the owner explicitly checks `magneto` on a non-main ref.

Production deploys on hosted Ubuntu after successful owner push CI for the default-branch SHA at the time of the completion event. Neither pull requests nor manual **CI** runs deploy. The owner may explicitly dispatch **Deploy raibert.lol** on `main` to deploy the SHA selected by that dispatch.
