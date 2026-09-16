# frozen_string_literal: true

require_relative "../game"

def assert(condition, message)
  raise "Smoke check failed: #{message}" unless condition
end

def clear_stage(game, now)
  game.tiles.each_key { |tile| game.tiles[tile] = game.target }
  game.tiles[[1, 0]] = game.target - 1
  game.move(:down_left, now)
  expected = game.level == GameState::LEVEL_COUNT ? :victory : :stage_clear
  assert(game.status == expected, "last fixed tile completes level #{game.level}")
end

def place_pickup(game, kind, position = game.player)
  game.instance_variable_set(:@pickup, { kind: kind, row: position[0], column: position[1] })
end

game = GameState.new(random: Random.new(1), now: 0)
assert(RaiBertWindow::THEMES.length == 20 && RaiBertWindow::LEVEL_NAMES.length == 20, "every level has a visual and name")
RaiBertWindow::THEMES.each do |theme|
  assert(File.exist?(File.join(__dir__, "../assets/music/#{theme[:music]}.wav")), "#{theme[:music]} soundtrack exists")
end
assert(game.player == [0, 0], "player starts at the summit")
assert(game.difficulty == :normal && game.lives == 3, "normal is the default difficulty")
assert(game.target_for(:down_right) == [1, 1], "diagonal movement maps to the pyramid")

window = RaiBertWindow.allocate
landing_game = GameState.new(random: Random.new(1), now: 0)
window.instance_variable_set(:@screen, :game)
window.instance_variable_set(:@game, landing_game)
window.instance_variable_set(:@paused, false)
window.instance_variable_set(:@last_direction, :down_right)
window.instance_variable_set(:@flash_until, 0)
window.instance_variable_set(:@music_level, landing_game.level)
window.instance_variable_set(:@test_time, 3_000)
window.define_singleton_method(:game_time) { @test_time }
window.define_singleton_method(:play) { |_event| }
place_pickup(landing_game, :life, [1, 1])
window.send(:begin_hop, :down_right)
assert(landing_game.player == [0, 0] && landing_game.tiles[[1, 1]].zero?, "hop does not land at takeoff")
window.instance_variable_set(:@test_time, 3_000 + RaiBertWindow::JUMP_TIME - 1)
window.update
assert(landing_game.tiles[[1, 1]].zero? && landing_game.lives == 3, "tile and pickup stay unchanged in flight")
window.instance_variable_set(:@test_time, 3_000 + RaiBertWindow::JUMP_TIME)
window.update
assert(landing_game.player == [1, 1] && landing_game.tiles[[1, 1]] == 1, "touchdown changes the tile")
assert(landing_game.lives == 4 && landing_game.pickup.nil?, "touchdown collects an extra life")
assert(landing_game.enemies.length == 1, "enemy scheduler advances at touchdown")

easy = GameState.new(random: Random.new(1), now: 0, difficulty: :easy)
hard = GameState.new(random: Random.new(1), now: 0, difficulty: :hard)
assert(easy.lives == 4 && hard.lives == 3, "difficulty changes starting lives")
{ easy: 5, normal: 6, hard: 7 }.each do |difficulty, cap|
  late = GameState.new(random: Random.new(1), now: 0, difficulty: difficulty)
  late.instance_variable_set(:@level, GameState::LEVEL_COUNT)
  assert(late.enemy_cap == cap, "#{difficulty} late-game enemy cap stays playable")
end
normal_interval = game.send(:pickup_interval)
assert(easy.send(:pickup_interval) > normal_interval && normal_interval > hard.send(:pickup_interval), "harder modes shorten pickup availability")
late_game = GameState.new(random: Random.new(1), now: 0)
late_game.instance_variable_set(:@level, GameState::LEVEL_COUNT)
assert(late_game.send(:pickup_interval) < normal_interval, "later levels shorten pickup availability")
normal_pressure = GameState.new(random: Random.new(1), now: 0)
hard_pressure = GameState.new(random: Random.new(1), now: 0, difficulty: :hard)
6.times do |index|
  normal_pressure.move(:down_right, 100 + index)
  hard_pressure.move(:down_right, 100 + index)
