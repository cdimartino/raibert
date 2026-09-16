# frozen_string_literal: true

require_relative "../game" unless defined?(RaiBertWindow)

class DemoWindow < RaiBertWindow
  NEXT_TICK_SLACK_MS = 34
  WAIT_LOOKAHEAD_MS = 16

  def initialize(start_level: 1, starting_lives: nil, difficulty: :normal)
    super(start_level: start_level, starting_lives: starting_lives)
    @difficulty_selection = DIFFICULTY_KEYS.index(difficulty) ||
                            raise(ArgumentError, "Unknown difficulty: #{difficulty}")
    start_game
    reset_demo_tracking
  end

  def update
    level = @game.level
    enemy_ids = @game.enemies.map(&:object_id)
    super
    @last_spawn_at = game_time if (@game.enemies.map(&:object_id) - enemy_ids).any?
    reset_demo_tracking if @game.level != level

    return if @game.status == :victory
    return restart_run if @game.status == :game_over && !@hop && !respawning?
    return unless @game.status == :playing && !@hop && !@paused && !respawning?

    move_once
  end

  private

  def restart_run
    press(:confirm)
    reset_demo_tracking
  end

  def reset_demo_tracking
    @last_spawn_at = game_time
    @best_tile_progress = @game.tiles.values.sum
    @stagnant_moves = 0
    @previous_player = nil
  end

  def move_once
    direction = choose_direction
    return unless direction

    @previous_player = @game.player.dup
    press(direction)
  end

  def choose_direction
    progress = @game.tiles.values.sum
    if progress > @best_tile_progress
      @best_tile_progress = progress
      @stagnant_moves = 0
    else
      @stagnant_moves += 1
    end

    future = game_time + JUMP_TIME + NEXT_TICK_SLACK_MS
    moves = legal_moves
    safe_moves = moves.select { |_direction, destination| safe_landing?(destination, future) }
    if safe_moves.empty?
      return if safe_to_wait?
      return available_rescue_direction if available_rescue_direction

      return moves.min_by { |_direction, destination| collision_risk(destination, future) }&.first
    end

    if @stagnant_moves >= 16
      alternatives = safe_moves.reject { |_direction, destination| destination == @previous_player }
      safe_moves = alternatives unless alternatives.empty?
    end

    gc_move = safe_moves.find { |_direction, destination| pickup_at?(destination, :gc) }
    return gc_move.first if gc_move

    goal = preferred_goal
    current_distance = graph_distance(@game.player, goal)
    goal = unfinished_tiles unless safe_moves.any? do |_direction, destination|
      graph_distance(destination, goal) < current_distance
    end
    safe_moves.min_by do |_direction, destination|
      margin = escape_margin(destination, future)
      trapped = margin.zero? && @stagnant_moves < 16 ? 1 : 0
      progress_priority = @game.tiles.fetch(destination) < @game.target ? 0 : 1
      [trapped, graph_distance(destination, goal), progress_priority, -margin]
    end.first
  end

  def legal_moves
    GameState::DIRECTIONS.filter_map do |direction, _delta|
      destination = @game.target_for(direction)
      [direction, destination] if @game.valid?(destination)
    end
  end

  def safe_landing?(destination, future)
    return true if pickup_at?(destination, :gc) || pickup_at?(destination, :shield)
    return true if @game.invulnerable?(future)
    return false if @game.enemies.any? { |enemy| enemy_position(enemy) == destination }

    freeze_until = pickup_at?(destination, :debugger) ? game_time + 4_000 : @game.freeze_until
    return true if future < freeze_until

    moving = @game.enemies.select { |enemy| enemy[:next_at] <= future }
    return false if moving.any? { |enemy| possible_enemy_steps(enemy, destination).include?(destination) }
    return false if spawn_possible?(future, destination) && destination[0] == GameState::ROWS - 1 &&
                    @game.level >= 2 && moving.any?

    true
  end

  def collision_risk(destination, future)
    return 0 if pickup_at?(destination, :gc) || pickup_at?(destination, :shield) || @game.invulnerable?(future)

    risk = @game.enemies.sum do |enemy|
      next 10.0 if enemy_position(enemy) == destination
      next 0 unless enemy_moves_by?(enemy, future)

      choices = possible_enemy_steps(enemy, destination)
      choices.include?(destination) ? 1.0 / choices.length : 0
    end
    risk += 1 if spawn_possible?(future, destination) && destination[0] == GameState::ROWS - 1
    risk
  end

  def safe_to_wait?
    future = game_time + WAIT_LOOKAHEAD_MS
    return true if @game.invulnerable?(future) || future < @game.freeze_until
    return false if @game.enemies.any? { |enemy| enemy_position(enemy) == @game.player }

    moving = @game.enemies.select { |enemy| enemy_moves_by?(enemy, future) }
    return false if moving.any? { |enemy| possible_enemy_steps(enemy, @game.player).include?(@game.player) }
    return false if spawn_possible?(future, @game.player) && @game.player[0] == GameState::ROWS - 1 && moving.any?

    true
  end

  def escape_margin(destination, future)
    next_landing = future + JUMP_TIME + NEXT_TICK_SLACK_MS
    spawned = spawn_possible?(future, destination) ? possible_spawn_positions : []
    legal_destinations(destination).count do |next_position|
      next false if spawned.include?(next_position)

      @game.enemies.none? do |enemy|
        if enemy_moves_by?(enemy, future)
          possible_enemy_steps(enemy, destination).include?(next_position)
        else
          enemy_position(enemy) == next_position ||
            (enemy_moves_by?(enemy, next_landing) && possible_enemy_steps(enemy, next_position).include?(next_position))
        end
      end
    end
  end

  def possible_spawn_positions
    positions = [[0, 0]]
    positions.concat((0...GameState::ROWS).map { |column| [GameState::ROWS - 1, column] }) if @game.level >= 2
    positions
  end

  def preferred_goal
    return [[@game.pickup.values_at(:row, :column)]] if @game.pickup && @game.enemies.any? && @stagnant_moves < 16

    unfinished_tiles
  end

  def unfinished_tiles
    @game.tiles.filter_map { |position, value| position if value < @game.target }
  end

  def graph_distance(start, goals)
    return 0 if goals.include?(start)

    queue = [[start, 0]]
    visited = { start => true }
    until queue.empty?
      position, distance = queue.shift
      legal_destinations(position).each do |destination|
        next if visited[destination]
        return distance + 1 if goals.include?(destination)

        visited[destination] = true
        queue << [destination, distance + 1]
      end
    end
    GameState::ROWS * 2
  end

  def legal_destinations(position)
    GameState::DIRECTIONS.values.filter_map do |delta|
      destination = [position[0] + delta[0], position[1] + delta[1]]
      destination if @game.valid?(destination)
    end
  end

  def enemy_moves_by?(enemy, future)
    future >= @game.freeze_until && enemy[:next_at] <= future
  end

  def possible_enemy_steps(enemy, player = nil)
    origin = enemy_position(enemy)
    unless enemy[:kind] == :exception
      return [[origin[0] + 1, origin[1]], [origin[0] + 1, origin[1] + 1]].select do |position|
        @game.valid?(position)
      end
    end

    choices = legal_destinations(origin)
    return choices unless player

    nearest = choices.map { |position| distance(position, player) }.min
    choices.select { |position| distance(position, player) == nearest }
  end

  def enemy_position(enemy)
    [enemy[:row], enemy[:column]]
  end

  def distance(first, second)
    (first[0] - second[0]).abs + (first[1] - second[1]).abs
  end

  def pickup_at?(position, kind)
    @game.pickup && @game.pickup[:kind] == kind && @game.pickup.values_at(:row, :column) == position
  end

  def available_rescue_direction
    return :up_left if @game.player == [4, 0] && @game.rescues[:left]
    return :up_right if @game.player == [4, 4] && @game.rescues[:right]
  end

  def spawn_possible?(future, destination)
    future >= @game.freeze_until && destination != [0, 0] && @game.enemies.length < @game.enemy_cap &&
      future - @last_spawn_at >= spawn_interval
  end

  def spawn_interval
    base = [3_000 - ((@game.level - 1) * 75), 1_500].max
    (base * GameState::DIFFICULTIES.fetch(@game.difficulty)[:spawn]).to_i
  end

  def respawning?
    instance_variable_defined?(:@respawn) && !@respawn.nil?
  end

end
