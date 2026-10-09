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
place_player(spawning_enemy, spawning_enemy.board.farthest_tiles.first)
make_vulnerable(spawning_enemy)
spawning_enemy.define_singleton_method(:enemy_kind) { :exception }
assert(spawning_enemy.tick(4_000) == :hit, "an enemy spawning on the player is detected immediately")
assert(spawning_enemy.lives == 2, "a spawn collision costs a life")

frozen_overlap = GameState.new(now: 0)
make_vulnerable(frozen_overlap)
frozen_overlap.instance_variable_set(:@freeze_until, 1_000)
frozen_overlap.enemies << { kind: :bug, row: frozen_overlap.player[0], column: frozen_overlap.player[1], next_at: 2_000 }
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
rescue_edge, = rescue_pickup.board.rescues.find { |_edge, side| side == :left }
rescue_position, rescue_direction = rescue_edge
place_player(rescue_pickup, rescue_position)
rescue_pickup.instance_variable_set(:@pickup, { kind: :life, row: rescue_pickup.board.start[0], column: rescue_pickup.board.start[1] })
assert(rescue_pickup.move(rescue_direction, 100) == :rescue, "the rescue platform remains the movement result")
assert(rescue_pickup.lives == 4 && rescue_pickup.pickup.nil?, "returning by rescue collects a summit powerup")

puts "Rai*bert collision check passed"

# A real completed hop must not hide an enemy arriving during subsequent idle time.
%i[bug exception regression].each do |kind|
  idle = GameState.new(now: 0)
  idle.move(:down_left, 420, started_at: 0)
  make_vulnerable(idle)
  row, column = idle.player
  idle.enemies << { kind: kind, row: row, column: column, from: [row - 1, column], spawned_at: 500, moved_at: 500, next_at: 2_000 }
  assert(idle.tick(749).nil?, "#{kind} does not hit before arriving after a completed hop")
  assert(idle.tick(750) == :hit && idle.lives == 2, "#{kind} arrival hits an idle player with completed motion")
  assert(idle.tick(751).nil? && idle.lives == 2, "contact removes only one life")
end

idle_pickup = GameState.new(now: 0)
idle_pickup.move(:down_left, 420, started_at: 0)
row, column = idle_pickup.player
idle_pickup.instance_variable_set(:@pickup, { kind: :life, row: row, column: column, from: [row - 1, column], spawned_at: 500, moved_at: 500, next_at: 2_000 })
assert(idle_pickup.tick(749).nil?, "idle pickup waits for arrival")
assert(idle_pickup.tick(750) == :life && idle_pickup.lives == 4, "idle pickup is collected after completed hop")

old_path = GameState.new(now: 0)
origin = old_path.player.dup
old_path.move(:down_left, 420, started_at: 0)
make_vulnerable(old_path)
old_path.enemies << { kind: :bug, row: origin[0], column: origin[1], spawned_at: 500, next_at: 2_000 }
assert(old_path.tick(750).nil? && old_path.lives == 3, "later contact with the departed tile cannot replay old motion")

protected_idle = GameState.new(now: 0)
protected_idle.move(:down_left, 420, started_at: 0)
protected_idle.enemies << { kind: :bug, row: protected_idle.player[0], column: protected_idle.player[1], spawned_at: 500, next_at: 2_000 }
assert(protected_idle.tick(750).nil? && protected_idle.lives == 3, "idle contact respects spawn invulnerability")
assert(protected_idle.tick(1_200) == :hit, "persistent contact becomes hazardous when invulnerability ends")

