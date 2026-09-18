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
assert(Leaderboard.response([]) == { "version" => 1, "highScore" => 0, "entries" => [] }, "empty response")
puts "Leaderboard domain check passed"
