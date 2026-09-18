# frozen_string_literal: true

class Leaderboard
  LIMIT = 15
  MAX_SCORE = 99_999_999
  DIFFICULTIES = %w[easy normal hard].freeze
  OUTCOMES = %w[game_over victory].freeze
  DENIED_INITIALS = %w[ASS FUK KKK SEX XXX].freeze
  class ValidationError < StandardError; end

  def self.validate_submission(input)
    expected = %w[runId initials score stage difficulty outcome]
    raise ValidationError, "invalid fields" unless input.is_a?(Hash) && input.keys.map(&:to_s).sort == expected.sort
    value = ->(key) { input.key?(key) ? input[key] : input[key.to_sym] }
    initials = value.call("initials").to_s.upcase
    run_id = value.call("runId").to_s
    score, stage = value.call("score"), value.call("stage")
    difficulty, outcome = value.call("difficulty").to_s, value.call("outcome").to_s
    raise ValidationError, "invalid run id" unless run_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
    raise ValidationError, "invalid initials" unless initials.match?(/\A[A-Z]{3}\z/) && !DENIED_INITIALS.include?(initials)
    raise ValidationError, "invalid score" unless score.is_a?(Integer) && score.between?(0, MAX_SCORE)
    raise ValidationError, "invalid stage" unless stage.is_a?(Integer) && stage.between?(1, 20)
    raise ValidationError, "invalid difficulty" unless DIFFICULTIES.include?(difficulty)
    raise ValidationError, "invalid outcome" unless OUTCOMES.include?(outcome)
    { "runId" => run_id.downcase, "initials" => initials, "score" => score, "stage" => stage, "difficulty" => difficulty, "outcome" => outcome }
  end

  def self.rank(entries)
    entries.sort_by { |entry| [-entry.fetch("score"), entry.fetch("achievedAt"), entry.fetch("id")] }.first(LIMIT).each_with_index.map { |entry, index| entry.merge("rank" => index + 1) }
  end

  def self.response(entries, submission: nil)
    ranked = rank(entries)
    { "version" => 1, "highScore" => ranked.first&.fetch("score", 0) || 0, "entries" => ranked }.tap { |payload| payload["submission"] = submission if submission }
  end
end