[[2, :left, [3, 1], :up_left, [1, 0], :down_left],
 [3, :left, [3, 1], :up_left, [1, 0], :down_left],
 [4, :right, [3, 4], :up_right, [1, 3], :down_right],
 [1, :left, nil, :down_left, nil, nil],
 [15, :right, nil, :down_right, nil, nil],
 [18, :right, nil, :down_right, nil, nil]].each do |level, side, origin, direction, alternate, wrong_direction|
  rescue_game = GameState.new(now: 0, start_level: level)
  edge = rescue_game.board.rescues.key(side)
  origin ||= edge.first
  assert(edge == [origin, direction], "level #{level} preserves the catalog rescue direction")
  initial_score = rescue_game.score
  place_player(rescue_game, origin)
  assert(rescue_game.move(direction, 2_000) == :rescue, "level #{level} marked launch rescues")
  assert(rescue_game.player == rescue_game.board.start && rescue_game.score == initial_score + 250 && !rescue_game.rescues[side], "rescue returns to start, scores once, and disappears")
  place_player(rescue_game, origin)
  assert(rescue_game.move(direction, 4_000) == :fall, "a used ship cannot rescue twice")
  next unless alternate

  wrong = GameState.new(now: 0, start_level: level)
  place_player(wrong, alternate)
  assert(wrong.move(wrong_direction, 2_000) == :fall && wrong.lives == 2, "level #{level} alternate approach still falls")
  assert(wrong.rescues[side], "ineligible approach does not consume rescue")
end

# Spawns and movement reserve both ends of an in-flight object's path.
occupied = GameState.new(random: ZeroRandom.new, now: 0)
place_player(occupied, [3, 1])
start_row, start_column = occupied.board.start
occupied.instance_variable_set(:@pickup, { kind: :life, row: start_row, column: start_column, next_at: 10_000 })
occupied.send(:spawn_enemy, 9_000)
assert(occupied.enemies.empty?, "an enemy cannot spawn on a powerup")
occupied.instance_variable_set(:@pickup, nil)
next_row, next_column = occupied.board.neighbors(occupied.board.start).first.last
occupied.enemies << { kind: :bug, row: next_row, column: next_column, from: occupied.board.start, moved_at: 8_900, next_at: 10_000 }
occupied.send(:spawn_pickup, 9_000)
assert(occupied.pickup.nil?, "a powerup cannot spawn on an enemy's in-flight origin")
occupied.send(:spawn_pickup, 9_151)
assert(occupied.pickup, "the vacated tile becomes available after the enemy lands")

%i[bug regression exception].each do |kind|
  avoiding = GameState.new(random: ZeroRandom.new, now: 0)
  origin = avoiding.board.start
  directions = kind == :exception ? GameState::DIRECTIONS.keys : %i[down_left down_right]
  destinations = directions.filter_map { |direction| avoiding.board.connection(origin, direction)&.to }
  enemy = { kind: kind, row: origin[0], column: origin[1], next_at: 0 }
  avoiding.enemies << enemy
  target = destinations.first
  avoiding.instance_variable_set(:@pickup, { kind: :life, row: target[0], column: target[1] })
  place_player(avoiding, target)
  avoiding.send(:step_enemy, enemy, 100)
  assert(enemy.values_at(:row, :column) != target, "#{kind} chooses a route away from the powerup")

  waiting = GameState.new(random: ZeroRandom.new, now: 0)
  waiting.enemies << (blocked = { kind: kind, row: origin[0], column: origin[1], next_at: 0 })
  destinations.each { |row, column| waiting.enemies << { kind: :bug, row: row, column: column, next_at: 10_000 } }
  waiting.send(:step_enemy, blocked, 100)
  assert(waiting.enemies.include?(blocked) && blocked.values_at(:row, :column) == origin,
         "#{kind} waits when all neighboring destinations are occupied")
  assert(blocked[:next_at] > 100, "a blocked #{kind} schedules its next attempt")
end

blocked_pickup = GameState.new(random: ZeroRandom.new, now: 0)
origin = blocked_pickup.board.start
blocked_pickup.instance_variable_set(:@pickup, { kind: :life, row: origin[0], column: origin[1], next_at: 0 })
%i[down_left down_right].each do |direction|
  destination = blocked_pickup.board.connection(origin, direction)&.to
  next unless destination

  row, column = destination
  blocked_pickup.enemies << { kind: :bug, row: row, column: column, next_at: 10_000 }
end
blocked_pickup.send(:step_pickup, 100)
assert(blocked_pickup.pickup && blocked_pickup.pickup.values_at(:row, :column) == origin,
       "a blocked powerup waits instead of overlapping an enemy or disappearing")
blocked_pickup.enemies.clear
blocked_pickup.send(:step_pickup, blocked_pickup.pickup[:next_at])
assert(blocked_pickup.pickup.values_at(:row, :column) != origin, "a powerup resumes once a route is free")
puts "Exclusive object occupancy checks passed"
