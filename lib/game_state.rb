# frozen_string_literal: true

class GameState
  ROWS = 7
  LEVEL_COUNT = 20
  LEVEL_TARGETS = [1, 2, 2, 2, *Array.new(16, 3)].freeze
  PICKUP_KINDS = %i[debugger gc life shield patch].freeze
  DIFFICULTIES = {
    easy: { label: "EASY", note: "4 lives // relaxed threats", lives: 4, spawn: 1.25, speed: 1.15, enemies: -1, powerup: 1.15 },
    normal: { label: "NORMAL", note: "3 lives // standard pipeline", lives: 3, spawn: 1.0, speed: 1.0, enemies: 0, powerup: 1.0 },
    hard: { label: "HARD", note: "3 lives // dense threat field", lives: 3, spawn: 1.02, speed: 1.02, enemies: 1, powerup: 0.85 }
  }.freeze
  DIRECTIONS = {
    up_left: [-1, -1],
    up_right: [-1, 0],
    down_left: [1, 0],
    down_right: [1, 1]
  }.freeze
  RESCUES = {
    [[4, 0], :up_left] => :left,
    [[4, 4], :up_right] => :right
  }.freeze

  attr_reader :player, :tiles, :enemies, :pickup, :lives, :score, :stage,
              :level, :target, :status, :rescues, :freeze_until, :shield_until,
              :difficulty

  def initialize(random: Random.new, now: 0, difficulty: :normal)
    @random = random
    @difficulty = difficulty
    @difficulty_settings = DIFFICULTIES.fetch(difficulty) do
      raise ArgumentError, "Unknown difficulty: #{difficulty}"
    end
    reset(now)
  end

  def reset(now = 0)
    @lives = @difficulty_settings[:lives]
    @score = 0
    @stage = 1
    setup_stage(now)
  end

  def target_for(direction)
    delta = DIRECTIONS.fetch(direction)
    [@player[0] + delta[0], @player[1] + delta[1]]
  end

  def valid?(position)
    row, column = position
    row.between?(0, ROWS - 1) && column.between?(0, row)
  end

  def move(direction, now)
    return :ignored unless @status == :playing

    from = @player.dup
    destination = target_for(direction)
    unless valid?(destination)
      rescue_side = RESCUES[[from, direction]]
      return use_rescue(rescue_side, now) if rescue_side && @rescues[rescue_side]

      lose_life(now)
      return :fall
    end

    @player = destination
    touch_tile(destination, now)
    collected = collect_pickup(now)
    hit = collide(now)
    return :hit if hit
    return :stage_clear if @status == :stage_clear

    collected || :hop
  end

  def tick(now)
    if @status == :stage_clear
      advance_stage(now) if now - @stage_clear_at >= 1_500
      return
    end
    return unless @status == :playing

    spawn_pickup(now)
    step_pickup(now)
    return if now < @freeze_until

    spawn_enemy(now)
    @enemies.dup.each do |enemy|
      next if now < enemy[:next_at]

      step_enemy(enemy, now)
      break if collide(now)
    end
  end

  def invulnerable?(now)
    now < @invulnerable_until
  end

  def enemy_cap
    [2 + ((@level - 1) / 4) + @difficulty_settings[:enemies], 2].max
  end

  private

  def setup_stage(now)
    @level = @stage
    @target = LEVEL_TARGETS.fetch(@level - 1)
    @tiles = {}
    ROWS.times { |row| (row + 1).times { |column| @tiles[[row, column]] = 0 } }
    @player = [0, 0]
    @enemies = []
    @pickup = nil
    @rescues = { left: true, right: true }
    @status = :playing
    @freeze_until = 0
    @shield_until = 0
    @invulnerable_until = now + 1_000
    @last_spawn_at = now
    @last_pickup_at = now
    touch_tile(@player, now)
  end

  def touch_tile(position, now)
    return if @tiles[position] >= @target

    @tiles[position] += 1
    @score += 100
    return unless @tiles.values.all? { |value| value == @target }

    @score += 1_000 * @level
    if @level == LEVEL_COUNT
      @status = :victory
    else
      @status = :stage_clear
      @stage_clear_at = now
    end
  end

  def use_rescue(side, now)
    @rescues[side] = false
    @player = [0, 0]
    @score += 250
    @invulnerable_until = now + 1_200
    :rescue
  end

  def lose_life(now)
    @lives -= 1
    @player = [0, 0]
    @enemies.clear
    @pickup = nil
    @invulnerable_until = now + 1_500
    @status = :game_over if @lives <= 0
  end

  def collide(now)
    return false if invulnerable?(now)
    return false unless @enemies.any? { |enemy| [enemy[:row], enemy[:column]] == @player }

    lose_life(now)
    true
  end

  def collect_pickup(now)
    return unless @pickup && [@pickup[:row], @pickup[:column]] == @player

    kind = @pickup[:kind]
    @pickup = nil
    @score += 300
    case kind
    when :debugger
      @freeze_until = now + 4_000
    when :gc
      @enemies.clear
    when :life
      @lives = [@lives + 1, @difficulty_settings[:lives] + 1].min
    when :shield
      @shield_until = now + 5_000
      @invulnerable_until = [@invulnerable_until, @shield_until].max
    when :patch
      @tiles.keys.select { |position| @tiles[position] < @target }.sample(3, random: @random).each do |position|
        touch_tile(position, now)
      end
    end
    kind
  end

  def spawn_pickup(now)
    return if @pickup || now - @last_pickup_at < 8_000
    return if @player == [0, 0] || @enemies.any? { |enemy| [enemy[:row], enemy[:column]] == [0, 0] }

    kinds = PICKUP_KINDS.reject { |kind| kind == :life && @lives >= @difficulty_settings[:lives] + 1 }
    @pickup = {
      kind: kinds.sample(random: @random), row: 0, column: 0,
      from: [-1, -0.5], moved_at: now, next_at: now + pickup_interval
    }
    @last_pickup_at = now
  end

  def step_pickup(now)
    return unless @pickup && now >= @pickup[:next_at]

    from = [@pickup[:row], @pickup[:column]]
    destination = descending_step(@pickup)
    return @pickup = nil unless destination

    @pickup[:from] = from
    @pickup[:row], @pickup[:column] = destination
    @pickup[:moved_at] = now
    @pickup[:next_at] = now + pickup_interval
  end

  def pickup_interval
    pressure = [1.0 - ((@level - 1) * 0.015), 0.70].max
    (1_000 * pressure * @difficulty_settings[:powerup]).to_i
  end

  def spawn_enemy(now)
    return if now - @last_spawn_at < spawn_interval
    return if @enemies.length >= enemy_cap
    return if @player == [0, 0]

    kind = enemy_kind
    row, column = kind == :exception ? [ROWS - 1, @random.rand(ROWS)] : [0, 0]
    @enemies << { kind: kind, row: row, column: column, next_at: now + enemy_interval(kind) }
    @last_spawn_at = now
  end

  def enemy_kind
    roll = @random.rand
    return :bug if @level == 1
    return roll < 0.7 ? :bug : :exception if @level == 2

    bug_cutoff = [0.72 - ((@level - 2) * 0.015), 0.42].max
    return :bug if roll < bug_cutoff

    roll < bug_cutoff + 0.26 ? :exception : :regression
  end

  def spawn_interval
    base = [3_000 - ((@level - 1) * 75), 1_500].max
    (base * @difficulty_settings[:spawn]).to_i
  end

  def enemy_interval(kind)
    base = { bug: 900, exception: 1_100, regression: 1_000 }.fetch(kind)
    pressure = [1.0 - ((@level - 1) * 0.012), 0.72].max
    (base * pressure * @difficulty_settings[:speed]).to_i
  end

  def step_enemy(enemy, now)
    destination = if enemy[:kind] == :exception
                    chasing_step(enemy)
                  else
                    descending_step(enemy)
                  end

    unless destination
      @enemies.delete(enemy)
      return
    end

    enemy[:row], enemy[:column] = destination
    enemy[:next_at] = now + enemy_interval(enemy[:kind])
    if enemy[:kind] == :regression
      position = [enemy[:row], enemy[:column]]
      @tiles[position] -= 1 if @tiles[position].positive?
    end
  end

  def descending_step(enemy)
    row = enemy[:row] + 1
    return if row >= ROWS

    column = enemy[:column] + @random.rand(2)
    [row, column]
  end

  def chasing_step(enemy)
    origin = [enemy[:row], enemy[:column]]
    choices = DIRECTIONS.values.map { |delta| [origin[0] + delta[0], origin[1] + delta[1]] }.select { |p| valid?(p) }
    nearest = choices.map { |p| distance(p, @player) }.min
    choices.select { |p| distance(p, @player) == nearest }.sample(random: @random)
  end

  def distance(a, b)
    (a[0] - b[0]).abs + (a[1] - b[1]).abs
  end

  def advance_stage(now)
    return @status = :victory if @level >= LEVEL_COUNT

    @stage += 1
    @lives += 1 if @lives < @difficulty_settings[:lives]
    setup_stage(now)
  end
end
