# frozen_string_literal: true

require "coverage"
require "json"
require "fileutils"

Coverage.start(lines: true)

load File.expand_path("collision_test.rb", __dir__)
load File.expand_path("smoke_test.rb", __dir__)
load File.expand_path("leaderboard_test.rb", __dir__)
load File.expand_path("board_layouts_test.rb", __dir__)

def coverage_assert(condition, message)
  raise "Unit coverage check failed: #{message}" unless condition
end

class FixedRandom
  def initialize(value)
    @value = value
  end

  def rand(limit = nil)
    limit ? (@value * limit).floor : @value
  end
end

# Cover every enemy selection and movement policy explicitly. The broad smoke
# suites exercise these probabilistically; these examples make the unit gate
# deterministic and document the boundary values.
level_two = GameState.new(random: FixedRandom.new(0.69))
level_two.instance_variable_set(:@level, 2)
coverage_assert(level_two.send(:enemy_kind) == :bug, "level two selects bugs below 0.7")
level_two.instance_variable_set(:@random, FixedRandom.new(0.7))
coverage_assert(level_two.send(:enemy_kind) == :exception, "level two selects exceptions at 0.7")

late_enemy = GameState.new(random: FixedRandom.new(0.1))
late_enemy.instance_variable_set(:@level, 3)
coverage_assert(late_enemy.send(:enemy_kind) == :bug, "later levels still select bugs")
late_enemy.instance_variable_set(:@random, FixedRandom.new(0.8))
coverage_assert(late_enemy.send(:enemy_kind) == :exception, "later levels select exceptions")
late_enemy.instance_variable_set(:@random, FixedRandom.new(0.99))
coverage_assert(late_enemy.send(:enemy_kind) == :regression, "later levels select regressions")

movement = GameState.new(random: FixedRandom.new(0.0), now: 0)
movement.instance_variable_set(:@player, [0, 0])
chaser = { kind: :exception, row: 2, column: 0, next_at: 0 }
movement.enemies << chaser
movement.send(:step_enemy, chaser, 100)
coverage_assert(chaser.values_at(:row, :column) == [1, 0], "exceptions chase the player")

regression = { kind: :regression, row: 0, column: 0, next_at: 0 }
movement.enemies << regression
movement.tiles[[1, 0]] = 1
movement.send(:step_enemy, regression, 100)
coverage_assert(movement.tiles[[1, 0]].zero?, "regressions undo completed work")

departure_tile = movement.board.tiles.find do |position|
  %i[down_left down_right].none? { |direction| movement.connection_for(position, direction) }
end
departing = { kind: :bug, row: departure_tile[0], column: departure_tile[1], next_at: 0 }
movement.enemies << departing
movement.send(:step_enemy, departing, 100)
coverage_assert(!movement.enemies.include?(departing), "descending enemies leave below the board")

tick_collision = GameState.new(random: FixedRandom.new(0.0), now: 0)
tick_collision.instance_variable_set(:@player, [1, 0])
tick_collision.instance_variable_set(:@invulnerable_until, 0)
tick_collision.enemies << { kind: :bug, row: 2, column: 0, next_at: 100 }
tick_collision.define_singleton_method(:step_enemy) do |enemy, _now|
  enemy[:row], enemy[:column] = @player
end
coverage_assert(tick_collision.tick(100) == :hit, "enemy movement can collide during a tick")

finished = GameState.new(start_level: GameState::LEVEL_COUNT)
finished.send(:advance_stage, 1_000)
coverage_assert(finished.status == :victory, "advancing past the final level stays at victory")

coverage_assert(!movement.neighbors.empty? && !movement.valid?([99, 99]), "public graph helpers expose board topology")
coverage_assert(movement.send(:descending_step, { row: movement.board.start[0], column: movement.board.start[1] }),
                "descending step compatibility uses the board graph")
coverage_assert(movement.send(:chasing_step, chaser), "chasing step compatibility uses the board graph")
coverage_assert(movement.send(:graph_distance, movement.board.start, [99, 99]).infinite?,
                "unreachable graph positions report infinite distance")

ribbon_game = GameState.new(start_level: 11)
ribbon = ribbon_game.board.ribbons.first
connection = ribbon_game.connection_for(ribbon.fetch(:from), ribbon.fetch(:direction))
motion = ribbon_game.send(:motion_for, connection, 0, 100)
coverage_assert(ribbon_game.send(:position_during, motion, 50).length == 2,
                "ribbon motion interpolates through its path")
coverage_assert(ribbon_game.send(:interpolate_path, connection.path, 1.0) == connection.path.last.map(&:to_f),
                "ribbon interpolation reaches its endpoint")
coverage_assert(ribbon_game.send(:interpolate_path, [[0, 0], [0, 0], [1, 1]], 0.0) == [0.0, 0.0],
                "zero-length ribbon segments are safe")
coverage_assert(ribbon_game.send(:interpolate_path, [[0, 0], [0, 1], [0, 3]], 0.75) == [0.0, 2.25],
                "ribbon interpolation advances across multiple segments")

layered_a = { from: [0, 0], to: [0, 2], started_at: 0, ended_at: 100,
              connection_id: "a", layer: 1, path: [[0, 0], [0, 1], [0, 2]] }
layered_b = { from: [2, 0], to: [2, 2], started_at: 0, ended_at: 100,
              connection_id: "b", layer: 2, path: [[2, 0], [2, 1], [2, 2]] }
coverage_assert(!ribbon_game.send(:motions_collide?, layered_a, layered_b),
                "separate layered ribbons do not collide")
layered_b[:from] = [0, 0]
layered_b[:path] = [[0, 0], [2, 1], [2, 2]]
coverage_assert(ribbon_game.send(:motions_collide?, layered_a, layered_b),
                "layered ribbons still collide at shared endpoints")
same_layer = layered_b.merge(connection_id: "a", layer: 1)
coverage_assert(ribbon_game.send(:motions_collide?, layered_a, same_layer),
                "shared ribbon paths use piecewise collision checks")

result = Coverage.result
targets = [
  File.expand_path("../lib/game_state.rb", __dir__),
  File.expand_path("../lib/board_layouts.rb", __dir__),
  File.expand_path("../leaderboard/leaderboard.rb", __dir__)
]
reports = targets.map do |target|
  lines = result.fetch(target).fetch(:lines)
  executable = lines.each_index.select { |index| !lines[index].nil? }
  missed = executable.select { |index| lines[index].zero? }
  percentage = ((executable.length - missed.length) * 100.0 / executable.length).round(2)
  { file: target, covered_lines: executable.length - missed.length, executable_lines: executable.length,
    percentage: percentage, missed_lines: missed.map { |index| index + 1 } }
end

FileUtils.mkdir_p(File.expand_path("../coverage", __dir__))
File.write(
  File.expand_path("../coverage/unit.json", __dir__),
  JSON.pretty_generate(
    files: reports,
    percentage: (reports.sum { |report| report[:covered_lines] } * 100.0 / reports.sum { |report| report[:executable_lines] }).round(2)
  ) + "\n"
)

reports.each do |report|
  coverage_assert(report[:missed_lines].empty?, "#{File.basename(report[:file])} line coverage is #{report[:percentage]}% (missed #{report[:missed_lines].join(', ')})")
  puts "#{File.basename(report[:file], '.rb')} unit coverage: 100% (#{report[:executable_lines]}/#{report[:executable_lines]} lines)"
end
