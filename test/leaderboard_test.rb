# frozen_string_literal: true
require_relative "../leaderboard/leaderboard"
def assert(condition, message)
  raise "Leaderboard check failed: #{message}" unless condition
end
def rejects(value)
  Leaderboard.validate_submission(value); false
rescue Leaderboard::ValidationError
  true
end
base = { "runId" => "123e4567-e89b-42d3-a456-426614174000", "initials" => "RAI", "score" => 12_300, "stage" => 3, "difficulty" => "normal", "outcome" => "game_over" }
assert(Leaderboard.validate_submission(base) == base, "valid submission is normalized")
[base.merge("extra" => true), base.reject { |key| key == "score" }, base.merge("runId" => "bad"), base.merge("initials" => "AA"), base.merge("initials" => "KKK"), base.merge("score" => -1), base.merge("score" => 100_000_000), base.merge("stage" => 0), base.merge("difficulty" => "nightmare"), base.merge("outcome" => "quit")].each { |value| assert(rejects(value), "invalid submission is rejected") }
entries = 18.times.map { |index| base.merge("id" => format("%02d", index), "score" => index % 3, "achievedAt" => "2026-01-01T00:00:#{format('%02d', 17-index)}Z") }
ranked = Leaderboard.rank(entries)
assert(ranked.length == 15, "board is capped")
assert(ranked.first(3).all? { |entry| entry["score"] == 2 }, "score ranks descending")
assert(ranked.map { |entry| entry["rank"] } == (1..15).to_a, "ranks are assigned")
assert(ranked.each_cons(2).all? { |left, right| ([-left["score"], left["achievedAt"], left["id"]] <=> [-right["score"], right["achievedAt"], right["id"]]) <= 0 }, "ties are deterministic")
response = Leaderboard.response([entries.first], submission: entries.first)
assert(response["highScore"] == entries.first["score"] && response["submission"] == entries.first, "response includes score and submission")
assert(Leaderboard.response([]) == { "version" => 1, "highScore" => 0, "entries" => [], "highScores" => { "easy" => 0, "normal" => 0, "hard" => 0 } }, "empty response")

module Aws
  module DynamoDB
    class Client; end
    module Errors
      class ServiceError < StandardError; end
      class TransactionCanceledException < ServiceError; end
    end
  end
end
require_relative "../leaderboard/handler"
fake_result = Struct.new(:item)
fake_client = Object.new
fake_client.define_singleton_method(:get_item) { |**| fake_result.new(nil) }
raw_body = LeaderboardHandler.new(table: "leaderboard-test", client: fake_client).call(event: { "requestContext" => { "http" => { "method" => "GET" } } })[:body]
assert(raw_body.scan(/"version":/).length == 1, "serialized board has one version key")
assert(JSON.parse(raw_body) == { "version" => 0, "highScore" => 0, "entries" => [], "highScores" => { "easy" => 0, "normal" => 0, "hard" => 0 } }, "handler returns the empty board revision")
puts "Leaderboard domain check passed"

assert(Leaderboard.response(entries, high_scores: { "hard" => 50 })["highScores"] == { "easy" => 0, "normal" => 2, "hard" => 50 }, "difficulty record survives absence from the global board")
puts "Difficulty record checks passed"

stored_board = { "version" => 1, "entries" => Leaderboard.rank(entries.map { |entry| entry.merge("score" => 2000) }), "highScores" => { "easy" => 800, "normal" => 2000, "hard" => 100 } }
transaction_client = Object.new
transaction_client.define_singleton_method(:get_item) { |key:, **| fake_result.new(key == LeaderboardHandler::BOARD_KEY ? stored_board : nil) }
transaction_client.define_singleton_method(:transact_write_items) { |transact_items:| stored_board.replace(transact_items.first.fetch(:put).fetch(:item)) }
handler = LeaderboardHandler.new(table: "leaderboard-test", client: transaction_client)
submitted = handler.call(event: { "httpMethod" => "POST", "headers" => { "content-type" => "application/json" }, "body" => JSON.generate(base.merge("difficulty" => "hard", "score" => 500)) })
payload = JSON.parse(submitted[:body])
assert(payload["rank"].nil?, "difficulty record can be below global Top 15")
assert(stored_board["highScores"] == { "easy" => 800, "normal" => 2000, "hard" => 500 }, "transaction preserves all difficulty records")
assert(JSON.parse(handler.call(event: { "httpMethod" => "GET" })[:body])["highScores"]["hard"] == 500, "GET retains a record absent from ranked entries")
puts "Persistent difficulty record transaction checks passed"
