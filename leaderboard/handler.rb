# frozen_string_literal: true

require "aws-sdk-dynamodb"
require "json"
require "securerandom"
require "time"
require_relative "leaderboard"

class LeaderboardHandler
  BOARD_KEY = { "pk" => "BOARD", "sk" => "CURRENT" }.freeze

  def initialize(table: ENV.fetch("LEADERBOARD_TABLE"), client: Aws::DynamoDB::Client.new)
    @table = table
    @client = client
  end

  def call(event:, context: nil)
    method = event.dig("requestContext", "http", "method") || event["httpMethod"]
    return response(200, board) if method == "GET"
    return response(405, error: "method_not_allowed") unless method == "POST"

    return response(415, error: "application_json_required") unless event.dig("headers")&.any? { |key, value| key.downcase == "content-type" && value.to_s.split(";").first == "application/json" }
    body = event.fetch("body", "")
    return response(413, error: "body_too_large") if body.bytesize > 1024

    submission = Leaderboard.validate_submission(JSON.parse(body))
    submit(submission)
  rescue JSON::ParserError
    response(400, error: "invalid_json")
  rescue Leaderboard::ValidationError => error
    response(422, error: "invalid_submission", message: error.message)
  rescue Aws::DynamoDB::Errors::ServiceError => error
    warn({ level: "error", event: "dynamodb_failure", type: error.class.name }.to_json)
    response(503, error: "temporarily_unavailable")
  end

  private

  def board
    item = @client.get_item(table_name: @table, key: BOARD_KEY, consistent_read: true).item
    entries = item&.fetch("entries", []) || []
    Leaderboard.response(entries).merge(version: item&.fetch("version", 0) || 0)
  end

  def submit(submission)
    existing = @client.get_item(table_name: @table, key: { "pk" => "RUN", "sk" => submission.fetch("runId") }, consistent_read: true).item
    return response(200, board.merge(duplicate: true)) if existing

    4.times do
      current = @client.get_item(table_name: @table, key: BOARD_KEY, consistent_read: true).item || { "version" => 0, "entries" => [] }
      entry = submission.merge("id" => SecureRandom.uuid, "achievedAt" => Time.now.utc.iso8601)
      ranked = Leaderboard.rank(current.fetch("entries", []) + [entry])
      rank = ranked.index { |candidate| candidate.fetch("id") == entry.fetch("id") }&.+(1)
      version = current.fetch("version", 0).to_i + 1
      begin
        @client.transact_write_items(transact_items: [
          { put: { table_name: @table, item: BOARD_KEY.merge("version" => version, "entries" => ranked),
                   condition_expression: "attribute_not_exists(version) OR version = :version",
                   expression_attribute_values: { ":version" => current.fetch("version", 0) } } },
          { put: { table_name: @table, item: { "pk" => "RUN", "sk" => submission.fetch("runId"), "expiresAt" => Time.now.to_i + 86_400 },
                   condition_expression: "attribute_not_exists(pk)" } }
        ])
        return response(200, Leaderboard.response(ranked, submission: entry).merge(version: version, rank: rank, duplicate: false, entry: rank ? entry : nil))
      rescue Aws::DynamoDB::Errors::TransactionCanceledException
        duplicate = @client.get_item(table_name: @table, key: { "pk" => "RUN", "sk" => submission.fetch("runId") }, consistent_read: true).item
        return response(200, board.merge(duplicate: true)) if duplicate

        next
      end
    end
    response(409, error: "contention_retry")
  end

  def response(status, payload)
    { statusCode: status, headers: { "content-type" => "application/json", "cache-control" => "no-store" }, body: JSON.generate(payload) }
  end
end

def handler(event:, context:)
  LeaderboardHandler.new.call(event: event, context: context)
end
