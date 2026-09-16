# frozen_string_literal: true

require "rack"
require "rack/mock"
require "json"

def assert(condition, message)
  raise "Rack check failed: #{message}" unless condition
end

app, = Rack::Builder.parse_file(File.expand_path("../config.ru", __dir__))
request = Rack::MockRequest.new(app)

root = request.get("/")
assert(root.ok?, "root serves the web application")
assert(root["content-type"].start_with?("text/html"), "root is HTML")
assert(root.body.include?('<link rel="icon" href="data:,">'), "root supplies an inline favicon")

image = request.get("/assets/art/build.png")
assert(image.ok?, "assets are available under /assets")
assert(image["content-type"].start_with?("image/png"), "assets have their correct MIME type")

audio = request.get("/assets/music/build.wav")
assert(audio.ok?, "audio is available under /assets")
assert(audio["content-type"].start_with?("audio/"), "audio has its correct MIME type")

manifest_response = request.get("/web/runtime.json")
assert(manifest_response.ok?, "runtime manifest is served")
manifest = JSON.parse(manifest_response.body)
artifacts = {
  "JavaScript" => [manifest.fetch("javascript"), /\A(?:application|text)\/javascript/],
  "WebAssembly" => [manifest.fetch("webassembly"), "application/wasm"]
}
artifacts.each do |kind, (file, content_type)|
  response = request.get("/web/#{file}")
  assert(response.ok?, "#{kind} build artifact is served")
  assert(content_type === response["content-type"], "#{kind} has its correct MIME type")
  assert(response["cache-control"] == "public, max-age=31536000, immutable", "#{kind} is cached immutably")
end

javascript = artifacts.fetch("JavaScript").first
compressed = request.get("/web/#{javascript}", "HTTP_ACCEPT_ENCODING" => "gzip")
assert(compressed["content-encoding"] == "gzip", "runtime supports gzip compression")
assert(compressed["vary"].split(",").map(&:strip).include?("Accept-Encoding"), "compressed runtime varies by encoding")

missing = request.get("/missing")
assert(missing.status == 404, "unknown routes return 404")

["/game.rb", "/Gemfile", "/../game.rb", "/%2e%2e/game.rb", "/assets/../game.rb", "/assets/%2e%2e/game.rb"].each do |path|
  response = request.get(path)
  assert(response.status != 200, "#{path} cannot expose repository files")
end

puts "Rack check passed"
