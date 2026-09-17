# frozen_string_literal: true

# The browser build puts this directory first on $LOAD_PATH, so `require "gosu"`
# resolves to this deliberately small compatibility layer instead of native Gosu.
require "json"
require "js"

module Gosu
  KEY_NAMES = [
    *("a".."z"), *("0".."9"), *(1..12).map { |number| "f#{number}" },
    *%w[left right up down return escape space tab backspace insert delete home end page_up page_down
        left_shift right_shift left_control right_control left_alt right_alt left_meta right_meta
        caps_lock num_lock scroll_lock print_screen pause context_menu
        numpad_0 numpad_1 numpad_2 numpad_3 numpad_4 numpad_5 numpad_6 numpad_7 numpad_8 numpad_9
        numpad_delete numpad_divide numpad_minus numpad_multiply numpad_plus
        semicolon comma period slash backslash iso minus equals left_bracket right_bracket backtick apostrophe]
  ].freeze
  KEY_NAMES.each { |name| const_set("KB_#{name.upcase}", name) }

  class Color
    attr_reader :alpha, :red, :green, :blue

    def initialize(value)
      value = Integer(value)
      @alpha = (value >> 24) & 0xff
      @red = (value >> 16) & 0xff
      @green = (value >> 8) & 0xff
      @blue = value & 0xff
    end

    def to_i
      (@alpha << 24) | (@red << 16) | (@green << 8) | @blue
    end

    WHITE = new(0xff_ffffff)
  end

  class << self
    def bridge
      @bridge ||= JS.global[:RaiBertWeb]
    end

    def milliseconds
      bridge.call(:milliseconds).to_i
    end

    def commands
      @commands ||= []
    end

    def flush
      bridge.call(:render, JSON.generate(commands))
      commands.clear
    end

    def draw_rect(x, y, width, height, color, z = 0)
      queue("rect", z, x: x, y: y, width: width, height: height, color: color_value(color))
    end

    def draw_line(x1, y1, color1, x2, y2, color2, z = 0)
      queue("line", z, x1: x1, y1: y1, color1: color_value(color1),
            x2: x2, y2: y2, color2: color_value(color2))
    end

    def draw_quad(x1, y1, color1, x2, y2, color2, x3, y3, color3, x4, y4, color4, z = 0)
      queue("quad", z, points: [x1, y1, x2, y2, x3, y3, x4, y4],
            colors: [color1, color2, color3, color4].map { |color| color_value(color) })
    end

    def queue(kind, z, **fields)
      commands << fields.merge(kind: kind, z: z, order: commands.length)
    end

    def color_value(color)
      color.is_a?(Color) ? color.to_i : Integer(color)
    end

    def asset_url(path)
      path = path.to_s
      index = path.index("assets/")
      raise ArgumentError, "Asset is outside the public assets directory: #{path}" unless index

      "/#{path[index..]}"
    end
  end

  class Window
    attr_writer :caption

    def initialize(width, height, fullscreen: false)
      raise ArgumentError, "The browser canvas cannot enter native fullscreen" if fullscreen

      @closed = false
      Gosu.bridge.call(:configure, width, height)
    end

    def show
      frame = proc do
        next if @closed

        safely do
          update
          draw
          Gosu.flush
        end
      end
      key = proc { |name| safely { button_down(name.to_s) } unless @closed }
      action = proc { |name| safely { press(name.to_s.to_sym) } unless @closed }
      Gosu.bridge.call(:start, frame, key, action, JSON.generate(KEY_NAMES))
      self
    end

    def close
      @closed = true
      Gosu.bridge.call(:stop)
    end

    private

    def safely
      yield
    rescue StandardError => error
      Gosu.bridge.call(:fail, "#{error.class}: #{error.message}\n#{error.backtrace&.first(8)&.join("\n")}")
      close
    end
  end

  class Image
    attr_reader :width, :height

    def self.load_tiles(path, tile_width, tile_height, tileable: false)
      url = Gosu.asset_url(path)
      dimensions = Gosu.bridge.call(:imageSize, url).to_s.split(",").map(&:to_i)
      raise "Image was not preloaded: #{url}" unless dimensions.length == 2 && dimensions.all?(&:positive?)

      columns = dimensions[0] / tile_width
      rows = dimensions[1] / tile_height
      Array.new(columns * rows) do |index|
        new(path, source: [(index % columns) * tile_width, (index / columns) * tile_height,
                           tile_width, tile_height])
      end
    end

    def initialize(path, source: nil)
      @url = Gosu.asset_url(path)
      dimensions = Gosu.bridge.call(:imageSize, @url).to_s.split(",").map(&:to_i)
      raise "Image was not preloaded: #{@url}" unless dimensions.length == 2 && dimensions.all?(&:positive?)

      @source = source || [0, 0, *dimensions]
      @width = @source[2]
      @height = @source[3]
    end

    def draw(x, y, z, scale_x = 1, scale_y = 1, color = Color::WHITE)
      Gosu.queue("image", z, url: @url, source: @source, x: x, y: y,
                 width: @width * scale_x, height: @height * scale_y,
                 color: Gosu.color_value(color))
    end
  end

  class Font
    def initialize(size, name: nil)
      @size = size
      @family = name || "monospace"
    end

    def text_width(text)
      Gosu.bridge.call(:textWidth, @size, @family, text.to_s).to_f
    end

    def draw_text(text, x, y, z, scale_x = 1, scale_y = 1, color = Color::WHITE)
      Gosu.queue("text", z, text: text.to_s, x: x, y: y, size: @size,
                 family: @family, scale_x: scale_x, scale_y: scale_y,
                 color: Gosu.color_value(color))
    end
  end

  class Sample
    def initialize(path)
      @url = Gosu.asset_url(path)
    end

    def play(volume = 1, speed = 1, looping = false)
      Gosu.bridge.call(:playEffect, @url, volume, speed, looping)
    end
  end

  class Song
    class << self
      attr_accessor :current_song
    end

    attr_accessor :volume

    def initialize(path)
      @url = Gosu.asset_url(path)
      @volume = 1.0
    end

    def play(looping = false)
      self.class.current_song&.stop unless self.class.current_song.equal?(self)
      self.class.current_song = self
      Gosu.bridge.call(:playSong, @url, @volume, looping)
      self
    end

    def pause
      Gosu.bridge.call(:pauseSong) if self.class.current_song.equal?(self)
    end

    def stop
      Gosu.bridge.call(:stopSong) if self.class.current_song.equal?(self)
      self.class.current_song = nil if self.class.current_song.equal?(self)
    end
  end
end

# Browser assets live outside WASI's virtual filesystem. The application only
# uses File.exist? to make optional browser-served art and audio conditional.
# ponytail: keep this narrow asset exception; replace it if game code starts
# reading asset bytes through Ruby's File API.
module RaiBertBrowserAssets
  def exist?(path)
    path.to_s.include?("/assets/") || super
  end
end
File.singleton_class.prepend(RaiBertBrowserAssets)
