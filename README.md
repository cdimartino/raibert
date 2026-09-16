# Rai*bert

Ship the pipeline, one hop at a time.

Rai*bert is a Q*bert-inspired Ruby arcade game. Turn every failing build tile into a passing build while dodging bugs, exceptions, and regressions across a 20-level campaign.

![Rai*bert stage completion](docs/screenshots/stage-clear.png)

![Rai*bert mid-game action](docs/screenshots/mid-game-action.png)

## Features

- 20 stages, from Build to Ship, with rising tile, enemy, and timing pressure.
- Easy, Normal, and Hard modes with different lives, enemy density, enemy speed, spawn rate, and powerup timing.
- Three enemy behaviors: descending bugs, chasing exceptions, and regressions that undo tile progress.
- Five falling, limited-time powerups: enemy freeze, enemy clear, extra life, shield, and tile repair.
- Two selectable Rai characters with directional hops, themed idle loops, and death/respawn animation.
- Layered stage presentation with illustrated worlds, atmospheric bands, data lanes, particles, palettes, and a unique looping chiptune track for every level.
- One-use rescue platforms on both edges of each stage.
- No checkpoints: by default, Game Over restarts at Level 1, while clearing Level 20 reaches the victory screen.

## Gameplay

Land on every tile enough times to complete the stage. Level 1 needs one landing per tile, Levels 2–4 need two, and Levels 5–20 need three. Tile progress changes only after Rai lands.

Enemy pressure increases throughout the campaign. Bugs descend the pyramid, exceptions chase Rai, and regressions remove progress from tiles they touch. Clearing a stage restores one lost life up to the configured starting amount.

### Powerups

| Drop | Effect |
| --- | --- |
| `DBG` | Freezes enemies for four seconds. |
| `GC` | Clears every active enemy. |
| `1UP` | Adds one life, up to one above the configured starting amount. |
| `SH` | Grants five seconds of collision protection. |
| `FX` | Repairs three unfinished tiles by one step. |

Drops enter at the summit, fall one row at a time, and disappear after leaving the board. They fall faster on later levels and harder difficulties, so collecting one means changing route before time runs out.

## Requirements

The included setup targets macOS and uses:

- [Homebrew](https://brew.sh/)
- [mise](https://mise.jdx.dev/)
- Ruby 4.0.7
- SDL2
- Xcode Command Line Tools or another working macOS C toolchain

Gosu and the remaining Ruby dependencies are declared in `Gemfile` and locked in `Gemfile.lock`.

## Install and run on macOS

```sh
brew install mise sdl2
mise install
mise exec -- bundle install
mise exec -- bundle exec ruby game.rb
```

If macOS asks for the Xcode license while compiling a native dependency, review and accept it in Terminal before retrying `bundle install`.

After the first setup, launch with:

```sh
mise exec -- bundle exec ruby game.rb
```

## Command-line options

Launching without flags is unchanged: choose a character and difficulty in the game, then begin at Level 1 with that difficulty's normal life count.

Use these optional overrides for testing and demos:

```sh
# Start at Level 12
mise exec -- bundle exec ruby game.rb --level 12

# Start with six lives
mise exec -- bundle exec ruby game.rb --lives 6

# Combine overrides
mise exec -- bundle exec ruby game.rb --level 12 --lives 6 --difficulty hard

# Autoplay the same configured run
mise exec -- bundle exec ruby game.rb --demo --level 12 --lives 6 --difficulty hard
```

`--level` accepts `1`–`20`, `--lives` accepts `1`–`99`, and `--difficulty` accepts `easy`, `normal`, or `hard`. Invalid values are rejected instead of being silently adjusted. Run `mise exec -- bundle exec ruby game.rb --help` for the full usage summary.

The overrides are launch settings, not checkpoints: after Game Over, the game restarts at the configured start level with the configured starting lives. Demo mode makes normal directional moves through the real tick, enemy, collision, tile, and powerup rules; it does not mutate progress directly and stops on the visible victory screen.

## Controls

| Action | Default keys |
| --- | --- |
| Hop up-left | `Q` or `W` |
| Hop up-right | `E` or `D` |
| Hop down-left | `Z` or `A` |
| Hop down-right | `C` or `S` |
| Choose character | Left / Right |
| Choose difficulty | Up / Down |
| Start or restart | Enter |
| Pause or return to character select | Escape |
| Mute music and effects | `M` |

## Configuration

Bindings live in `config/controls.json`. Each action accepts one or more Gosu key names; the game validates every action and key at startup.

```json
{
  "up_left": ["q", "w"],
  "up_right": ["e", "d"],
  "down_left": ["z", "a"],
  "down_right": ["c", "s"]
}
```

Difficulty and character are normally selected in the game; `--difficulty` can preset the difficulty for a test or demo run. No save file or checkpoint configuration is used.

## Test

After installing dependencies, run the rules smoke test:

```sh
mise exec -- bundle check
mise exec -- bundle exec ruby test/smoke_test.rb
```

The smoke test covers campaign progression, CLI validation, difficulty scaling, enemies, touchdown timing, rescues, powerup effects and expiry, life limits, Game Over reset, and Level 20 victory.

## Project layout

```text
game.rb                 Gosu window, input, rendering, animation, and audio
lib/game_state.rb       Deterministic game rules and balance
lib/demo_window.rb      Real-input autoplay driver used by --demo
config/controls.json    Customizable key bindings
assets/art/             Stage, enemy, rescue, and powerup artwork
assets/music/           One soundtrack per level
assets/rai*/            Character sprite sheets
test/smoke_test.rb      Runnable gameplay rules check
```

## Credits and licensing

Rai character artwork is derived from the supplied `rai-pets-v2.zip`. Stage, enemy, rescue, and powerup art was generated for this game; generation prompts are preserved in `assets/art/PROMPTS.md`. [Gosu](https://www.libgosu.org/) is MIT-licensed.

Rai*bert is released under the [MIT License](LICENSE).
