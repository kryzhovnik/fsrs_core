# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'stringio'
require 'support/oracle_verifier'

class OracleVerifierTest < Minitest::Test
  V = FsrsCoreTestSupport::OracleVerifier

  def test_verifies_all_scheduler_operations
    cases = valid_cases
    output = StringIO.new
    summary = V.verify(corpus(cases), out: output)

    assert_equal 4, summary.cases
    assert_equal({
                   'current_retrievability' => 1,
                   'memory_state' => 1,
                   'next_interval' => 1,
                   'next_states' => 1
                 }, summary.counts)
    assert_includes output.string, "PASS: Ruby matches Rust FSRS #{FsrsCore::FSRS_CRATE_VERSION}"
    assert_includes output.string, 'Checked 4 cases; all results conform within minimal tolerances.'
    assert_includes output.string, 'Metric'
    assert_includes output.string, 'Largest deviation'
    assert_includes output.string, 'Tolerance'
    assert_match(/^Difficulty\s+0\.000e\+00\s+0\.000e\+00$/, output.string)
    assert_match(/^Interval\s+0\.000e\+00\s+0\.000e\+00$/, output.string)
    assert_match(/^Retrievability\s+0\.000e\+00\s+0\.000e\+00$/, output.string)
    assert_match(/^Stability\s+0\.000e\+00\s+0\.000e\+00$/, output.string)
    refute_includes output.string, 'abs='
    refute_includes output.string, 'rel='
  end

  def test_verbose_output_includes_raw_deltas
    previous = ENV['ORACLE_VERBOSE']
    ENV['ORACLE_VERBOSE'] = '1'
    output = StringIO.new

    V.verify(corpus(valid_cases), out: output)

    assert_includes output.string, "PASS: Ruby matches Rust FSRS #{FsrsCore::FSRS_CRATE_VERSION}"
    assert_includes output.string, 'Raw diagnostics'
    assert_match(/^interval\s+abs=\d\.\d{3}e[+-]\d{2} rel=\d\.\d{3}e[+-]\d{2}$/, output.string)
  ensure
    previous.nil? ? ENV.delete('ORACLE_VERBOSE') : ENV['ORACLE_VERBOSE'] = previous
  end

  def test_rejects_wrong_schema
    error = assert_raises(V::VerificationError) do
      V.verify(corpus(valid_cases, 'schema_version' => 99), out: StringIO.new)
    end
    assert_includes error.message, 'schema_version'
  end

  def test_rejects_wrong_crate_version
    error = assert_raises(V::VerificationError) do
      V.verify(corpus(valid_cases, 'crate_version' => '0.0.0'), out: StringIO.new)
    end
    assert_includes error.message, 'crate_version'
  end

  def test_rejects_duplicate_case_ids
    cases = [valid_cases.first, valid_cases.first]
    error = assert_raises(V::VerificationError) { V.verify(corpus(cases), out: StringIO.new) }
    assert_includes error.message, 'duplicate case id'
  end

  def test_rejects_count_mismatch
    error = assert_raises(V::VerificationError) do
      V.verify(corpus(valid_cases, 'case_count' => 99), out: StringIO.new)
    end
    assert_includes error.message, 'case_count'
  end

  def test_rejects_unknown_operation
    bad = valid_cases.first.merge('id' => 'unknown/0000', 'kind' => 'unknown')
    error = assert_raises(V::VerificationError) do
      V.verify(corpus([bad], 'counts' => { 'next_states' => 1 }), out: StringIO.new)
    end
    assert_includes error.message, 'unknown operation'
  end

  def test_rejects_missing_required_field
    bad = valid_cases.first.dup
    bad.delete('input')
    error = assert_raises(V::VerificationError) { V.verify(corpus([bad]), out: StringIO.new) }
    assert_includes error.message, 'input'
  end

  def test_numeric_mismatch_has_reproduction_context
    bad = valid_cases.find { |c| c['kind'] == 'next_interval' }
    bad = Marshal.load(Marshal.dump(bad))
    bad['expected']['interval'] += 1.0

    error = assert_raises(V::VerificationError) { V.verify(corpus([bad]), out: StringIO.new) }
    assert_includes error.message, 'seed=0x4653525300060601'
    assert_includes error.message, 'case=next_interval/0000'
    assert_includes error.message, 'expected='
    assert_includes error.message, 'actual='
    assert_includes error.message, 'abs_delta='
    assert_includes error.message, 'rel_delta='
    assert_includes error.message, 'input='
    assert_includes error.message, 'desired_retention'
    assert_includes error.message, '--case next_interval/0000'
  end

  def test_rejects_degenerate_computation
    bad = valid_cases.find { |c| c['kind'] == 'next_interval' }
    bad = Marshal.load(Marshal.dump(bad))
    bad['input']['desired_retention'] = Float::MIN

    error = assert_raises(V::VerificationError) { V.verify(corpus([bad]), out: StringIO.new) }
    assert_includes error.message, 'next_interval/0000'
    assert_includes error.message, 'not finite'
  end

  private

  def corpus(cases, overrides = {})
    counts = cases.map { |c| c.fetch('kind') }.tally
    meta = {
      'type' => 'meta',
      'schema_version' => 1,
      'generator_version' => 1,
      'crate_version' => FsrsCore::FSRS_CRATE_VERSION,
      'seed' => '0x4653525300060601',
      'case_count' => cases.length,
      'counts' => counts,
      'default_parameters' => FsrsCore::Parameters::DEFAULT
    }.merge(overrides)
    StringIO.new(([meta] + cases).map { |record| JSON.generate(record) }.join("\n") << "\n")
  end

  def valid_cases
    scheduler = FsrsCore::Scheduler.new
    memory = FsrsCore::MemoryState.new(stability: 10.0, difficulty: 5.0)
    reviews = [
      FsrsCore::Review.new(rating: 3, delta_t: 0),
      FsrsCore::Review.new(rating: 1, delta_t: 7)
    ]
    states = scheduler.next_states(memory_state: memory, desired_retention: 0.9, days_elapsed: 7)
    replay = scheduler.memory_state(reviews: reviews)

    [
      {
        'type' => 'case', 'id' => 'next_states/0000', 'kind' => 'next_states',
        'input' => { 'parameters' => nil, 'memory' => memory.to_h.transform_keys(&:to_s), 'desired_retention' => 0.9, 'days_elapsed' => 7 },
        'expected' => states.to_h.transform_values do |item|
          item.memory.to_h.transform_keys(&:to_s).merge('interval' => item.interval)
        end.transform_keys(&:to_s)
      },
      {
        'type' => 'case', 'id' => 'memory_state/0000', 'kind' => 'memory_state',
        'input' => { 'parameters' => nil, 'reviews' => reviews.map { |r| r.to_h.transform_keys(&:to_s) } },
        'expected' => replay.to_h.transform_keys(&:to_s)
      },
      {
        'type' => 'case', 'id' => 'next_interval/0000', 'kind' => 'next_interval',
        'input' => { 'parameters' => nil, 'stability' => 5.0, 'desired_retention' => 0.9 },
        'expected' => { 'interval' => scheduler.next_interval(stability: 5.0, desired_retention: 0.9) }
      },
      {
        'type' => 'case', 'id' => 'current_retrievability/0000', 'kind' => 'current_retrievability',
        'input' => { 'parameters' => nil, 'memory' => memory.to_h.transform_keys(&:to_s), 'days_elapsed' => 10.0 },
        'expected' => { 'retrievability' => scheduler.current_retrievability(memory_state: memory, days_elapsed: 10.0) }
      }
    ]
  end
end
