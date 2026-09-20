# frozen_string_literal: true

Connection = Data.define(:id, :from, :direction, :to, :kind, :path, :layer)

class BoardLayout
  DIRECTIONS = {
    up_left: [-1, -1], up_right: [-1, 0],
    down_left: [1, 0], down_right: [1, 1]
  }.freeze
  INVERSE = {
    up_left: :down_right, up_right: :down_left,
    down_left: :up_right, down_right: :up_left
  }.freeze

  attr_reader :id, :name, :tiles, :start, :rescues, :ribbons

  def initialize(id:, name:, tiles:, start:, rescues:, ribbons: [])
    @id = id
    @name = name
    @tiles = tiles.map(&:freeze).uniq.freeze
    @tile_lookup = @tiles.to_h { |position| [position, true] }.freeze
    @start = start.freeze
    @rescues = rescues.transform_keys { |position, direction| [position.freeze, direction] }.freeze
    @ribbons = ribbons.map do |ribbon|
      {
        from: ribbon.fetch(:from).freeze,
        to: ribbon.fetch(:to).freeze,
        direction: ribbon.fetch(:direction),
        path: ribbon.fetch(:path).map(&:freeze).freeze,
        layer: ribbon.fetch(:layer, 0)
      }.freeze
    end.freeze
    @special_connections = build_special_connections.freeze
    validate!
    freeze
  end

  def include?(position)
    @tile_lookup.key?(position)
  end

  def connection(position, direction)
    key = [position, direction]
    return @special_connections[key] if @special_connections.key?(key)

    delta = DIRECTIONS.fetch(direction)
    destination = [position[0] + delta[0], position[1] + delta[1]]
    return unless include?(destination)

    edge = [position, destination].sort
    Connection.new("step:#{edge.flatten.join(':')}", position, direction, destination, :step,
                   [position, destination].freeze, 0)
  end

  def neighbors(position)
    DIRECTIONS.filter_map do |direction, _delta|
      connection = connection(position, direction)
      [direction, connection.to] if connection
    end
  end

  def rescue_for(position, direction)
    @rescues[[position, direction]]
  end

  def fall_target(position, direction)
    delta = DIRECTIONS.fetch(direction)
    [position[0] + delta[0], position[1] + delta[1]]
  end

  def farthest_tiles
    distances = graph_distances(@start)
    farthest = distances.values.max
    distances.filter_map { |position, distance| position if distance == farthest }
  end

  def projected_bounds
    points = @tiles + @ribbons.flat_map { |ribbon| ribbon.fetch(:path) }
    xs = points.map { |row, column| column - row / 2.0 }
    ys = points.map(&:first)
    [xs.min, xs.max, ys.min, ys.max]
  end

  private

  def build_special_connections
    @ribbons.each_with_index.each_with_object({}) do |(ribbon, index), connections|
      from = ribbon.fetch(:from)
      to = ribbon.fetch(:to)
      direction = ribbon.fetch(:direction)
      inverse = INVERSE.fetch(direction)
      path = ribbon.fetch(:path).map(&:freeze).freeze
      id = "ribbon:#{@id}:#{index}"
      layer = ribbon.fetch(:layer, index)
      connections[[from, direction]] = Connection.new(id, from, direction, to, :ribbon, path, layer)
      connections[[to, inverse]] = Connection.new(id, to, inverse, from, :ribbon, path.reverse.freeze, layer)
    end
  end

  def graph_distances(origin)
    distances = { origin => 0 }
    queue = [origin]
    until queue.empty?
      position = queue.shift
      neighbors(position).each do |_direction, destination|
        next if distances.key?(destination)

        distances[destination] = distances.fetch(position) + 1
        queue << destination
      end
    end
    distances
  end

  def validate!
    raise ArgumentError, "#{@id}: tile count must be 24-32" unless @tiles.length.between?(24, 32)
    raise ArgumentError, "#{@id}: missing start" unless include?(@start)
    raise ArgumentError, "#{@id}: needs two rescues" unless @rescues.values.sort == %i[left right]
    @rescues.each_key do |position, direction|
      raise ArgumentError, "#{@id}: invalid rescue origin" unless include?(position)
      raise ArgumentError, "#{@id}: rescue overlaps a connection" if connection(position, direction)
    end
    @ribbons.each do |ribbon|
      from = ribbon.fetch(:from)
      to = ribbon.fetch(:to)
      direction = ribbon.fetch(:direction)
      raise ArgumentError, "#{@id}: invalid ribbon endpoint" unless include?(from) && include?(to)
      delta = DIRECTIONS.fetch(direction)
      ordinary = [from[0] + delta[0], from[1] + delta[1]]
      raise ArgumentError, "#{@id}: ribbon replaces an ordinary step" if include?(ordinary)
      inverse = INVERSE.fetch(direction)
      reverse_delta = DIRECTIONS.fetch(inverse)
      reverse_ordinary = [to[0] + reverse_delta[0], to[1] + reverse_delta[1]]
      raise ArgumentError, "#{@id}: ribbon reverse replaces an ordinary step" if include?(reverse_ordinary)
    end
    raise ArgumentError, "#{@id}: disconnected board" unless graph_distances(@start).length == @tiles.length
    raise ArgumentError, "#{@id}: cyclic descending flow" if descending_cycle?
    min_x, max_x, min_y, max_y = projected_bounds
    raise ArgumentError, "#{@id}: board exceeds render bounds" if max_x - min_x > 6 || max_y - min_y > 7
  end

  def descending_cycle?
    visited = {}
    active = {}
    visit = lambda do |position|
      return true if active[position]
      return false if visited[position]

      visited[position] = true
      active[position] = true
      cycle = %i[down_left down_right].any? do |direction|
        edge = connection(position, direction)
        edge && visit.call(edge.to)
      end
      active.delete(position)
      cycle
    end
    @tiles.any? { |position| visit.call(position) }
  end
