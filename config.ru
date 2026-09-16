# frozen_string_literal: true

require "rack"
require "rack/deflater"

use Rack::Deflater,
  include: %w[application/json application/wasm text/css text/html text/javascript text/plain],
  if: ->(_env, status, _headers, _body) { status == 200 },
  sync: false

root = File.expand_path(__dir__)
not_found = lambda do |_env|
  body = "Not Found\n"
  [404, { "content-type" => "text/plain; charset=utf-8", "content-length" => body.bytesize.to_s }, [body]]
end

map "/assets" do
  run Rack::Files.new(File.join(root, "assets"))
end

map "/" do
  run Rack::Static.new(
    not_found,
    urls: ["/"],
    root: File.join(root, "public"),
    index: "index.html",
    header_rules: [
      [%r{\A/web/ruby-[0-9a-f]{16}\.(?:js|wasm)\z}, { "cache-control" => "public, max-age=31536000, immutable" }]
    ]
  )
end
