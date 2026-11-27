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
    raw_initials = value.call("initials").to_s
    # Only three ASCII letters reach String#upcase: Ruby's case conversion had memory-safety bugs
    # (advisories of 2026-11-18), and Unicode case mapping can turn two characters into three letters.
    raise ValidationError, "invalid initials" unless raw_initials.match?(/\A[A-Za-z]{3}\z/)
    initials = raw_initials.upcase
    run_id = value.call("runId").to_s
    score, stage = value.call("score"), value.call("stage")
    difficulty, outcome = value.call("difficulty").to_s, value.call("outcome").to_s
    # Explicit hex classes instead of /i: case-insensitive matching was also covered by those advisories.
    raise ValidationError, "invalid run id" unless run_id.match?(/\A\h{8}-\h{4}-4\h{3}-[89abAB]\h{3}-\h{12}\z/)
    raise ValidationError, "invalid initials" if DENIED_INITIALS.include?(initials)
    raise ValidationError, "invalid score" unless score.is_a?(Integer) && score.between?(0, MAX_SCORE)
    raise ValidationError, "invalid stage" unless stage.is_a?(Integer) && stage.between?(1, 20)
    raise ValidationError, "invalid difficulty" unless DIFFICULTIES.include?(difficulty)
    raise ValidationError, "invalid outcome" unless OUTCOMES.include?(outcome)
    { "runId" => run_id.downcase, "initials" => initials, "score" => score, "stage" => stage, "difficulty" => difficulty, "outcome" => outcome }
  end

  def self.rank(entries)
    entries.sort_by { |entry| [-entry.fetch("score"), entry.fetch("achievedAt"), entry.fetch("id")] }.first(LIMIT).each_with_index.map { |entry, index| entry.merge("rank" => index + 1) }
  end

  def self.high_scores(entries, saved = {})
    DIFFICULTIES.to_h do |difficulty|
      scores = entries.select { |entry| entry["difficulty"] == difficulty }.map { |entry| entry.fetch("score", 0).to_i }
      [difficulty, ([saved.fetch(difficulty, 0).to_i] + scores).max]
    end
  end

  def self.response(entries, submission: nil, high_scores: {})
    ranked = rank(entries)
    { "version" => 1, "highScore" => ranked.first&.fetch("score", 0) || 0, "entries" => ranked, "highScores" => self.high_scores(entries, high_scores) }.tap { |payload| payload["submission"] = submission if submission }
  end
end
