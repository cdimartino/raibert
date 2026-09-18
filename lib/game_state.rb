# frozen_string_literal: true

class GameState
  ROWS = 7
  LEVEL_COUNT = 20
  OBJECT_MOVE_TIME = 250
  LEVEL_TARGETS = [1, 2, 2, 2, *Array.new(16, 3)].freeze
  PICKUP_KINDS = %i[debugger gc life shield patch].freeze
  DIFFICULTIES = {
    easy: { label: "EASY", note: "4 lives // relaxed threats", lives: 4, spawn: 1.25, speed: 1.15, enemies: -1, powerup: 1.15 },
    normal: { label: "NORMAL", note: "3 lives // standard pipeline", lives: 3, spawn: 1.0, speed: 1.0, enemies: 0, powerup: 1.0 },
    hard: { label: "HARD", note: "3 lives // dense threat field", lives: 3, spawn: 0.9, speed: 0.9, enemies: 1, powerup: 0.85 }
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

  def initialize(random: Random.new, now: 0, difficulty: :normal, start_level: 1, starting_lives: nil)
    @random = random
    @difficulty = difficulty
    @difficulty_settings = DIFFICULTIES.fetch(difficulty) do
      raise ArgumentError, "Unknown difficulty: #{difficulty}"
    end
    raise ArgumentError, "Start level must be between 1 and #{LEVEL_COUNT}" unless start_level.is_a?(Integer) && start_level.between?(1, LEVEL_COUNT)

    @start_level = start_level
    @starting_lives = starting_lives || @difficulty_settings[:lives]
    raise ArgumentError, "Starting lives must be between 1 and 99" unless @starting_lives.is_a?(Integer) && @starting_lives.between?(1, 99)

    reset(now)
  end

  def reset(now = 0)
    @lives = @starting_lives
    @score = 0
    @stage = @start_level
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

  def move(direction, now, started_at: now)
    return :ignored unless @status == :playing

    from = @player.dup
    destination = target_for(direction)
    unless valid?(destination)
      rescue_side = RESCUES[[from, direction]]
      return use_rescue(rescue_side, now) if rescue_side && @rescues[rescue_side]

      lose_life(now)
      return :fall
    end

    motion = { from: from, to: destination, started_at: started_at, ended_at: now }
    @player = destination
    @player_motion = motion
    touch_tile(destination, now)
    collected = collect_pickup(now, motion: motion)
    hit = collide(now, motion: motion)
    return :hit if hit
    return @status if %i[stage_clear victory].include?(@status)

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
    collected = collect_pickup(now, motion: @player_motion)
    return collected unless @status == :playing
    return :hit if collide(now, motion: @player_motion)
    return collected if now < @freeze_until

    spawn_enemy(now)
    return :hit if collide(now, motion: @player_motion)

    hit = false
    @enemies.dup.each do |enemy|
      next if now < enemy[:next_at]

      step_enemy(enemy, now)
      if collide(now, motion: @player_motion)
        hit = true
        break
      end
    end
    hit ? :hit : collected
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
    @player_motion = nil
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
    @player_motion = nil
    @score += 250
    @invulnerable_until = now + 1_200
    collect_pickup(now)
    :rescue
  end

  def lose_life(now)
    @lives -= 1
    @player = [0, 0]
    @player_motion = nil
    @enemies.clear
    @pickup = nil
    @invulnerable_until = now + 1_500
    @status = :game_over if @lives <= 0
  end

  def collide(now, motion: nil)
    return false if invulnerable?(now)
    return false unless @enemies.any? { |enemy| entity_collides?(enemy, motion, now) }

    lose_life(now)
    true
  end

  def collect_pickup(now, motion: nil)
    return unless @pickup && entity_collides?(@pickup, motion, now)

    kind = @pickup[:kind]
    @pickup = nil
    @score += 300
    case kind
    when :debugger
      @freeze_until = now + 4_000
    when :gc
      @enemies.clear
    when :life
      @lives = [@lives + 1, @starting_lives + 1].min
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

    kinds = PICKUP_KINDS.reject { |kind| kind == :life && @lives >= @starting_lives + 1 }
    @pickup = {
      kind: kinds.sample(random: @random), row: 0, column: 0,
      from: [-1, -0.5], spawned_at: now, moved_at: now, next_at: now + pickup_interval
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
    @enemies << { kind: kind, row: row, column: column, spawned_at: now, next_at: now + enemy_interval(kind) }
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
    from = [enemy[:row], enemy[:column]]
    destination = if enemy[:kind] == :exception
                    chasing_step(enemy)
                  else
                    descending_step(enemy)
                  end

    unless destination
      @enemies.delete(enemy)
      return
    end

    enemy[:from] = from
    enemy[:row], enemy[:column] = destination
    enemy[:moved_at] = now
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

  def entity_collides?(entity, motion, now)
    destination = [entity[:row], entity[:column]]
    motion ||= { from: @player, to: @player, started_at: now, ended_at: now }
    existence_start = entity[:spawned_at] || motion[:started_at]
    return false if motion[:ended_at] < existence_start

    unless entity[:from] && entity[:moved_at]
      stationary = {
        from: destination, to: destination,
        started_at: [motion[:started_at], existence_start].max, ended_at: motion[:ended_at]
      }
      return motions_collide?(motion, stationary)
    end

    entity_ends_at = entity[:moved_at] + OBJECT_MOVE_TIME
    phases = []
    if motion[:started_at] <= entity[:moved_at]
      phases << {
        from: entity[:from], to: entity[:from],
        started_at: [motion[:started_at], existence_start].max,
        ended_at: [motion[:ended_at], entity[:moved_at]].min
      }
    end
    if motion[:ended_at] >= entity[:moved_at] && motion[:started_at] <= entity_ends_at
      phases << {
        from: entity[:from], to: destination,
        started_at: entity[:moved_at], ended_at: entity_ends_at
      }
    end
    if motion[:ended_at] >= entity_ends_at
      phases << {
        from: destination, to: destination,
        started_at: [motion[:started_at], entity_ends_at].max, ended_at: motion[:ended_at]
      }
    end
    phases.any? { |entity_motion| motions_collide?(motion, entity_motion) }
  end

  def motions_collide?(first, second)
    overlap_start = [first[:started_at], second[:started_at]].max
    overlap_end = [first[:ended_at], second[:ended_at]].min
    return false if overlap_start > overlap_end

    start_delta = position_delta(first, second, overlap_start)
    end_delta = position_delta(first, second, overlap_end)
    return true if zero_vector?(start_delta) || zero_vector?(end_delta)

    fractions = start_delta.zip(end_delta).filter_map do |start_value, end_value|
      change = end_value - start_value
      return false if change.abs < Float::EPSILON && start_value.abs >= Float::EPSILON

      -start_value / change unless change.abs < Float::EPSILON
    end
    return true if fractions.empty?

    fraction = fractions.first
    fraction.between?(0.0, 1.0) && fractions.all? { |value| (value - fraction).abs < 1e-9 }
  end

  def position_delta(first, second, now)
    first_position = position_during(first, now)
    second_position = position_during(second, now)
    first_position.zip(second_position).map { |first_value, second_value| first_value - second_value }
  end

  def position_during(motion, now)
    duration = motion[:ended_at] - motion[:started_at]
    return motion[:to].map(&:to_f) unless duration.positive?

    progress = (now - motion[:started_at]).to_f / duration
    motion[:from].zip(motion[:to]).map do |from, to|
      from + (to - from) * progress
    end
  end

  def zero_vector?(vector)
    vector.all? { |value| value.abs < 1e-9 }
  end

  def advance_stage(now)
    return @status = :victory if @level >= LEVEL_COUNT

    @stage += 1
    @lives += 1 if @lives < @starting_lives
    setup_stage(now)
  end
end
