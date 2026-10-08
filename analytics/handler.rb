# frozen_string_literal: true
require "json"
require "base64"

class AnalyticsHandler
  METRICS = {
    "page_view" => "PageViews", "session_start" => "Sessions",
    "game_start" => "GameStarts", "game_over" => "GameOvers",
    "victory" => "Victories", "runtime_error" => "RuntimeErrors",
    "engagement" => "ActivePlaySeconds"
  }.freeze

  DIAGNOSTIC_VALUES = {
    "browser" => %w[Chrome Safari Firefox Edge Opera unknown],
    "errorType" => %w[TypeError ReferenceError RangeError SyntaxError CompileError LinkError RuntimeError NoMethodError NameError ArgumentError LoadError StandardError Error unknown],
    "phase" => %w[assets runtime-download runtime-compile runtime-start gameplay unknown],
    "source" => %w[game.rb web/gosu.rb web/app.js web/analytics.js unknown]
  }.freeze

  def call(event:, context: nil)
    return response(405) unless event.dig("requestContext", "http", "method") == "POST"
    return response(415) unless event.fetch("headers", {}).any? { |key, value| key.downcase == "content-type" && value.to_s.split(";").first == "application/json" }
    body = event.fetch("body", "")
    return response(413) if body.bytesize > 2048
    body = Base64.strict_decode64(body) if event["isBase64Encoded"]
    data = JSON.parse(body)
    return response(422) unless data.is_a?(Hash) && (data.keys - %w[event device referrer seconds diagnostics]).empty?
    metric = METRICS[data["event"]]
    return response(422) unless metric && %w[desktop mobile].include?(data["device"])
    referrer = data["referrer"]
    return response(422) unless referrer.is_a?(String) && referrer.match?(/\A(?:direct|[a-z0-9.-]{1,253})\z/)
    seconds = data["seconds"]
    if data["event"] == "engagement"
      return response(422) unless seconds.is_a?(Integer) && seconds.between?(1, 3600)
    else
      return response(422) if data.key?("seconds")
    end
    diagnostics = data["diagnostics"]
    if data.key?("diagnostics")
      return response(422) unless data["event"] == "runtime_error" && valid_diagnostics?(diagnostics)
    end
    # Log only validated, bounded attributes; never log the request or its headers.
    puts JSON.generate({
      "_aws" => { "Timestamp" => (Time.now.to_f * 1000).to_i,
                  "CloudWatchMetrics" => [{ "Namespace" => "RaiBert/Usage", "Dimensions" => [["Site"]],
                    "Metrics" => [{ "Name" => metric, "Unit" => metric == "ActivePlaySeconds" ? "Seconds" : "Count" }] }] },
      "Site" => "raibert.lol", metric => seconds || 1,
      "event" => data["event"], "device" => data["device"], "referrer" => referrer
    }.merge(diagnostics ? { "diagnostics" => diagnostics } : {}))
    response(204)
  rescue JSON::ParserError, ArgumentError
    response(400)
  end

  private

  def valid_diagnostics?(value)
    return false unless value.is_a?(Hash) && value.keys.sort == (DIAGNOSTIC_VALUES.keys + %w[release runtime line]).sort
    return false unless DIAGNOSTIC_VALUES.all? { |key, allowed| allowed.include?(value[key]) }
    return false unless value["release"] == "2026-10-08.1"
    return false unless value["runtime"].is_a?(String) && value["runtime"].match?(/\A(?:unknown|ruby-[a-f0-9]{16}\.wasm)\z/)
    value["line"].is_a?(Integer) && value["line"].between?(0, 99_999)
  end

  def response(status)
    { statusCode: status, headers: { "cache-control" => "no-store" }, body: "" }
  end
end

def handler(event:, context:)
  AnalyticsHandler.new.call(event: event, context: context)
end
