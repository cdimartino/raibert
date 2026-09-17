# frozen_string_literal: true

require "json"

def assert(condition, message)
  raise "Web shim check failed: #{message}" unless condition
end

class BrowserBridgeStub
  attr_reader :rendered, :frame_callback, :key_callback, :action_callback, :keys, :failure

  def call(method, *arguments)
    case method
    when :milliseconds then 123
    when :imageSize then "384,416"
    when :textWidth then arguments.last.to_s.length * 10
    when :render then @rendered = JSON.parse(arguments.fetch(0))
    when :start
      @frame_callback, @key_callback, @action_callback = arguments.take(3)
      @keys = JSON.parse(arguments.fetch(3))
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
