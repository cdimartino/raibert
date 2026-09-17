# frozen_string_literal: true

require "gosu"
require "json"
require "optparse"
require_relative "lib/game_state"

module RaiBertCLI
  module_function

  def parse(argv)
    options = { start_level: 1, starting_lives: nil, difficulty: nil, demo: false }
    OptionParser.new do |parser|
      parser.banner = "Usage: ruby game.rb [options]"
      parser.on("--level N", Integer, "Start at level 1-#{GameState::LEVEL_COUNT}") do |value|
        raise OptionParser::InvalidArgument, "level must be between 1 and #{GameState::LEVEL_COUNT}" unless value.between?(1, GameState::LEVEL_COUNT)

        options[:start_level] = value
      end
      parser.on("--lives N", Integer, "Start with 1-99 lives") do |value|
        raise OptionParser::InvalidArgument, "lives must be between 1 and 99" unless value.between?(1, 99)

        options[:starting_lives] = value
      end
      parser.on("--difficulty MODE", "easy, normal, or hard") do |value|
        difficulty = value.to_sym
        raise OptionParser::InvalidArgument, "difficulty must be easy, normal, or hard" unless GameState::DIFFICULTIES.key?(difficulty)

        options[:difficulty] = difficulty
      end
      parser.on("--demo", "Autoplay the game") { options[:demo] = true }
      parser.on("-h", "--help", "Show this help") { options[:help] = parser.to_s }
    end.parse!(argv)
    options
  end
end

