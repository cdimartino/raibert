# frozen_string_literal: true

require "json"

def assert(condition, message)
  raise "Web shim check failed: #{message}" unless condition
end

class BrowserBridgeStub
  attr_reader :rendered, :frame_callback, :key_callback, :action_callback, :resize_callback, :world_score_callback, :keys, :failure
  attr_accessor :preferences, :milliseconds
  attr_reader :saved_preferences, :published

  def call(method, *arguments)
    case method
    when :milliseconds then @milliseconds || 123
    when :imageSize then "384,416"
    when :textWidth then arguments.last.to_s.length * 10
    when :render then @rendered = JSON.parse(arguments.fetch(0))
    when :preferences then JSON.generate(@preferences || {})
    when :savePreferences then @saved_preferences = JSON.parse(arguments.first)
    when :publishGameState then @published = JSON.parse(arguments.first)
    when :start
      @frame_callback, @key_callback, @action_callback, @resize_callback, @world_score_callback = arguments.take(5)
      @keys = JSON.parse(arguments.fetch(5))
    when :fail then @failure = arguments.fetch(0)
    end
  end
end

bridge = BrowserBridgeStub.new
js_global = Object.new
js_global.define_singleton_method(:[]) { |key| key == :RaiBertWeb ? bridge : nil }
Object.const_set(:JS, Module.new)
JS.define_singleton_method(:global) { js_global }
$LOADED_FEATURES << "js.rb"

require_relative "../web/gosu"

color = Gosu::Color.new(0x7f_123456)
assert([color.alpha, color.red, color.green, color.blue] == [0x7f, 0x12, 0x34, 0x56], "ARGB colors are decoded")
assert(Gosu.milliseconds == 123, "browser timing is used")
assert(Gosu::KB_RETURN == "return", "configured key constants are available")
assert(Gosu.const_defined?(:KB_SPACE) && Gosu.const_get(:KB_SPACE) == "space", "supported browser key constants are available")
assert(!Gosu.const_defined?(:KB_RETRUN), "misspelled browser key constants are rejected")

tiles = Gosu::Image.load_tiles("/app/assets/rai/spritesheet.png", 192, 208)
assert(tiles.length == 4 && tiles.first.width == 192 && tiles.first.height == 208, "sprite sheets are tiled")
Gosu.draw_rect(1, 2, 3, 4, color, 2)
tiles.last.draw(5, 6, 1, 0.5, 0.5)
Gosu.flush
assert(bridge.rendered.map { |command| command.fetch("kind") } == %w[rect image], "draw commands reach the browser")
assert(bridge.rendered.map { |command| command.fetch("order") } == [0, 1], "draw order is stable before z sorting")
assert(File.exist?("/app/assets/sounds/hop.wav"), "browser-served assets are visible to optional asset checks")
assert(!File.exist?("/app/not-an-asset"), "unrelated virtual paths are not invented")

class BrowserWindowCheck < Gosu::Window
  attr_reader :keys, :actions

  def initialize
    @controls = { custom: [Gosu.const_get(:KB_SPACE)] }
    @keys = []
    @actions = []
    super(100, 100)
  end

  def update; end
  def draw; end
  def button_down(key) = @keys << key
  def press(action) = @actions << action
end

window = BrowserWindowCheck.new.show
assert(bridge.keys == Gosu::KEY_NAMES, "all supported browser keys are registered for runtime rebinding")
bridge.key_callback.call("space")
bridge.action_callback.call("up_left")
assert(window.keys == ["space"] && window.actions == [:up_left], "key and semantic action callbacks are routed")

class BrokenBrowserWindow < BrowserWindowCheck
  def button_down(_key) = raise("bad input")
end

BrokenBrowserWindow.new.show
bridge.key_callback.call("space")
assert(bridge.failure.include?("bad input"), "input callback failures reach the browser error UI")

$LOAD_PATH.unshift(File.expand_path("../web", __dir__))
require_relative "../game"
game = RaiBertWindow.new
assert(
  RaiBertWindow::MOVE_ACTIONS.to_h { |action| [action, game.instance_variable_get(:@control_names).fetch(action)] } ==
    { up_left: ["q"], up_right: ["e"], down_left: ["a"], down_right: ["d"] },
  "movement defaults use one Q/E/A/D key per direction"
)
game.press(:up_right)
game.press(:up_left)
assert(game.instance_variable_get(:@selection) == 1, "touch up-right selects the character on the selection screen")
assert(game.instance_variable_get(:@difficulty_selection) == 0, "touch up-left selects the difficulty on the selection screen")
game.press(:options)
assert(game.instance_variable_get(:@screen) == :options, "options open before starting")
game.press(:confirm)
game.button_down("r")
assert(game.instance_variable_get(:@control_names).fetch(:up_left) == ["r"], "options replace a movement binding")
game.press(:down_right)
game.press(:confirm)
game.button_down("r")
assert(game.instance_variable_get(:@control_names).fetch(:up_right) == ["e"], "duplicate movement binding is rejected")
game.press(:pause)
game.press(:pause)
game.press(:confirm)
game.press(:pause)
game.press(:options)
assert(game.instance_variable_get(:@screen) == :options, "options open while paused")
game.press(:pause)
assert(game.instance_variable_get(:@screen) == :game && game.instance_variable_get(:@paused), "leaving options returns to paused game")
begin
  game.press(:not_a_control)
  raise "invalid semantic action was accepted"
rescue ArgumentError => error
  assert(error.message.include?("Unknown control action"), "semantic actions remain validated")
end

puts "Rai*bert web shim check passed"

