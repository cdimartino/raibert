# frozen_string_literal: true

require "json"

def assert(condition, message)
  raise "Gameplay collision check failed: #{message}" unless condition
end

class HeadlessBridge
  attr_accessor :milliseconds

  def initialize
    @milliseconds = 0
  end

  def call(method, *arguments)
    case method
    when :milliseconds then @milliseconds
    when :imageSize
      path = arguments.fetch(0)
      return "1536,2288" if path.end_with?("spritesheet.png")
      return "1536,1024" if path.end_with?("objects.png")

      "512,512"
    when :textWidth then arguments.last.to_s.length * 10
    end
  end
end

bridge = HeadlessBridge.new
js_global = Object.new
js_global.define_singleton_method(:[]) { |key| key == :RaiBertWeb ? bridge : nil }
Object.const_set(:JS, Module.new)
JS.define_singleton_method(:global) { js_global }
$LOADED_FEATURES << "js.rb"
$LOAD_PATH.unshift(File.expand_path("../web", __dir__))

require_relative "../lib/demo_window"

def validate_game(game, difficulty, frame)
  assert(GameState::DIFFICULTIES.key?(game.difficulty), "known difficulty at frame #{frame}")
  assert(game.difficulty == difficulty, "difficulty remains stable at frame #{frame}")
  assert(game.level.between?(1, GameState::LEVEL_COUNT), "level remains in range at frame #{frame}")
  assert(game.stage.between?(1, GameState::LEVEL_COUNT), "stage remains in range at frame #{frame}")
  assert(game.valid?(game.player), "player remains on a valid tile at frame #{frame}")
  assert(game.tiles.length == GameState::ROWS * (GameState::ROWS + 1) / 2, "tile count remains stable at frame #{frame}")
  assert(game.tiles.all? { |position, value| game.valid?(position) && value.between?(0, game.target) },
         "tile progress remains valid at frame #{frame}")
  assert(game.enemies.length <= game.enemy_cap, "enemy count remains capped at frame #{frame}")
  assert(game.enemies.all? { |enemy| game.valid?(enemy.values_at(:row, :column)) },
         "enemies remain on valid tiles at frame #{frame}")
  assert(!game.pickup || game.valid?(game.pickup.values_at(:row, :column)),
         "powerup remains on a valid tile at frame #{frame}")
  assert(game.lives.between?(0, 100), "lives remain in range at frame #{frame}")
end

def run_campaign(bridge, difficulty, seed, starting_lives: 99, max_frames: 250_000)
  bridge.milliseconds = 0
  window = DemoWindow.new(difficulty: difficulty)
  game = GameState.new(random: Random.new(seed), now: 0, difficulty: difficulty, starting_lives: starting_lives)
  window.instance_variable_set(:@game, game)
  window.send(:reset_demo_tracking)

  frames = 0
  deaths = 0
  previous_lives = game.lives
  levels = { game.level => true }
  until game.status == :victory
    frames += 1
    assert(frames <= max_frames, "#{difficulty} seed #{seed} campaign completes")
    bridge.milliseconds += 34
    window.update
    validate_game(game, difficulty, frames)
    deaths += previous_lives - game.lives if game.lives < previous_lives
    previous_lives = game.lives
    levels[game.level] = true
  end

  assert(levels.keys.sort == (1..GameState::LEVEL_COUNT).to_a,
         "#{difficulty} seed #{seed} visits every campaign level")
  { difficulty: difficulty, seed: seed, frames: frames, deaths: deaths }
end

results = GameState::DIFFICULTIES.keys.map.with_index do |difficulty, index|
  run_campaign(bridge, difficulty, 10_000 + index)
end
default_easy = run_campaign(bridge, :easy, 20_000, starting_lives: 4, max_frames: 150_000)

results.each do |result|
  puts "#{result[:difficulty]} campaign: #{result[:frames]} frames, #{result[:deaths]} deaths"
end
puts "default-life easy campaign: #{default_easy[:frames]} frames, #{default_easy[:deaths]} deaths"
puts "Rai*bert full gameplay collision check passed"