class RaiBertWindow < Gosu::Window
  WIDTH = 1_000
  HEIGHT = 760
  TILE_WIDTH = 90
  TILE_HEIGHT = 46
  ROW_STEP = 68
  PYRAMID_TOP = 160
  JUMP_TIME = 420
  DEATH_TIME = 650
  RESPAWN_TIME = 550

  THEMES = [
    { art: "build", music: "build", name: "EMERALD COMPILER GARDEN", accent: 0xff_55efbc, tile: 0xff_224f50, pass: 0xff_70f2be },
    { art: "test", music: "test", name: "AMETHYST OBSERVATORY", accent: 0xff_c5a0ff, tile: 0xff_393563, pass: 0xff_b996ff },
    { art: "deploy", music: "deploy", name: "AMBER DEPLOYMENT FOUNDRY", accent: 0xff_ffc477, tile: 0xff_694032, pass: 0xff_ffba65 },
    { art: "observe", music: "observe", name: "SAPPHIRE TELEMETRY OCEAN", accent: 0xff_5fd7ff, tile: 0xff_244869, pass: 0xff_72dcff },
    { art: "scale", music: "scale", name: "MAGENTA AUTOSCALING CITADEL", accent: 0xff_ff72cb, tile: 0xff_5d2c5f, pass: 0xff_ff8edb },
    { art: "build", music: "cache", name: "TURQUOISE CACHE CAVERNS", accent: 0xff_46f5d0, tile: 0xff_174d48, pass: 0xff_65ffdf },
    { art: "test", music: "queue", name: "INDIGO MESSAGE QUEUE", accent: 0xff_8b8cff, tile: 0xff_30325c, pass: 0xff_a7a8ff },
    { art: "deploy", music: "shard", name: "CRIMSON SHARD FORGE", accent: 0xff_ff5c72, tile: 0xff_5f2631, pass: 0xff_ff8291 },
    { art: "observe", music: "replicate", name: "AZURE REPLICA MATRIX", accent: 0xff_4ab8ff, tile: 0xff_214b68, pass: 0xff_72cbff },
    { art: "scale", music: "balance", name: "GOLDEN LOAD BALANCER", accent: 0xff_ffd45f, tile: 0xff_5b4930, pass: 0xff_ffdf80 },
    { art: "build", music: "trace", name: "CYAN TRACE LABYRINTH", accent: 0xff_61e8ff, tile: 0xff_1f4e59, pass: 0xff_83efff },
    { art: "build", music: "heal", name: "VERDANT SELF-HEALING GROVE", accent: 0xff_8cf580, tile: 0xff_2e5730, pass: 0xff_a8ff9d },
    { art: "test", music: "migrate", name: "VIOLET MIGRATION GATE", accent: 0xff_d58cff, tile: 0xff_4b3565, pass: 0xff_e0a8ff },
    { art: "deploy", music: "secure", name: "SCARLET SECURITY VAULT", accent: 0xff_ff5364, tile: 0xff_612a32, pass: 0xff_ff7b88 },
    { art: "observe", music: "optimize", name: "ELECTRIC OPTIMIZATION GRID", accent: 0xff_5f8cff, tile: 0xff_26385f, pass: 0xff_83a6ff },
    { art: "scale", music: "federate", name: "CELESTIAL FEDERATION NEXUS", accent: 0xff_f19cff, tile: 0xff_56385f, pass: 0xff_f7b9ff },
    { art: "deploy", music: "chaos", name: "NEON CHAOS ARENA", accent: 0xff_ff8a4c, tile: 0xff_5f3625, pass: 0xff_ffaa78 },
    { art: "observe", music: "recover", name: "AQUA RECOVERY ARCHIVE", accent: 0xff_57f0dd, tile: 0xff_235955, pass: 0xff_7dffed },
    { art: "test", music: "harden", name: "OBSIDIAN HARDENING CORE", accent: 0xff_c2d0e0, tile: 0xff_343b47, pass: 0xff_e0e8f2 },
    { art: "scale", music: "ship", name: "RAINBOW SHIPPING SINGULARITY", accent: 0xff_ffffff, tile: 0xff_5c3567, pass: 0xff_ffd36e }
  ].freeze
  LEVEL_NAMES = %w[
    BUILD TEST DEPLOY OBSERVE SCALE CACHE QUEUE SHARD REPLICATE BALANCE
    TRACE HEAL MIGRATE SECURE OPTIMIZE FEDERATE CHAOS RECOVER HARDEN SHIP
  ].freeze
  HOP_ROWS = { up_left: 2, down_left: 2, up_right: 1, down_right: 1 }.freeze
  IDLE_ROWS = [0, 8, 7, 6].freeze
  ROW_FRAMES = { 0 => 7, 1 => 8, 2 => 8, 4 => 5, 5 => 8, 6 => 6, 7 => 6, 8 => 6 }.freeze
  DIFFICULTY_KEYS = GameState::DIFFICULTIES.keys.freeze

  COLORS = {
    background: Gosu::Color.new(0xff_07100d),
    panel: Gosu::Color.new(0xee_101a17),
    green: Gosu::Color.new(0xff_42f59e),
    dim_green: Gosu::Color.new(0xff_173e2e),
    ruby: Gosu::Color.new(0xff_e32656),
    amber: Gosu::Color.new(0xff_ffbd2e),
    purple: Gosu::Color.new(0xff_b97aff),
    cyan: Gosu::Color.new(0xff_62d9ff),
    white: Gosu::Color.new(0xff_f5fff9),
    muted: Gosu::Color.new(0xff_7e9a8c),
    shadow: Gosu::Color.new(0xaa_000000)
  }.freeze
  POWERUP_STYLES = {
    life: ["1UP", 0xff_55ef8a],
    shield: ["SH", 0xff_62d9ff],
    patch: ["FX", 0xff_ffbd2e]
  }.freeze

  CHARACTERS = [
    { id: :rai, name: "RAI", subtitle: "ruby familiar", path: "assets/rai/spritesheet.png" },
    { id: :voxel, name: "RAI VOXEL", subtitle: "block runner", path: "assets/rai_voxel/spritesheet.png" }
  ].freeze

  CONTROL_ACTIONS = %i[
    up_left up_right down_left down_right select_left select_right select_up select_down confirm options pause mute
  ].freeze
  MOVE_ACTIONS = %i[up_left up_right down_left down_right].freeze
  MOVE_LABELS = {
    up_left: "UP-LEFT", up_right: "UP-RIGHT", down_left: "DOWN-LEFT", down_right: "DOWN-RIGHT"
  }.freeze
  KEY_ALIASES = { "enter" => "return", "esc" => "escape" }.freeze

  def initialize(start_level: 1, starting_lives: nil, difficulty: nil)
    super(WIDTH, HEIGHT, fullscreen: false)
    self.caption = "Rai*bert // ship it"
    @font = Gosu::Font.new(20, name: "Menlo")
    @small_font = Gosu::Font.new(14, name: "Menlo")
    @title_font = Gosu::Font.new(52, name: "Menlo")
    @sprites = CHARACTERS.to_h do |character|
      path = File.join(__dir__, character[:path])
      [character[:id], Gosu::Image.load_tiles(path, 192, 208, tileable: false)]
    end
    sound_path = File.join(__dir__, "assets/blip.wav")
    @sound = Gosu::Sample.new(sound_path) if File.exist?(sound_path)
    @backgrounds = THEMES.map { |theme| Gosu::Image.new(File.join(__dir__, "assets/art/#{theme[:art]}.png")) }
    @songs = THEMES.map { |theme| Gosu::Song.new(File.join(__dir__, "assets/music/#{theme[:music]}.wav")) }
    @songs.each { |song| song.volume = 0.32 }
    atlas = Gosu::Image.load_tiles(File.join(__dir__, "assets/art/objects.png"), 512, 512)
    @objects = %i[bug exception regression debugger gc rescue].zip(atlas).to_h
    @powerups = POWERUP_STYLES.keys.to_h do |kind|
      path = File.join(__dir__, "assets/art/powerups/#{kind}.png")
      [kind, File.exist?(path) ? Gosu::Image.new(path) : nil]
    end
    load_controls
    @screen = :select
    @start_level = start_level
    @starting_lives = starting_lives
    @selection = 0
    @difficulty_selection = DIFFICULTY_KEYS.index(difficulty || :normal)
    @muted = false
    @paused = false
    @pause_started_at = nil
    @paused_duration = 0
    @hop = nil
    @respawn = nil
    @idle_started_at = 0
    @last_direction = :down_right
    @flash_until = 0
    @music_level = nil
    @options_selection = 0
    @rebinding_action = nil
    @options_message = nil
  end

  def needs_cursor?
    false
  end

  def update
    return unless @screen == :game

    now = game_time
    if @respawn
      return if now - @respawn[:started_at] < DEATH_TIME + RESPAWN_TIME

      @respawn = nil
      @idle_started_at = now
    end
    if @hop
      return if now - @hop[:started_at] < @hop[:duration]

      land_hop(now)
    end
    return if @paused || @respawn

    old_lives = @game.lives
    death_position = @game.player.dup
    @game.tick(now)
    play_level_music if @music_level != @game.level
    if @game.lives < old_lives
      @flash_until = now + 250
      start_respawn(death_position, now)
      play(:hit)
    end
  end

  def button_down(key)
    if @screen == :options
      options_input(key)
      return
    end

    if pressed?(:mute, key)
      @muted = !@muted
      sync_music
      return
    end

    @screen == :select ? select_input(key) : game_input(key)
  end

  def press(action)
    raise ArgumentError, "Unknown control action: #{action}" unless action.respond_to?(:to_sym)

    action = action.to_sym
    action = {
      up_left: :select_up,
      up_right: :select_right,
      down_left: :select_left,
      down_right: :select_down
    }.fetch(action, action) if [:select, :options].include?(@screen)
    raise ArgumentError, "Unknown control action: #{action}" unless CONTROL_ACTIONS.include?(action)

    button_down(@controls.fetch(action).first)
  end

  def draw
    draw_background
    case @screen
    when :select then draw_select
    when :options then draw_options
    else draw_game
    end
  end

  private

  def select_input(key)
    if pressed?(:select_left, key)
      @selection = (@selection - 1) % CHARACTERS.length
      play(:select)
    elsif pressed?(:select_right, key)
      @selection = (@selection + 1) % CHARACTERS.length
      play(:select)
    elsif pressed?(:select_up, key)
      @difficulty_selection = (@difficulty_selection - 1) % DIFFICULTY_KEYS.length
      play(:select)
    elsif pressed?(:select_down, key)
      @difficulty_selection = (@difficulty_selection + 1) % DIFFICULTY_KEYS.length
      play(:select)
    elsif pressed?(:confirm, key)
      start_game
    elsif pressed?(:options, key)
      open_options(:select)
    elsif pressed?(:pause, key)
      close
    end
  end

  def game_input(key)
    if @paused && pressed?(:options, key)
      open_options(:game)
      return
    end

    if pressed?(:pause, key)
      if [:game_over, :victory].include?(@game.status)
        @screen = :select
        stop_music
      else
        toggle_pause
        sync_music
      end
      return
    end

    if pressed?(:confirm, key) && [:game_over, :victory].include?(@game.status)
      reset_game_clock
      @game.reset(game_time)
      @hop = nil
      @respawn = nil
      @idle_started_at = game_time
      @flash_until = 0
      play_level_music
      play(:start)
      return
    end

    direction = GameState::DIRECTIONS.keys.find { |action| pressed?(action, key) }
    begin_hop(direction) if direction && !@paused && !@hop && !@respawn && @game.status == :playing
  end

  def open_options(return_screen)
    @options_return_screen = return_screen
    @options_selection = 0
    @rebinding_action = nil
    @options_message = nil
    @screen = :options
    sync_music
  end

  def options_input(key)
    if @rebinding_action
      if pressed?(:pause, key)
        @rebinding_action = nil
        @options_message = "CHANGE CANCELLED"
      else
        bind_movement_key(@rebinding_action, key)
      end
      return
    end

    if pressed?(:select_up, key) || pressed?(:select_left, key)
      @options_selection = (@options_selection - 1) % MOVE_ACTIONS.length
      play(:select)
    elsif pressed?(:select_down, key) || pressed?(:select_right, key)
      @options_selection = (@options_selection + 1) % MOVE_ACTIONS.length
      play(:select)
    elsif pressed?(:confirm, key)
      @rebinding_action = MOVE_ACTIONS.fetch(@options_selection)
      @options_message = "PRESS NEW KEY  //  ESC CANCELS"
    elsif pressed?(:pause, key) || pressed?(:options, key)
      @screen = @options_return_screen
      @rebinding_action = nil
      sync_music
    end
  end

  def bind_movement_key(action, key)
    name = key_name(key)
    unavailable = @controls.reject { |other, _keys| other == action }.values.flatten.include?(key)
    if name.nil? || unavailable
      @options_message = unavailable ? "KEY ALREADY IN USE" : "KEY NOT SUPPORTED"
      return
    end

    @control_names[action] = [name]
    @controls[action] = [key]
    @rebinding_action = nil
    @options_message = "#{MOVE_LABELS.fetch(action)} = #{name.upcase}"
    play(:select)
  end

  def start_game
    @character = CHARACTERS[@selection][:id]
    reset_game_clock
    @game = GameState.new(
      now: game_time,
      difficulty: DIFFICULTY_KEYS.fetch(@difficulty_selection),
      start_level: @start_level,
      starting_lives: @starting_lives
    )
    @screen = :game
    @hop = nil
    @respawn = nil
    @idle_started_at = game_time
    play_level_music
    play(:start)
  end

  def begin_hop(direction)
    now = game_time
    from = @game.player.dup
    target = @game.target_for(direction)
    rescue_side = GameState::RESCUES[[from, direction]]
    event = rescue_side && @game.rescues[rescue_side] ? :rescue : :hop
    @last_direction = direction
    @hop = {
      from: from,
      target: target,
      direction: direction,
      event: event,
      started_at: now,
      duration: event == :rescue ? 720 : JUMP_TIME
    }
    play(:hop)
  end

  def land_hop(now)
    hop = @hop
    event = @game.move(hop[:direction], now)
    @hop = nil
    if [:fall, :hit].include?(event)
      @flash_until = now + 250
      start_respawn(event == :fall ? hop[:from] : hop[:target], now)
    else
      @idle_started_at = now
    end
    play(event) unless event == :hop
  end

  def start_respawn(position, now)
    @respawn = { position: position, started_at: now }
  end

  def play(event)
    return if @muted || !@sound

    speed = {
      select: 1.1, start: 1.5, hop: 1.0, debugger: 1.8, gc: 0.65,
      life: 1.65, shield: 1.4, patch: 1.2, rescue: 1.35,
      stage_clear: 2.0, victory: 2.0, fall: 0.55, hit: 0.45
    }.fetch(event, 1.0)
    @sound.play(0.28, speed)
  end

  def play_level_music
    Gosu::Song.current_song&.stop
    @music_level = @game.level
    sync_music
  end

  def sync_music
    return unless @music_level

    song = @songs.fetch(@music_level - 1)
    @screen == :game && !@muted && !@paused ? song.play(true) : song.pause
  end

  def stop_music
    Gosu::Song.current_song&.stop
    @music_level = nil
  end

  def toggle_pause
    if @paused
      @paused_duration += Gosu.milliseconds - @pause_started_at
      @pause_started_at = nil
    else
      @pause_started_at = Gosu.milliseconds
    end
    @paused = !@paused
  end

  def reset_game_clock
    @paused = false
    @pause_started_at = nil
    @paused_duration = 0
  end

  def game_time
    (@paused ? @pause_started_at : Gosu.milliseconds) - @paused_duration
  end

  def draw_background
    background = @backgrounds[theme_index]
    now = Gosu.milliseconds
    scale = [WIDTH.to_f / background.width, HEIGHT.to_f / background.height].max * 1.08
    width = background.width * scale
    height = background.height * scale
    pan_x = Math.sin((now + theme_index * 700) / 5_000.0) * 10
    pan_y = Math.cos((now + theme_index * 430) / 6_000.0) * 7
    background.draw((WIDTH - width) / 2 + pan_x, (HEIGHT - height) / 2 + pan_y, 0, scale, scale)

    layer_color = accent
    Gosu.draw_rect(0, 0, WIDTH, HEIGHT, alpha_color(layer_color, 22), 0.1)
    36.times do |index|
      speed = 55.0 + (index % 9) * 8
      x = (index * 137 + theme_index * 53 + now / speed) % WIDTH
      y = (index * 71 + theme_index * 41 - now / (speed * 1.7)) % HEIGHT
      size = 1 + (index % 3)
      Gosu.draw_rect(x, y, size, size, alpha_color(layer_color, 70 + (index % 4) * 18), 0.2)
    end

    6.times do |index|
      drift = (now / (24.0 + index * 5) + index * 193 + theme_index * 47) % (WIDTH + 300) - 150
      lean = (theme_index.even? ? 1 : -1) * (80 + index * 9)
      color = alpha_color(layer_color, 18 + index * 3)
      Gosu.draw_quad(drift, 0, color, drift + 2, 0, color,
                     drift + lean + 2, HEIGHT, color, drift + lean, HEIGHT, color, 0.25)
    end

    4.times do |index|
      y = 150 + index * 155 + Math.sin((now + index * 900 + theme_index * 300) / 1_800.0) * 22
      Gosu.draw_rect(0, y, WIDTH, 42, alpha_color(layer_color, 10 + index * 2), 0.3)
    end
    Gosu.draw_rect(0, 0, WIDTH, HEIGHT, 0x18040912, 0.35)
  end

  def draw_select
    center_text(@title_font, "RAI*BERT", WIDTH / 2 + 3, 61, 3.9, COLORS[:shadow])
    center_text(@title_font, "RAI*BERT", WIDTH / 2, 58, 4, COLORS[:white])
    center_text(@font, "A RUBY ARCADE ODYSSEY", WIDTH / 2, 124, 4, accent)

    CHARACTERS.each_with_index do |character, index|
      x = index.zero? ? 300 : 700
      selected = index == @selection
      border = selected ? COLORS[:green] : COLORS[:muted]
      Gosu.draw_rect(x - 155, 190, 310, 390, COLORS[:panel], 2)
      draw_border(x - 155, 190, 310, 390, border, 3)
      draw_diamond(x, 421, 110, 27, selected ? accent : COLORS[:muted], 3)
      image = sprite(character[:id], 0, (Gosu.milliseconds / 110) % 7)
      image.draw(x - 96, 226 + Math.sin(Gosu.milliseconds / 450.0) * 5, 4, 1, 1)
      center_text(@font, character[:name], x, 470, 4, selected ? COLORS[:white] : COLORS[:muted])
      center_text(@small_font, character[:subtitle], x, 505, 4, COLORS[:muted])
      center_text(@small_font, selected ? "> READY <" : "", x, 540, 4, COLORS[:green])
    end

    difficulty = GameState::DIFFICULTIES.fetch(DIFFICULTY_KEYS.fetch(@difficulty_selection))
    center_text(@font, "#{binding_label(:select_up)} / #{binding_label(:select_down)}  DIFFICULTY: #{difficulty[:label]}", WIDTH / 2, 590, 4, accent)
    center_text(@small_font, difficulty[:note].upcase, WIDTH / 2, 618, 4, COLORS[:muted])
    center_text(@font, "#{binding_label(:select_left)} / #{binding_label(:select_right)} TO CHOOSE  //  #{binding_label(:confirm)} TO BOOT", WIDTH / 2, 660, 4, COLORS[:white])
    move_keys = GameState::DIRECTIONS.keys.flat_map { |action| @control_names.fetch(action) }.uniq.map(&:upcase).join(" ")
    center_text(@small_font, "MOVE #{move_keys}  |  #{binding_label(:options)} options  |  #{binding_label(:pause)} pause  |  #{binding_label(:mute)} mute", WIDTH / 2, 708, 4, COLORS[:muted])
  end

  def draw_options
    center_text(@title_font, "OPTIONS", WIDTH / 2, 72, 4, COLORS[:white])
    center_text(@small_font, "CHOOSE A DIRECTION, THEN PRESS ENTER", WIDTH / 2, 142, 4, COLORS[:muted])

    MOVE_ACTIONS.each_with_index do |action, index|
      selected = index == @options_selection
      y = 220 + index * 82
      color = selected ? COLORS[:green] : COLORS[:muted]
      Gosu.draw_rect(270, y, 460, 56, COLORS[:panel], 2)
      draw_border(270, y, 460, 56, color, 3)
      @font.draw_text(selected ? ">" : " ", 292, y + 16, 4, 1, 1, color)
      @font.draw_text(MOVE_LABELS.fetch(action), 330, y + 16, 4, 1, 1, COLORS[:white])
      @font.draw_text(binding_label(action), 650, y + 16, 4, 1, 1, color)
    end

    prompt = @rebinding_action ? "PRESS NEW KEY FOR #{MOVE_LABELS.fetch(@rebinding_action)}" : @options_message
    center_text(@font, prompt.to_s, WIDTH / 2, 580, 4, COLORS[:amber])
    center_text(@small_font, "ARROWS MOVE  //  ENTER CHANGE  //  ESC BACK", WIDTH / 2, 654, 4, COLORS[:muted])
  end

  def draw_game
    draw_hud
    draw_platforms
    draw_pyramid
    draw_pickup
    draw_enemies
    draw_player

    if @game.status == :stage_clear
      overlay("DEPLOYED!", "next pipeline booting...", COLORS[:green])
    elsif @game.status == :victory
      overlay("PIPELINE SHIPPED!", "#{binding_label(:confirm)} replay  //  #{binding_label(:pause)} character select", accent)
    elsif @game.status == :game_over && !@respawn
      overlay("BUILD FAILED", "#{binding_label(:confirm)} retry  //  #{binding_label(:pause)} character select", COLORS[:ruby])
    elsif @paused
      overlay("PAUSED", "#{binding_label(:pause)} resume  //  #{binding_label(:options)} options  //  #{binding_label(:mute)} #{@muted ? 'unmute' : 'mute'}", COLORS[:amber])
    end

    if game_time < @flash_until
      Gosu.draw_rect(0, 0, WIDTH, HEIGHT, Gosu::Color.new(0x44_ff174f), 20)
    end
  end

  def draw_hud
    fixed = @game.tiles.count { |_tile, value| value == @game.target }
    Gosu.draw_rect(16, 12, WIDTH - 32, 80, 0xe609101e, 4.9)
    Gosu.draw_rect(16, 12, 3, 80, accent, 5)
    @font.draw_text(format("STAGE %02d :: %s", @game.stage, LEVEL_NAMES.fetch(@game.level - 1)), 28, 22, 5, 1, 1, accent)
    @small_font.draw_text(format("PASS %02d/28", fixed), 30, 54, 5, 1, 1, COLORS[:white])
    center_text(@font, format("SCORE %07d", @game.score), WIDTH / 2, 22, 5, COLORS[:white])
    @small_font.draw_text("LIVES", 772, 29, 5, 1, 1, COLORS[:muted])
    if @game.lives <= 5
      @game.lives.times { |index| sprite(@character, 0, 0).draw(820 + index * 31, 14, 5, 0.20, 0.20) }
    else
      sprite(@character, 0, 0).draw(820, 14, 5, 0.20, 0.20)
      @font.draw_text("x#{@game.lives}", 854, 24, 5, 1, 1, COLORS[:white])
    end
    @small_font.draw_text(@game.difficulty.to_s.upcase, 790, 54, 5, 1, 1, accent)
    @small_font.draw_text(@muted ? "MUTED" : "SOUND ON", 878, 54, 5, 1, 1, COLORS[:muted])
    effects = []
    effects << "DEBUGGER: FROZEN" if game_time < @game.freeze_until
    effects << "SHIELD: #{((@game.shield_until - game_time) / 1_000.0).ceil}s" if game_time < @game.shield_until
    center_text(@small_font, effects.join("  //  "), WIDTH / 2, 60, 5, COLORS[:cyan]) unless effects.empty?
    controls = [[:up_left, "up-left"], [:up_right, "up-right"], [:down_left, "down-left"], [:down_right, "down-right"]]
    legend = controls.map { |action, label| "#{binding_label(action)} #{label}" }.join("    ")
    Gosu.draw_rect(16, 690, WIDTH - 32, 60, 0xe609101e, 4.9)
    center_text(@small_font, THEMES[theme_index][:name], WIDTH / 2, 699, 5, accent)
    center_text(@small_font, legend, WIDTH / 2, 724, 5, COLORS[:muted])
    Gosu.draw_rect(130, 61, 220, 5, 0xff263444, 5)
    Gosu.draw_rect(130, 61, 220 * fixed / 28.0, 5, accent, 5.1)
  end

  def draw_pyramid
    GameState::ROWS.times do |row|
      (row + 1).times do |column|
        x, y = tile_center([row, column])
        progress = @game.tiles[[row, column]]
        top_color, label = tile_style(progress)
        side_left = darken(top_color, 0.48)
        side_right = darken(top_color, 0.32)
        z = 2 + row * 0.01
        draw_diamond(x, y + 24, TILE_WIDTH / 2 + 5, TILE_HEIGHT / 2, 0x66000000, z - 0.01)
        Gosu.draw_quad(x - TILE_WIDTH / 2, y, side_left,
                       x, y + TILE_HEIGHT / 2, side_left,
                       x, y + TILE_HEIGHT / 2 + 18, COLORS[:shadow],
                       x - TILE_WIDTH / 2, y + 18, COLORS[:shadow], z)
        Gosu.draw_quad(x, y + TILE_HEIGHT / 2, side_right,
                       x + TILE_WIDTH / 2, y, side_right,
                       x + TILE_WIDTH / 2, y + 18, COLORS[:shadow],
                       x, y + TILE_HEIGHT / 2 + 18, COLORS[:shadow], z)
        Gosu.draw_quad(x, y - TILE_HEIGHT / 2, top_color,
                       x + TILE_WIDTH / 2, y, top_color,
                       x, y + TILE_HEIGHT / 2, top_color,
                       x - TILE_WIDTH / 2, y, top_color, z + 0.01)
        rim = progress == @game.target ? accent : Gosu::Color.new(0xff69858f)
        [[x, y - 23, x + 45, y], [x + 45, y, x, y + 23],
         [x, y + 23, x - 45, y], [x - 45, y, x, y - 23]].each do |line|
          Gosu.draw_line(line[0], line[1], rim, line[2], line[3], rim, z + 0.015)
        end
        draw_diamond(x, y, 33, 15, darken(top_color, 0.88), z + 0.016)
        center_text(@small_font, label, x, y - 8, z + 0.02, COLORS[:background])
      end
    end
  end

  def tile_style(progress)
    return [Gosu::Color.new(THEMES[theme_index][:tile]), "x"] if progress.zero?
    return [COLORS[:amber], "#{progress}/#{@game.target}"] if progress < @game.target

    [Gosu::Color.new(THEMES[theme_index][:pass]), "OK"]
  end

  def draw_platforms
    { left: [3, -1], right: [3, 4] }.each do |side, position|
      next unless @game.rescues[side]

      x, y = tile_center(position)
      draw_object(:rescue, x, y + 10, 92, 3.2)
    end
  end

  def draw_pickup
    return unless @game.pickup

    pickup = @game.pickup
    destination = [pickup[:row], pickup[:column]]
    progress = pickup[:moved_at] ? [[(game_time - pickup[:moved_at]) / 250.0, 0].max, 1].min : 1
    x, y = tile_center(interpolate(pickup[:from] || destination, destination, progress))
    y += Math.sin(game_time / 220.0) * 4 - 4
    POWERUP_STYLES.key?(pickup[:kind]) ? draw_powerup(pickup[:kind], x, y, 56, 3.5) : draw_object(pickup[:kind], x, y, 56, 3.5)
  end

  def draw_enemies
    @game.enemies.each do |enemy|
      x, y = tile_center([enemy[:row], enemy[:column]])
      draw_object(enemy[:kind], x, y + 6 + Math.sin(game_time / 170.0 + x) * 2, 65, 3.4)
    end
  end

  def draw_player
    now = game_time
    position = @game.player
    jump_progress = nil
    if @respawn
      elapsed = now - @respawn[:started_at]
      if elapsed < DEATH_TIME
        position = @respawn[:position]
        row = 5
        frame = [[elapsed * ROW_FRAMES.fetch(row) / DEATH_TIME, 0].max, ROW_FRAMES.fetch(row) - 1].min
      else
        elapsed -= DEATH_TIME
        position = [0, 0]
        row = 6
        frame = [[elapsed * ROW_FRAMES.fetch(row) / RESPAWN_TIME, 0].max, ROW_FRAMES.fetch(row) - 1].min
      end
    elsif @hop
      elapsed = now - @hop[:started_at]
      t = [[elapsed.to_f / @hop[:duration], 0].max, 1].min
      position = animated_position(t)
      jump_progress = t
      row = @hop[:event] == :rescue ? 4 : HOP_ROWS.fetch(@hop[:direction])
      frame = [(t * ROW_FRAMES.fetch(row)).floor, ROW_FRAMES.fetch(row) - 1].min
    else
      elapsed = now - @idle_started_at
      act = [theme_index / 5, IDLE_ROWS.length - 1].min
      row = elapsed >= 1_800 ? IDLE_ROWS.fetch(act) : 0
      frame = (elapsed / 130) % ROW_FRAMES.fetch(row)
    end

    x, y = tile_center(position)
    draw_diamond(x, y + 4, 20, 7, 0x88000000, 3.8)
    y -= Math.sin(jump_progress * Math::PI) * 34 if jump_progress
    image = sprite(@character, row, frame)
    alpha = @game.invulnerable?(now) && (now / 100).even? ? Gosu::Color.new(0x66_ffffff) : Gosu::Color::WHITE
    scale = @character == :voxel ? 0.34 : 0.32
    image.draw(x - 96 * scale, y - 180 * scale, 4, scale, scale, alpha)
  end

  def animated_position(t)
    if @hop[:event] == :rescue
      if t < 0.5
        interpolate(@hop[:from], @hop[:target], t * 2)
      else
        interpolate(@hop[:target], [0, 0], (t - 0.5) * 2)
      end
    else
      interpolate(@hop[:from], @hop[:target], t)
    end
  end

  def interpolate(from, to, amount)
    [from[0] + (to[0] - from[0]) * amount, from[1] + (to[1] - from[1]) * amount]
  end

  def tile_center(position)
    row, column = position
    [WIDTH / 2 + (column - row / 2.0) * TILE_WIDTH, PYRAMID_TOP + row * ROW_STEP]
  end

  def sprite(character, row, column)
    @sprites.fetch(character).fetch(row * 8 + column)
  end

  def theme_index
    @screen == :game ? @game.level - 1 : 0
  end

  def accent
    Gosu::Color.new(THEMES[theme_index][:accent])
  end

  def draw_object(kind, x, y, size, z)
    draw_diamond(x, y, size * 0.28, 6, 0x77000000, z - 0.01)
    @objects.fetch(kind).draw(x - size / 2.0, y - size, z, size / 512.0, size / 512.0)
  end

  def draw_powerup(kind, x, y, size, z)
    label, color = POWERUP_STYLES.fetch(kind)
    draw_diamond(x, y, size * 0.28, 6, 0x77000000, z - 0.01)
    if (image = @powerups[kind])
      scale = size * 1.25 / [image.width, image.height].max
      image.draw(x - image.width * scale / 2, y - image.height * scale, z, scale, scale)
      draw_diamond(x, y - 8, size * 0.3, 9, 0xdd_07100d, z + 0.01)
      center_text(@small_font, label, x, y - 15, z + 0.02, color)
    else
      center_y = y - size / 2.0
      draw_diamond(x, center_y, size * 0.38, size * 0.32, color, z)
      center_text(@small_font, label, x, center_y - 8, z + 0.01, COLORS[:background])
    end
  end

  def draw_diamond(x, y, half_width, half_height, color, z)
    Gosu.draw_quad(x, y - half_height, color, x + half_width, y, color,
                   x, y + half_height, color, x - half_width, y, color, z)
  end

  def overlay(title, subtitle, color)
    Gosu.draw_rect(170, 275, 660, 155, Gosu::Color.new(0xee_08100d), 10)
    draw_border(170, 275, 660, 155, color, 11)
    center_text(@title_font, title, WIDTH / 2, 298, 12, color)
    center_text(@small_font, subtitle, WIDTH / 2, 382, 12, COLORS[:white])
  end

  def draw_border(x, y, width, height, color, z)
    Gosu.draw_rect(x, y, width, 2, color, z)
    Gosu.draw_rect(x, y + height - 2, width, 2, color, z)
    Gosu.draw_rect(x, y, 2, height, color, z)
    Gosu.draw_rect(x + width - 2, y, 2, height, color, z)
  end

  def center_text(font, text, x, y, z, color)
    font.draw_text(text, x - font.text_width(text) / 2.0, y, z, 1, 1, color)
  end

  def darken(color, factor)
    Gosu::Color.new(0xff_000000 | ((color.red * factor).to_i << 16) |
                    ((color.green * factor).to_i << 8) | (color.blue * factor).to_i)
  end

  def alpha_color(color, alpha)
    Gosu::Color.new((alpha << 24) | (color.red << 16) | (color.green << 8) | color.blue)
  end

  def load_controls
    path = File.join(__dir__, "config/controls.json")
    settings = JSON.parse(File.read(path))
    unknown = settings.keys.map(&:to_sym) - CONTROL_ACTIONS
    missing = CONTROL_ACTIONS - settings.keys.map(&:to_sym)
    raise ArgumentError, "Unknown control actions: #{unknown.join(', ')}" unless unknown.empty?
    raise ArgumentError, "Missing control actions: #{missing.join(', ')}" unless missing.empty?

    @control_names = settings.to_h do |action, names|
      unless names.is_a?(Array) && !names.empty? && names.all? { |name| name.is_a?(String) }
        raise ArgumentError, "Control #{action} must contain one or more key names"
      end
      [action.to_sym, names.map(&:downcase)]
    end
    @controls = @control_names.transform_values { |names| names.map { |name| key_id(name) } }
  rescue JSON::ParserError => error
    raise ArgumentError, "Invalid controls JSON: #{error.message}"
  end

  def key_id(name)
    normalized = KEY_ALIASES.fetch(name, name).upcase
    constant = "KB_#{normalized}"
    raise ArgumentError, "Unknown control key: #{name}" unless Gosu.const_defined?(constant)

    Gosu.const_get(constant)
  end

  def key_name(key)
    constant = Gosu.constants.grep(/\AKB_/).find { |name| Gosu.const_get(name) == key }
    constant&.to_s&.delete_prefix("KB_")&.downcase
  end

  def pressed?(action, key)
    @controls.fetch(action).include?(key)
  end

  def binding_label(action)
    @control_names.fetch(action).map(&:upcase).join("/")
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = RaiBertCLI.parse(ARGV)
  rescue OptionParser::ParseError => error
    warn "Rai*bert: #{error.message}"
    warn "Run with --help for usage."
    exit 2
  end
  if (help = options.delete(:help))
    puts help
    exit
  end
  demo = options.delete(:demo)
  if demo
    require_relative "lib/demo_window"
    options[:difficulty] ||= :normal
    DemoWindow.new(**options).show
  else
    RaiBertWindow.new(**options).show
  end
end
