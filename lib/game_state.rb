# frozen_string_literal: true

require_relative "board_layouts"

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
              :difficulty, :board

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
    connection_for(@player, direction)&.to || @board.fall_target(@player, direction)
  end

  def connection_for(position, direction)
    @board.connection(position, direction)
  end

  def neighbors(position = @player)
    @board.neighbors(position)
  end

  def valid?(position)
    @board.include?(position)
  end

  def move(direction, now, started_at: now)
    return :ignored unless @status == :playing

    from = @player.dup
    connection = connection_for(from, direction)
    unless connection
      rescue_side = @board.rescue_for(from, direction)
      return use_rescue(rescue_side, now) if rescue_side && @rescues[rescue_side]

      lose_life(now)
      return :fall
    end

    destination = connection.to
    motion = motion_for(connection, started_at, now)
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
    @board = BoardLayouts.fetch(@level)
    @target = LEVEL_TARGETS.fetch(@level - 1)
    @tiles = @board.tiles.to_h { |position| [position, 0] }
    @player = @board.start.dup
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
    @player = @board.start.dup
    @player_motion = nil
    @score += 250
    @invulnerable_until = now + 1_200
    collect_pickup(now)
    :rescue
  end

  def lose_life(now)
    @lives -= 1
    @player = @board.start.dup
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
    return if @player == @board.start || @enemies.any? { |enemy| [enemy[:row], enemy[:column]] == @board.start }

    kinds = PICKUP_KINDS.reject { |kind| kind == :life && @lives >= @starting_lives + 1 }
    @pickup = {
      kind: kinds.sample(random: @random), row: @board.start[0], column: @board.start[1],
      from: @board.start, spawned_at: now, moved_at: now, next_at: now + pickup_interval
    }
    @last_pickup_at = now
  end

  def step_pickup(now)
    return unless @pickup && now >= @pickup[:next_at]

    from = [@pickup[:row], @pickup[:column]]
    connection = descending_connection(@pickup)
    return @pickup = nil unless connection

    @pickup[:from] = from
    @pickup[:row], @pickup[:column] = connection.to
    apply_connection_metadata(@pickup, connection)
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
    return if @player == @board.start

    kind = enemy_kind
    row, column = if kind == :exception
                    @board.farthest_tiles.sample(random: @random)
                  else
                    @board.start
                  end
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
    connection = if enemy[:kind] == :exception
                   chasing_connection(enemy)
                 else
                   descending_connection(enemy)
                 end

    unless connection
      @enemies.delete(enemy)
      return
    end

    enemy[:from] = from
    enemy[:row], enemy[:column] = connection.to
    apply_connection_metadata(enemy, connection)
    enemy[:moved_at] = now
    enemy[:next_at] = now + enemy_interval(enemy[:kind])
    if enemy[:kind] == :regression
      position = [enemy[:row], enemy[:column]]
      @tiles[position] -= 1 if @tiles[position].positive?
    end
  end

  def descending_step(enemy)
    descending_connection(enemy)&.to
  end

  def chasing_step(enemy)
    chasing_connection(enemy)&.to
  end

  def descending_connection(entity)
    origin = [entity[:row], entity[:column]]
    %i[down_left down_right].filter_map { |direction| @board.connection(origin, direction) }.sample(random: @random)
  end

  def chasing_connection(enemy)
    origin = [enemy[:row], enemy[:column]]
    choices = DIRECTIONS.keys.filter_map { |direction| @board.connection(origin, direction) }
    nearest = choices.map { |connection| graph_distance(connection.to, @player) }.min
    choices.select { |connection| graph_distance(connection.to, @player) == nearest }.sample(random: @random)
  end

  def graph_distance(origin, destination)
    return 0 if origin == destination

    distances = { origin => 0 }
    queue = [origin]
    until queue.empty?
      position = queue.shift
      @board.neighbors(position).each do |_direction, neighbor|
        next if distances.key?(neighbor)

        distance = distances.fetch(position) + 1
        return distance if neighbor == destination

        distances[neighbor] = distance
        queue << neighbor
      end
    end
    Float::INFINITY
  end

  def motion_for(connection, started_at, ended_at)
    {
      from: connection.from, to: connection.to,
      started_at: started_at, ended_at: ended_at,
      connection_id: connection.id, path: connection.path, layer: connection.layer
    }
  end

  def apply_connection_metadata(entity, connection)
    entity[:connection_id] = connection.id
    entity[:path] = connection.path
    entity[:layer] = connection.layer
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
        started_at: entity[:moved_at], ended_at: entity_ends_at,
        connection_id: entity[:connection_id], path: entity[:path], layer: entity[:layer]
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

    # Separate stair ribbons may cross in projection without sharing physical
    # space. Their endpoints are still ordinary board tiles and are handled by
    # the position checks below.
    distinct_layered_connections = first[:connection_id] && second[:connection_id] &&
                                   first[:connection_id] != second[:connection_id] &&
                                   first[:layer] != second[:layer]
    if distinct_layered_connections && overlap_start < overlap_end
      endpoint_times = [overlap_start, overlap_end, first[:started_at], first[:ended_at],
                        second[:started_at], second[:ended_at]].select do |time|
        time.between?(overlap_start, overlap_end)
      end
      return true if endpoint_times.any? { |time| zero_vector?(position_delta(first, second, time)) }
      return false
    end

    breakpoints = [overlap_start, overlap_end]
    [first, second].each do |motion|
      path = motion[:path]
      next unless path && path.length > 2

      duration = motion[:ended_at] - motion[:started_at]
      lengths = path.each_cons(2).map do |from, to|
        Math.sqrt(from.zip(to).sum { |a, b| (b - a)**2 })
      end
      traversed = 0.0
      lengths[0...-1].each do |length|
        traversed += length
        time = motion[:started_at] + duration * traversed / lengths.sum
        breakpoints << time if time.between?(overlap_start, overlap_end)
      end
    end
    breakpoints.sort.uniq.each_cons(2).any? do |interval_start, interval_end|
      linear_interval_collides?(first, second, interval_start, interval_end)
    end || linear_interval_collides?(first, second, overlap_start, overlap_start)
  end

  def linear_interval_collides?(first, second, interval_start, interval_end)
    start_delta = position_delta(first, second, interval_start)
    end_delta = position_delta(first, second, interval_end)
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
    path = motion[:path] || [motion[:from], motion[:to]]
    return interpolate_path(path, progress) if path.length > 2

    motion[:from].zip(motion[:to]).map do |from, to|
      from + (to - from) * progress
    end
  end

  def interpolate_path(path, progress)
    return path.last.map(&:to_f) if progress >= 1.0

    lengths = path.each_cons(2).map do |from, to|
      Math.sqrt(from.zip(to).sum { |first, second| (second - first)**2 })
    end
    remaining = lengths.sum * [[progress, 0.0].max, 1.0].min
    path.each_cons(2).zip(lengths).each do |(from, to), length|
      if remaining <= length
        fraction = length.zero? ? 1.0 : remaining / length
        return from.zip(to).map { |first, second| first + (second - first) * fraction }
      end

      remaining -= length
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
