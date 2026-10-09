# frozen_string_literal: true
require "json"
require "digest"
require "zlib"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

def check(condition, message)
  raise message unless condition
end

Dir.mktmpdir("raibert-deploy-") do |directory|
  site = File.join(directory, "site")
  FileUtils.mkdir_p([File.join(site, "web"), File.join(directory, "bin")])
  %w[index.html 404.html web/assets.json web/app.js web/app.css web/input.js web/artwork.js web/analytics.js web/high-score.js].each do |name|
    File.write(File.join(site, name), "fixture")
  end
  File.write(File.join(site, "web/assets.json"), JSON.generate(images: ["/web/artwork.js"], effects: [], initialSong: "/web/input.js"))
  runtime = {}
  { "javascript" => ["js", "export const runtime = true;"], "webassembly" => ["wasm", "\0asm\1\0\0\0"] }.each do |key, (extension, bytes)|
    filename = "ruby-#{Digest::SHA256.hexdigest(bytes)[0, 16]}.#{extension}"
    path = File.join(site, "web", filename)
    extension == "wasm" ? Zlib::GzipWriter.open(path) { |gzip| gzip.write(bytes) } : File.write(path, bytes)
    runtime[key] = filename
  end
  File.write(File.join(site, "web/runtime.json"), JSON.generate(runtime))
  fake = File.join(directory, "bin/aws")
  File.write(fake, "#!#{RbConfig.ruby}\n" + <<~'FAKE')
    require "json"
    File.open(ENV.fetch("AWS_CALLS"), "a") { |file| file.puts(JSON.generate(ARGV)) }
    exit 19 if ENV["FAIL_UPLOAD"] && ARGV.any? { |argument| argument.end_with?(ENV["FAIL_UPLOAD"]) }
    if ARGV[0] == "cloudformation"
      puts ARGV.join.include?("SiteBucketName") ? "fixture-bucket" : "fixture-distribution"
    elsif ARGV[0] == "cloudfront"
      puts "fixture-invalidation"
    end
  FAKE
  File.chmod(0o755, fake)
  log = File.join(directory, "calls.jsonl")
  env = { "PATH" => "#{File.dirname(fake)}:#{ENV.fetch('PATH')}", "AWS_CALLS" => log }
  deploy = File.expand_path("../script/deploy_site", __dir__)
  run = lambda do |extra = {}|
    File.write(log, "")
    output, status = Open3.capture2e(env.merge(extra), deploy, site)
    [File.readlines(log).map { |line| JSON.parse(line) }, status, output]
  end
  calls, status, output = run.call
  check(status.success?, output)
  writes = calls.select { |args| args[0] == "s3" }
  runtime.each_value do |name|
    upload = writes.find { |args| args[1] == "cp" && args[2].end_with?(name) }
    check(upload && upload.include?("public,max-age=31536000,immutable"), "runtime must be immutable")
    if name.end_with?("wasm")
      check(upload.include?("gzip") && upload.include?("application/wasm"), "first WASM upload needs final headers")
    end
  end
  check(writes.first(2).all? { |args| args[2].include?("/ruby-") }, "runtime uploads precede all publication")
  check(calls.none? { |args| args.include?("--delete") || args[1] == "rm" }, "old client artifacts must be retained")
  sync = writes.find { |args| args[1] == "sync" }
  %w[web/*.wasm web/*.js web/runtime.json web/assets.json index.html].each do |pattern|
    check(sync.each_cons(2).include?(["--exclude", pattern]), "sync must exclude #{pattern}")
  end
  check(writes.last[2].end_with?("/index.html"), "entry page must publish last")
  dependency = writes.index { |args| args[2].end_with?("/web/artwork.js") }
  entry = writes.index { |args| args[2].end_with?("/web/app.js") }
  check(dependency < entry, "module dependencies must precede app")
  [runtime.fetch("webassembly"), "/web/artwork.js", "/site/"].each do |failure|
    failed, status, = run.call("FAIL_UPLOAD" => failure)
    check(!status.success?, "upload failure must abort deployment")
    check(failed.none? { |args| args[0] == "cloudfront" || (args[1] == "cp" && args[2].end_with?("/runtime.json", "/index.html")) }, "failed dependencies must not publish manifests or invalidate")
  end
  File.delete(File.join(site, "web/artwork.js"))
  calls, status, = run.call
  check(!status.success? && calls.empty?, "missing asset must fail before AWS calls")
  File.write(File.join(site, "web/artwork.js"), "fixture")
  File.write(File.join(site, "web", runtime.fetch("webassembly")), "broken gzip")
  calls, status, = run.call
  check(!status.success? && calls.empty?, "invalid artifact must fail before AWS calls")
end
puts "Deployment publication order, retention, headers, and failure checks passed"
