# frozen_string_literal: true
require 'yaml'
require 'json'
template = YAML.safe_load(File.read(File.expand_path('../infra/site.yml', __dir__)))
rules = template.fetch('Resources').fetch('LeaderboardWebAcl').fetch('Properties').fetch('Rules')
invalid = rules.find { |r| r['Name'] == 'InvalidApiRequest' }.fetch('Statement')
# Evaluate the request-shape subset against real API boundary cases.
def matches(statement, path, method, bytes)
  key, value = statement.first
  case key
  when 'AndStatement' then value['Statements'].all? { |s| matches(s, path, method, bytes) }
  when 'OrStatement' then value['Statements'].any? { |s| matches(s, path, method, bytes) }
  when 'NotStatement' then !matches(value['Statement'], path, method, bytes)
  when 'ByteMatchStatement'
    actual = value['FieldToMatch'].key?('Method') ? method : path
    case value.fetch('PositionalConstraint')
    when 'EXACTLY' then actual == value['SearchString']
    when 'STARTS_WITH' then actual.start_with?(value['SearchString'])
    else raise 'Unsupported match'
    end
  when 'SizeConstraintStatement'
    raise 'Unexpected size operator' unless value['ComparisonOperator'] == 'LE'
    raise 'Overflow must fail allowed shape' unless value.dig('FieldToMatch', 'Body', 'OversizeHandling') == 'NO_MATCH'
    bytes <= value['Size']
  else raise "Unsupported statement #{key}"
  end
end
[
  ['/api/leaderboard', 'GET', 0, false],
  ['/api/leaderboard', 'GET', 1, true],
  ['/api/leaderboard', 'POST', 1024, false],
  ['/api/leaderboard', 'POST', 1025, true],
  ['/api/analytics', 'POST', 2048, false],
  ['/api/analytics', 'POST', 2049, true],
  ['/api/analytics', 'POST', 20000, true],
  ['/api/analytics', 'GET', 0, true],
  ['/api/leaderboard', 'DELETE', 0, true],
  ['/api/unknown', 'POST', 1, true],
  ['/api/leaderboard/extra', 'POST', 1, true],
  ['/web/app.js', 'GET', 0, false]
].each do |path, method, bytes, blocked|
  raise "Wrong match: #{[path, method, bytes]}" unless matches(invalid, path, method, bytes) == blocked
end
existing = rules.find { |r| r['Name'] == 'ApiRateLimit' }
raise 'Existing protection changed' unless existing['Action'] == {'Block'=>{}} && existing.dig('Statement', 'RateBasedStatement', 'Limit') == 100
raise 'Duplicate rule priorities' unless rules.map { |r| r['Priority'] }.uniq.size == rules.size
puts 'WAF request-boundary cases passed'
