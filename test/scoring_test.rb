# frozen_string_literal: true
require_relative '../lib/game_state'

def scoring_assert(condition, message)
  raise "Scoring check failed: #{message}" unless condition
end

def scored_stage(elapsed, lose_life: false)
  game = GameState.new(now: 1_000)
  game.send(:lose_life, 1_100) if lose_life
  game.tiles.each_key { |tile| game.tiles[tile] = game.target }
  game.tiles[game.player] = game.target - 1
  game.send(:touch_tile, game.player, 1_000 + elapsed)
  game
end
fast = scored_stage(5_000)
slow = scored_stage(20_000)
expired = scored_stage(1_000_000)
scoring_assert(fast.score > slow.score && slow.score > expired.score, 'same stage rewards faster completion')
scoring_assert(expired.last_stage_bonus[:speed].zero?, 'expired speed bonus cannot become negative')
scoring_assert(fast.last_stage_bonus[:clean] == 500, 'clean stage awards a skill bonus')
hit = scored_stage(5_000, lose_life: true)
scoring_assert(hit.score == fast.score - 500, 'losing a life forfeits only the clean bonus')
hit.instance_variable_set(:@lives, 4)
scoring_assert(hit.clean_bonus.zero?, 'recovering lives cannot restore clean-stage eligibility')
scoring_assert(fast.score_bonuses == fast.last_stage_bonus, 'run totals include awarded bonuses')
score = fast.score
fast.send(:touch_tile, fast.player, 99_000)
scoring_assert(fast.score == score, 'completed stage cannot award twice')
fast.tick(8_000)
scoring_assert(fast.stage == 2 && fast.clean_bonus == 1_000, 'next stage restores clean eligibility')
scoring_assert(fast.speed_bonus(8_000) == 4_000, 'new stage starts a fresh speed clock')
fast.reset(20_000)
scoring_assert(fast.score == 100 && fast.score_bonuses.values.all?(&:zero?), 'retry resets bonuses and score')
scoring_assert(fast.speed_bonus(19_000) == 2_000, 'clock cannot exceed the stage bonus cap')

# The existing purple regression enemy removes one increment, including from
# fully cleared tiles. The player must restore it before completing the board.
game = GameState.new(start_level: 3, random: Random.new(3))
origin = game.board.start
regression = { kind: :regression, row: origin[0], column: origin[1] }
# Choose one real descending edge deterministically for this unit fixture.
connection = [:down_left, :down_right].filter_map { |direction| game.connection_for(origin, direction) }.first
game.define_singleton_method(:descending_connection) { |_enemy, _now| connection }
destination = connection.to
game.tiles[destination] = game.target
game.send(:step_enemy, regression, 1_000)
scoring_assert(game.tiles[destination] == game.target - 1, 'regression undoes a cleared tile')
game.send(:touch_tile, destination, 1_300)
scoring_assert(game.tiles[destination] == game.target, 'player restores undone progress')
game.tiles[destination] = 0
game.send(:step_enemy, regression, 2_000)
scoring_assert(game.tiles[destination].zero?, 'regression never lowers progress below zero')
puts 'Speed, clean-stage scoring, retry and regression-enemy checks passed'

[1, GameState::LEVEL_COUNT].each do |level|
  final_hit = GameState.new(start_level: level)
  direction, destination = final_hit.neighbors.first
  final_hit.tiles.each_key { |tile| final_hit.tiles[tile] = final_hit.target }
  final_hit.tiles[destination] = final_hit.target - 1
  final_hit.instance_variable_set(:@invulnerable_until, 0)
  final_hit.enemies << { kind: :bug, row: destination[0], column: destination[1], next_at: 99_999 }
  scoring_assert(final_hit.move(direction, 2_000) == :hit && final_hit.lives == 2, 'final tile can coincide with a collision')
  scoring_assert(final_hit.last_stage_bonus[:clean].zero? && final_hit.score_bonuses[:clean].zero?, 'final-tile collision forfeits clean bonus, including victory')
  scoring_assert(final_hit.score == 200 + 1_000 * level + final_hit.last_stage_bonus[:speed], 'only base rewards and earned speed bonus remain')
end
puts 'Simultaneous stage completion and collision scoring passed'