end

module BoardLayouts
  module_function

  COUNTS = [28, 26, 27, 28, 30, 26, 28, 27, 29, 30, 28, 26, 29, 28, 30, 30, 27, 29, 31, 32].freeze
  NAMES = [
    "RUBY MARK", "STEP CUT", "MARQUISE", "PRINCESS CUT", "CROWN AND PAVILION",
    "WINDOWED RUBY", "SPLIT RUBY", "SHARDWHEEL", "SPIRAL FACET", "DOUBLE HALO",
    "FOLDED FACET", "SUSPENDED SHARDS", "INVERTED PAVILION", "MOBIUS GIRDLE", "IMPOSSIBLE CROWN",
    "BRAIDED FACETS", "SHATTERED HALO", "PENROSE PAVILION", "FOLDED CROWN", "RUBY SINGULARITY"
  ].freeze
  RIBBON_COUNTS = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 3, 3, 4].freeze
  MAPS = [
    ["###", "#####", "######", " ######", "  ####", "   ###", "     #"],
    ["###", "####", " ####", " ####", "  ####", "  ####", "   ###"],
    ["###", "####", " ####", " #####", "  ####", "  ####", "   ###"],
    [" #", "####", "####", "#####", " ####", " #####", "   ###", "    ##"],
    ["####", "#####", " ####", " #####", "  ####", "  ####", "   ###", "    #"],
    ["###", "####", " ####", " #####", "  ## #", "  ####", "   ###"],
    ["###", "## #", " ####", " #####", "  ####", "  #####", "   ###", "   #"],
    ["####", " ####", " ####", " ### #", "  ####", "  ####", "   ###"],
    ["####", " ####", " ####", " #####", "  ####", "  ### #", "   ####"],
    [" ##", "####", "####", "#####", "# ###", " #####", "   ###", "    ###"],
    ["###", "####", "####", "#####", " ####", " #####", "   ##", "     #"],
    ["####", " ###", "####", "#####", " ####", "  ###", "   ###"],
    ["####", " ###", "  ####", "  #####", "   ####", "   ## ##", "    ####", "    #"],
    ["###", "###", " ####", " #####", "  ####", "  ### #", "   ###", "   ##"],
    ["####", " ###", "  ####", "  #####", "   ####", "   ####", "    ###", "    ###"],
    ["#####", " #####", "  ###", "  #####", "   ####", "   ####", "    ###", "    #"],
    ["###", " ###", " ###", "#####", " ## #", " #####", "  ####", "    #"],
    ["####", " ####", " # ##", " #####", "  ####", "  #####", "    ###", "     #"],
    ["####", " ####", " # ##", " #####", "  ####", "  #####", "    ###", "     ###"],
    ["#####", " ####", "  ####", "  #####", "   ## #", "    ####", "     ###", "     ####"]
  ].map { |map| map.map(&:freeze).freeze }.freeze

  def build_tiles(level, count)
    tiles = MAPS.fetch(level - 1).flat_map.with_index do |row, row_index|
      row.chars.filter_map.with_index { |cell, column| [row_index, column] if cell == "#" }
    end
    raise "#{level}: expected #{count} tiles, got #{tiles.length}" unless tiles.length == count

    tiles
  end

  def ribbon_specs(id, tiles, count)
    return [] if count.zero?

    used = {}
    candidates = tiles.product(tiles).select do |from, to|
      next false if from == to

      distance = (from[0] - to[0]).abs + (from[1] - to[1]).abs
      distance >= 5
    end.sort_by { |from, to| -((from[0] - to[0]).abs + (from[1] - to[1]).abs) }
    ribbons = []
    candidates.each do |from, to|
      direction = %i[down_right down_left up_right up_left].find do |action|
        inverse = BoardLayout::INVERSE.fetch(action)
        !used[[from, action]] && !used[[to, inverse]] &&
          missing_step?(tiles, from, action) && missing_step?(tiles, to, inverse) &&
          ribbon_flows_downward?(from, to, action)
      end
      next unless direction

      used[[from, direction]] = true
      used[[to, BoardLayout::INVERSE.fetch(direction)]] = true
      bend = ribbons.length.even? ? -1.2 : 1.2
      middle = [(from[0] + to[0]) / 2.0 + bend, (from[1] + to[1]) / 2.0 - bend]
      ribbons << { from: from, to: to, direction: direction, path: [from, middle, to], layer: ribbons.length + 1 }
      break if ribbons.length == count
    end
    raise "#{id}: unable to place ribbons" unless ribbons.length == count

    ribbons
  end

  def missing_step?(tiles, position, direction)
    delta = BoardLayout::DIRECTIONS.fetch(direction)
    !tiles.include?([position[0] + delta[0], position[1] + delta[1]])
  end

  def ribbon_flows_downward?(from, to, direction)
    if %i[down_left down_right].include?(direction)
      to[0] > from[0]
    else
      from[0] > to[0]
    end
  end

  def rescue_specs(tiles, ribbons)
    occupied = ribbons.flat_map do |ribbon|
      [[ribbon.fetch(:from), ribbon.fetch(:direction)],
       [ribbon.fetch(:to), BoardLayout::INVERSE.fetch(ribbon.fetch(:direction))]]
    end.to_h { |key| [key, true] }
    center_row = tiles.map(&:first).sum.to_f / tiles.length
    candidates = tiles.flat_map do |position|
      BoardLayout::DIRECTIONS.keys.filter_map do |direction|
        [position, direction] if missing_step?(tiles, position, direction) && !occupied[[position, direction]]
      end
    end
    left = candidates.min_by { |(row, column), _direction| [(row - center_row).abs, column - row / 2.0] }
    right = candidates.min_by { |(row, column), _direction| [(row - center_row).abs, -(column - row / 2.0)] }
    right = candidates.find { |candidate| candidate != left } if right == left
    { left => :left, right => :right }
  end

  LAYOUTS = COUNTS.each_with_index.map do |count, index|
    level = index + 1
    tiles = build_tiles(level, count)
    ribbons = ribbon_specs(level, tiles, RIBBON_COUNTS[index])
    start = level == 1 ? [0, 1] : tiles.min_by { |row, column| [row, (column - row / 2.0).abs] }
    BoardLayout.new(id: level, name: NAMES[index], tiles: tiles, start: start,
                    rescues: rescue_specs(tiles, ribbons), ribbons: ribbons)
  end.freeze

  raise "board layouts must be unique" unless LAYOUTS.map { |layout| layout.tiles.sort }.uniq.length == LAYOUTS.length

  def fetch(level)
    raise IndexError, "level must be 1-#{LAYOUTS.length}" unless level.is_a?(Integer) && level.between?(1, LAYOUTS.length)

    LAYOUTS.fetch(level - 1)
  end
end
