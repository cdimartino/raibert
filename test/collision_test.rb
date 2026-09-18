# frozen_string_literal: true

require_relative "../lib/game_state"

def assert(condition, message)
  raise "Collision check failed: #{message}" unless condition
end

def place_player(game, position)
  game.instance_variable_set(:@player, position)
end

def make_vulnerable(game)
  game.instance_variable_set(:@invulnerable_until, 0)
end

class ZeroRandom
  def rand(limit = nil)
    limit ? 0 : 0.0
  end
end

falling = GameState.new(random: ZeroRandom.new, now: 0)
place_player(falling, [1, 0])
falling.instance_variable_set(:@pickup, {
  kind: :life, row: 0, column: 0, from: [-1, -0.5], moved_at: 0, next_at: 100
})
event = falling.tick(100)
assert(event.nil? && falling.pickup, "a falling powerup is not collected before reaching the player")
event = falling.tick(350)
assert(event == :life, "a powerup landing on the player reports its effect")
assert(falling.lives == 4 && falling.pickup.nil?, "a powerup landing on the player is collected")

GameState::PICKUP_KINDS.each do |kind|
  crossing_pickup = GameState.new(now: 0)
  place_player(crossing_pickup, [2, 0])
  crossing_pickup.enemies << { kind: :bug, row: 4, column: 0, next_at: 2_000 } if kind == :gc
  crossing_pickup.instance_variable_set(:@pickup, {
    kind: kind, row: 2, column: 0, from: [1, 0], moved_at: 100, next_at: 2_000
  })
  event = crossing_pickup.move(:up_right, 300, started_at: 150)
  assert(event == kind, "moving through an in-flight #{kind} powerup reports its effect")
  assert(crossing_pickup.pickup.nil?, "moving through an in-flight #{kind} powerup collects it")
  assert(crossing_pickup.freeze_until == 4_300, "the debugger powerup freezes enemies") if kind == :debugger
  assert(crossing_pickup.enemies.empty?, "the gc powerup clears enemies") if kind == :gc
end

expired_path = GameState.new(now: 0)
expired_path.instance_variable_set(:@pickup, {
  kind: :debugger, row: 2, column: 0, from: [1, 0], moved_at: 100, next_at: 2_000
})
event = expired_path.move(:down_left, 800, started_at: 400)
assert(event == :hop && expired_path.pickup, "an expired movement path does not cause a stale collision")

departing_paths = GameState.new(now: 0)
make_vulnerable(departing_paths)
departing_paths.enemies << {
  kind: :exception, row: 0, column: 0, from: [1, 0], spawned_at: 0, moved_at: 300, next_at: 2_000
}
event = departing_paths.move(:down_right, 300, started_at: 0)
assert(event == :hop, "paths sharing a tile at different times do not collide")
assert(departing_paths.lives == 3, "a temporally separated path does not cost a life")

falling_enemy = GameState.new(random: ZeroRandom.new, now: 0)
place_player(falling_enemy, [1, 0])
make_vulnerable(falling_enemy)
falling_enemy.enemies << { kind: :bug, row: 0, column: 0, next_at: 100 }
assert(falling_enemy.tick(100).nil?, "an enemy does not hit before reaching the player")
assert(falling_enemy.tick(350) == :hit, "an enemy landing on the player reports a hit")
assert(falling_enemy.lives == 2, "an enemy landing on the player costs a life")

%i[bug exception regression].each do |kind|
  crossing_enemy = GameState.new(now: 0)
  place_player(crossing_enemy, [2, 0])
  make_vulnerable(crossing_enemy)
  crossing_enemy.enemies << {
    kind: kind, row: 2, column: 0, from: [1, 0], moved_at: 100, next_at: 2_000
  }
  assert(crossing_enemy.move(:up_right, 300, started_at: 150) == :hit, "moving through an in-flight #{kind} is a hit")
  assert(crossing_enemy.lives == 2, "crossing an in-flight #{kind} costs a life")
end

spawning_enemy = GameState.new(random: ZeroRandom.new, now: 0)
spawning_enemy.instance_variable_set(:@level, 2)
spawning_enemy.instance_variable_set(:@stage, 2)
spawning_enemy.instance_variable_set(:@last_spawn_at, 0)
place_player(spawning_enemy, [GameState::ROWS - 1, 0])
make_vulnerable(spawning_enemy)
spawning_enemy.define_singleton_method(:enemy_kind) { :exception }
assert(spawning_enemy.tick(4_000) == :hit, "an enemy spawning on the player is detected immediately")
assert(spawning_enemy.lives == 2, "a spawn collision costs a life")

frozen_overlap = GameState.new(now: 0)
make_vulnerable(frozen_overlap)
frozen_overlap.instance_variable_set(:@freeze_until, 1_000)
frozen_overlap.enemies << { kind: :bug, row: 0, column: 0, next_at: 2_000 }
assert(frozen_overlap.tick(100) == :hit, "a frozen enemy overlapping the player is still hazardous")

life_then_hit = GameState.new(random: ZeroRandom.new, now: 0)
place_player(life_then_hit, [1, 0])
make_vulnerable(life_then_hit)
life_then_hit.instance_variable_set(:@pickup, {
  kind: :life, row: 1, column: 0, from: [0, 0], moved_at: 100, next_at: 2_000
})
life_then_hit.enemies << { kind: :bug, row: 1, column: 0, next_at: 2_000 }
assert(life_then_hit.tick(350) == :hit, "a hit is reported even when a life powerup offsets the lost life")
assert(life_then_hit.lives == 3, "life gain and collision loss are both applied in the same tick")

rescue_pickup = GameState.new(now: 0)
place_player(rescue_pickup, [4, 0])
rescue_pickup.instance_variable_set(:@pickup, { kind: :life, row: 0, column: 0 })
assert(rescue_pickup.move(:up_left, 100) == :rescue, "the rescue platform remains the movement result")
assert(rescue_pickup.lives == 4 && rescue_pickup.pickup.nil?, "returning by rescue collects a summit powerup")

puts "Rai*bert collision check passed"