controls = RaiBertWindow.new
controls.press(:options)
controls.press(:confirm)
controls.button_down("s")
assert(controls.instance_variable_get(:@controls)[:up_left] == ["s"], "movement can reuse selection-only S")
controls.press(:select_down)
controls.press(:confirm)
%w[s m l return].each do |key|
  controls.button_down(key)
  assert(controls.instance_variable_get(:@rebinding_action) == :up_right, "active conflict #{key} is rejected")
end
controls.button_down("r")
assert(bridge.saved_preferences.dig("controls", "up_right") == ["r"], "custom controls are persisted")
bridge.preferences = bridge.saved_preferences
restored = RaiBertWindow.new
assert(restored.instance_variable_get(:@controls)[:up_left] == ["s"], "cross-context binding survives reload")
restored.button_down("s")
assert(restored.instance_variable_get(:@difficulty_selection) == 2, "S still changes selection difficulty")
restored.press(:options)
4.times { restored.press(:select_down) }
restored.press(:confirm)
assert(bridge.saved_preferences["controls"] == RaiBertWindow::DIAMOND_CONTROLS.transform_keys(&:to_s), "diamond preset has explicit Q/R/S/D directions")
bridge.preferences = bridge.saved_preferences
diamond = RaiBertWindow.new
diamond.press(:confirm)
moves = []
diamond.define_singleton_method(:begin_hop) { |direction| moves << direction }
%w[q r s d].each { |key| diamond.button_down(key) }
assert(moves == RaiBertWindow::MOVE_ACTIONS, "all four preset directions route correctly")
diamond.press(:pause)
assert(diamond.instance_variable_get(:@paused), "pause remains available with the preset")
diamond.press(:options)
5.times { diamond.press(:select_down) }
diamond.press(:confirm)
assert(bridge.saved_preferences.dig("controls", "up_right") == ["e"] && bridge.saved_preferences.dig("controls", "down_left") == ["a"], "reset restores default controls")

bridge.preferences = { "controls" => { "up_left" => ["m"], "up_right" => ["q"] } }
invalid = RaiBertWindow.new
assert(invalid.instance_variable_get(:@controls)[:up_left] == ["q"], "invalid stored conflicts restore a safe default mapping")
bridge.preferences = {}
selection = RaiBertWindow.new
[[1000, 760], [760, 1645]].each do |width, height|
  selection.resize(width, height)
  Gosu.commands.clear
  selection.draw
  labels = Gosu.commands.select { |command| command[:kind] == "text" }.map { |command| command[:text] }
  %w[Choose\ character: Change\ difficulty: Start\ game:].each do |action|
    assert(labels.any? { |label| label.start_with?(action) }, "selection explicitly names #{action}")
  end
  assert(labels.none? { |label| label.include?("BOOT") || label.include?("//") }, "essential selection guidance uses plain actions")
end

# Every board grows to the limiting viewport edge, including off-board rescue ships.
responsive = RaiBertWindow.new
responsive.press(:confirm)
[[480, 1039], [480, 640], [1039, 480], [760, 1645], [760, 1013], [1645, 760], [1000, 760]].each do |width, height|
  responsive.resize(width, height)
  (1..GameState::LEVEL_COUNT).each do |level|
    state = GameState.new(start_level: level)
    responsive.instance_variable_set(:@game, state)
    positions = state.board.tiles + state.board.ribbons.flat_map { |ribbon| ribbon.fetch(:path) } + state.board.rescues.keys.map { |origin, direction| state.board.fall_target(origin, direction) }
    centers = positions.map { |position| responsive.send(:tile_center, position) }
    tile = responsive.send(:tile_width)
    xs, ys = centers.transpose
    portrait = height > width
    available_width = width - (portrait ? 28 : 80)
    available_height = height - (portrait ? 158 : 118) - (portrait ? 28 : 86)
    occupied_width = xs.max - xs.min + tile * 1.15
    occupied_height = ys.max - ys.min + tile * 1.5
    assert(occupied_width <= available_width + 0.001 && occupied_height <= available_height + 0.001,
           "stage #{level} fits #{width}x#{height} with rescue space")
    assert((occupied_width - available_width).abs < 0.001 || (occupied_height - available_height).abs < 0.001,
           "stage #{level} fills the limiting viewport edge at #{width}x#{height}")
    assert(ys.min - tile >= (portrait ? 158 : 118) - 0.001 && ys.max + tile * 0.5 <= height - (portrait ? 28 : 86) + 0.001,
           "stage #{level} reserves vertical room for sprites and tile depth")
    assert((xs.min + xs.max - width).abs < 0.001, "stage #{level} stays centered after resize")
  end
end

# The real window reports life loss and sound on the same frame as idle contact.
bridge.milliseconds = 0
contact = RaiBertWindow.new
contact.press(:confirm)
contact.press(:down_left)
bridge.milliseconds = 420
contact.update
state = contact.instance_variable_get(:@game)
state.instance_variable_set(:@invulnerable_until, 0)
row, column = state.player
state.enemies << { kind: :bug, row: row, column: column, from: [row - 1, column], spawned_at: 500, moved_at: 500, next_at: 2_000 }
sounds = []
contact.define_singleton_method(:play) { |event| sounds << event }
bridge.milliseconds = 749
contact.update
assert(state.lives == 3 && sounds.empty?, "no hit feedback before enemy arrival")
bridge.milliseconds = 750
contact.update
assert(state.lives == 2 && sounds == [:hit] && contact.instance_variable_get(:@respawn)[:started_at] == 750, "hit sound, life loss, and death animation start together")
assert(bridge.published["lives"] == 2, "browser sees the life loss on that frame")
puts "Feedback window and control checks passed"
