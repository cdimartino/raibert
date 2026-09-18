# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "tmpdir"
require "zlib"

ROOT = File.expand_path("..", __dir__)

def assert(condition, message)
  raise "Site check failed: #{message}" unless condition
end

infrastructure = File.read(File.join(ROOT, "infra/site.yml"))
assert(infrastructure.include?("OriginAccessControlOriginType: lambda") && infrastructure.include?("AuthType: AWS_IAM"), "Lambda origin is private and signed by CloudFront")
assert(infrastructure.include?("Scope: CLOUDFRONT") && infrastructure.include?("RateBasedStatement:"), "CloudFront WAF rate limits the API")
assert(infrastructure.include?("PointInTimeRecoveryEnabled: true") && infrastructure.scan("DeletionPolicy: Retain").length >= 3, "stateful resources are protected and retained")
assert(infrastructure.include?("ReservedConcurrentExecutions: 8") && infrastructure.include?("RetentionInDays: 30"), "Lambda concurrency and logs are bounded")
assert(infrastructure.include?("DynamoDBCrudPolicy:") && !infrastructure.include?("Action: \"*\""), "leaderboard role is scoped to its table")

Dir.mktmpdir("raibert-site-") do |destination|
  output, status = Open3.capture2e(File.join(ROOT, "script/package_site"), destination)
  assert(status.success?, "package script failed: #{output}")

  %w[index.html 404.html web/app.js web/app.css web/runtime.json assets/art/build.png assets/music/build.wav].each do |path|
    assert(File.file?(File.join(destination, path)), "package contains #{path}")
  end

  runtime = JSON.parse(File.read(File.join(destination, "web/runtime.json")))
  javascript = File.join(destination, "web", runtime.fetch("javascript"))
  webassembly = File.join(destination, "web", runtime.fetch("webassembly"))
  assert(File.file?(javascript), "runtime JavaScript exists")
  assert(File.file?(webassembly), "runtime WebAssembly exists")

  original = File.join(ROOT, "public/web", runtime.fetch("webassembly"))
  unpacked_digest = Digest::SHA256.new
  Zlib::GzipReader.open(webassembly) do |gzip|
    unpacked_digest << gzip.read(1024 * 1024) until gzip.eof?
  end
  assert(unpacked_digest.hexdigest == Digest::SHA256.file(original).hexdigest, "packaged WebAssembly expands to the committed runtime")
  assert(File.size(webassembly) < File.size(original), "packaged WebAssembly is compressed")

  assets = JSON.parse(File.read(File.join(destination, "web/assets.json")))
  manifest_urls = assets.fetch("images") + Array(assets["effects"]) + Array(assets["effect"]) + [assets.fetch("initialSong")]
  manifest_urls.each do |url|
    assert(File.file?(File.join(destination, url.delete_prefix("/"))), "manifest target #{url} exists")
  end
end

puts "Static site package check passed"
