# frozen_string_literal: true
require "stringio"
require_relative "../analytics/handler"
def assert(condition, message)
  raise message unless condition
end
handler = AnalyticsHandler.new
base = { "event" => "page_view", "device" => "desktop", "referrer" => "direct" }
def request(data)
  { "requestContext" => { "http" => { "method" => "POST" } }, "headers" => { "content-type" => "application/json" }, "body" => JSON.generate(data) }
end
original_stdout = $stdout
begin
  $stdout = StringIO.new
  assert(handler.call(event: request(base))[:statusCode] == 204, "accept valid event")
  log = JSON.parse($stdout.string)
  assert(log["PageViews"] == 1 && log.dig("_aws", "CloudWatchMetrics", 0, "Dimensions") == [["Site"]], "emit bounded aggregate metric")
  [base.merge("event" => "unknown"), base.merge("initials" => "ABC"), base.merge("referrer" => "https://example.com/private"), base.merge("seconds" => 3), [], base.merge("device" => "other")].each do |data|
    assert(handler.call(event: request(data))[:statusCode] == 422, "reject invalid or identifying attributes")
  end
  assert(handler.call(event: request(base.merge("event" => "engagement", "seconds" => 60)))[:statusCode] == 204, "accept play duration")
  [0, 3601, "60", 1.5].each do |seconds|
    assert(handler.call(event: request(base.merge("event" => "engagement", "seconds" => seconds)))[:statusCode] == 422, "bound play duration")
  end
  assert(handler.call(event: request(base).merge("body" => "x" * 2049))[:statusCode] == 413, "bound body")
  assert(handler.call(event: request(base).merge("body" => "{"))[:statusCode] == 400, "reject invalid JSON")
  assert(handler.call(event: request(base).merge("isBase64Encoded" => true, "body" => Base64.strict_encode64(JSON.generate(base))))[:statusCode] == 204, "decode Lambda base64 body")
  assert(handler.call(event: request(base).merge("requestContext" => { "http" => { "method" => "GET" } }))[:statusCode] == 405, "no read API")
ensure
  $stdout = original_stdout
end
puts "Analytics collector checks passed"