end
[3_200, 6_400, 9_600].each do |now|
  normal_pressure.tick(now)
  hard_pressure.tick(now)
end
assert(normal_pressure.enemies.length == 2 && hard_pressure.enemies.length == 3, "hard mode sustains an extra enemy")

falling = GameState.new(random: Random.new(1), now: 0)
falling.move(:down_left, 100)
falling.tick(8_000)
assert(falling.pickup && [falling.pickup[:row], falling.pickup[:column]] == [0, 0], "timed pickup starts at the summit")
6.times { falling.send(:step_pickup, falling.pickup[:next_at]) }
assert(falling.pickup[:row] == GameState::ROWS - 1, "pickup falls to the bottom row")
falling.send(:step_pickup, falling.pickup[:next_at])
assert(falling.pickup.nil?, "uncollected pickup expires after leaving the board")

bonus = GameState.new(random: Random.new(1), now: 0)
2.times do |index|
  place_pickup(bonus, :life)
  bonus.send(:collect_pickup, 2_000 + index)
end
assert(bonus.lives == 4, "extra life is capped at one above the starting allowance")
clear_stage(bonus, 3_000)
bonus.tick(4_500)
assert(bonus.lives == 4, "level transition preserves a collected bonus life")

shielded = GameState.new(random: Random.new(1), now: 0)
place_pickup(shielded, :shield)
assert(shielded.send(:collect_pickup, 2_000) == :shield && shielded.shield_until == 7_000, "shield lasts five seconds")
shielded.enemies << { kind: :bug, row: 0, column: 0, next_at: 9_000 }
assert(!shielded.send(:collide, 6_999) && shielded.lives == 3, "shield blocks collisions while active")
assert(shielded.send(:collide, 7_000) && shielded.lives == 2, "shield expires on schedule")

patched = GameState.new(random: Random.new(1), now: 0)
progress = patched.tiles.values.sum
place_pickup(patched, :patch)
assert(patched.send(:collect_pickup, 2_000) == :patch, "patch pickup is collected")
assert(patched.tiles.values.sum == progress + 3, "patch repairs three unfinished tiles")

game.move(:down_right, 2_000)
assert(game.player == [1, 1], "valid hop moves the player")

game.move(:down_right, 2_100)
game.move(:down_right, 2_200)
game.move(:down_right, 2_300)
assert(game.move(:up_right, 2_400) == :rescue, "edge platform rescues the player")
assert(game.player == [0, 0], "rescue returns to the summit")

3.times { |index| game.move(:up_left, 4_000 + index * 2_000) }
assert(game.status == :game_over, "three falls end the run")

game.reset(10_000)
game.move(:up_left, 10_500)
assert(game.lives == 2, "a fall costs a life")
clear_stage(game, 11_000)
game.tick(12_500)
assert(game.stage == 2 && game.level == 2, "stage advances after the clear banner")
assert(game.lives == 3, "clearing a level repairs one life up to the difficulty cap")

(3..GameState::LEVEL_COUNT).each_with_index do |level, index|
  now = 14_000 + index * 3_000
  clear_stage(game, now)
  game.tick(now + 1_500)
  assert(game.level == level, "campaign advances to level #{level}")
end
assert(GameState::LEVEL_TARGETS.length == 20 && game.target == 3, "campaign defines twenty escalating levels")
clear_stage(game, 70_000)
game.tick(80_000)
assert(game.status == :victory && game.stage == 20, "level twenty ends in victory without a stage twenty-one")
assert(game.move(:down_left, 81_000) == :ignored, "victory locks further movement")

begin
  GameState.new(difficulty: :impossible)
  raise "Smoke check failed: invalid difficulty was accepted"
rescue ArgumentError
  # expected
end

puts "Rai*bert smoke check passed"
