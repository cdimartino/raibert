# frozen_string_literal: true

require_relative "../lib/board_layouts"

def board_assert(condition, message)
  raise "Board layout check failed: #{message}" unless condition
end

layouts = BoardLayouts::LAYOUTS
board_assert(layouts.length == 20, "catalog contains all twenty levels")
board_assert(layouts.map(&:name) == BoardLayouts::NAMES, "catalog preserves the campaign names")
board_assert(layouts.map { |board| board.tiles.length } == BoardLayouts::COUNTS,
             "each board has its specified tile count")
board_assert(layouts.map { |board| board.tiles.sort }.uniq.length == layouts.length,
             "every board has a unique canonical shape")

layouts.each_with_index do |board, index|
  expected_ribbons = BoardLayouts::RIBBON_COUNTS.fetch(index)
  board_assert(board.frozen? && board.tiles.frozen? && board.rescues.frozen?,
               "level #{index + 1} is immutable")
  board_assert(board.ribbons.frozen? && board.ribbons.all? { |ribbon| ribbon.frozen? && ribbon.fetch(:path).frozen? },
               "level #{index + 1} ribbon metadata is immutable")
  board_assert(board.include?(board.start), "level #{index + 1} start is on the board")
  board_assert(board.rescues.values.sort == %i[left right], "level #{index + 1} has both rescues")
  board_assert(board.ribbons.length == expected_ribbons, "level #{index + 1} has its ribbon tier")
  min_x, max_x, min_y, max_y = board.projected_bounds
  board_assert(max_x - min_x <= 6 && max_y - min_y <= 7, "level #{index + 1} fits render bounds")
  board_assert(board.farthest_tiles.all? { |tile| board.include?(tile) },
               "level #{index + 1} farthest tiles belong to the board")

  reached = { board.start => true }
  queue = [board.start]
  until queue.empty?
    position = queue.shift
    board.neighbors(position).each do |direction, destination|
      connection = board.connection(position, direction)
      reverse = board.connection(destination, BoardLayout::INVERSE.fetch(direction))
      board_assert(connection.to == destination, "level #{index + 1} neighbor has a connection")
      board_assert(reverse&.to == position, "level #{index + 1} connection is reciprocal")
      next if reached[destination]

      reached[destination] = true
      queue << destination
    end
  end
  board_assert(reached.length == board.tiles.length, "level #{index + 1} is fully connected")

  board.rescues.each_key do |position, direction|
    board_assert(board.connection(position, direction).nil?, "level #{index + 1} rescue is an open edge")
    board_assert(board.rescue_for(position, direction), "level #{index + 1} rescue is addressable")
    board_assert(board.fall_target(position, direction).is_a?(Array), "level #{index + 1} has a fall target")
  end

  board.ribbons.each do |ribbon|
    connection = board.connection(ribbon.fetch(:from), ribbon.fetch(:direction))
    board_assert(connection.kind == :ribbon && connection.path.length >= 3,
                 "level #{index + 1} ribbon supplies an animation path")
  end
end

ruby_mark = BoardLayouts.fetch(1)
board_assert(ruby_mark.tiles.group_by(&:first).sort.map { |_row, tiles| tiles.length } == [3, 5, 6, 6, 4, 3, 1],
             "Ruby Mark uses the specified seven bands")
board_assert(ruby_mark.start == [0, 1], "Ruby Mark starts in the top-band center")

begin
  BoardLayouts.fetch(21)
  raise "Board layout check failed: level twenty-one was accepted"
rescue IndexError
  # expected
end

puts "Rai*bert board layout check passed"
