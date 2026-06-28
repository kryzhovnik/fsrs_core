# frozen_string_literal: true

require 'json'
require 'fsrs_core'
require_relative 'tolerances'

module FsrsCoreTestSupport
  module OracleVerifier
    SCHEMA_VERSION = 1
    GENERATOR_VERSION = 1
    SUPPORTED_KINDS = %w[current_retrievability memory_state next_interval next_states].freeze
    PARAMETER_TOLERANCE = 1e-5

    class VerificationError < StandardError; end

    Summary = Data.define(:cases, :counts, :max_deltas)

    module_function

    def verify(io, out: $stdout)
      records = parsed_records(io)
      meta = records.shift || raise(VerificationError, 'corpus is empty')
      validate_meta!(meta)

      seen = Set.new
      counts = Hash.new(0)
      maxima = Hash.new { |hash, kind| hash[kind] = { abs: 0.0, rel: 0.0, tol: 0.0 } }
      mismatches = []

      records.each do |record|
        id, kind, input, expected = validate_case!(record, seen)
        counts[kind] += 1
        begin
          compare_case(kind, input, expected, maxima, mismatches, meta, id)
        rescue StandardError => e
          mismatches << context(meta, id, kind, input, "computation_error=#{e.class}: #{e.message}")
        end
      end

      validate_counts!(meta, records.length, counts)
      raise VerificationError, mismatches.first(10).join("\n\n") unless mismatches.empty?

      normalized_counts = counts.sort.to_h.freeze
      normalized_maxima = maxima.sort.to_h.transform_values(&:freeze).freeze
      print_summary(out, records.length, normalized_counts, normalized_maxima)
      Summary.new(cases: records.length, counts: normalized_counts, max_deltas: normalized_maxima)
    end

    def parsed_records(io)
      io.each_line.with_index(1).filter_map do |line, line_number|
        next if line.strip.empty?

        JSON.parse(line)
      rescue JSON::ParserError => e
        raise VerificationError, "invalid JSON on line #{line_number}: #{e.message}"
      end
    end
    private_class_method :parsed_records

    def validate_meta!(meta)
      raise VerificationError, 'first record must have type=meta' unless meta.fetch('type') == 'meta'

      expect_meta(meta, 'schema_version', SCHEMA_VERSION)
      expect_meta(meta, 'generator_version', GENERATOR_VERSION)
      expect_meta(meta, 'crate_version', FsrsCore::FSRS_CRATE_VERSION)
      unless meta.fetch('seed').is_a?(String) && !meta.fetch('seed').empty?
        raise VerificationError,
              'seed must be a non-empty String'
      end

      case_count = meta.fetch('case_count')
      unless case_count.is_a?(Integer) && case_count >= 0
        raise VerificationError,
              'case_count must be a non-negative Integer'
      end

      counts = meta.fetch('counts')
      unless counts.is_a?(Hash) && counts.all? do |kind, count|
        SUPPORTED_KINDS.include?(kind) && count.is_a?(Integer) && count >= 0
      end
        raise VerificationError, 'counts contains an unsupported operation or invalid count'
      end

      parameters = meta.fetch('default_parameters')
      unless parameters.is_a?(Array) && parameters.length == FsrsCore::Parameters::DEFAULT.length
        raise VerificationError, 'default_parameters must contain exactly 21 weights'
      end

      parameters.each_with_index do |expected, index|
        actual = FsrsCore::Parameters::DEFAULT.fetch(index)
        next if expected.is_a?(Numeric) && expected.finite? && (expected - actual).abs <= PARAMETER_TOLERANCE

        raise VerificationError, "default_parameters[#{index}] does not match Ruby defaults"
      end
    rescue KeyError => e
      raise VerificationError, "metadata missing required field #{e.key.inspect}"
    end
    private_class_method :validate_meta!

    def expect_meta(meta, key, expected)
      actual = meta.fetch(key)
      return if actual == expected

      raise VerificationError,
            "#{key} mismatch: expected #{expected.inspect}, got #{actual.inspect}"
    end
    private_class_method :expect_meta

    def validate_case!(record, seen)
      raise VerificationError, 'case record must have type=case' unless record.fetch('type') == 'case'

      id = record.fetch('id')
      raise VerificationError, 'case id must be a non-empty String' unless id.is_a?(String) && !id.empty?
      raise VerificationError, "duplicate case id #{id.inspect}" unless seen.add?(id)

      kind = record.fetch('kind')
      raise VerificationError, "unknown operation #{kind.inspect} for case #{id}" unless SUPPORTED_KINDS.include?(kind)

      input = record.fetch('input')
      expected = record.fetch('expected')
      raise VerificationError, "input must be an object for case #{id}" unless input.is_a?(Hash)
      raise VerificationError, "expected must be an object for case #{id}" unless expected.is_a?(Hash)

      [id, kind, input, expected]
    rescue KeyError => e
      raise VerificationError, "case missing required field #{e.key.inspect}"
    end
    private_class_method :validate_case!

    def compare_case(kind, input, expected, maxima, mismatches, meta, id)
      scheduler = scheduler_for(input)
      case kind
      when 'next_states'
        result = scheduler.next_states(
          memory_state: memory(input.fetch('memory')),
          desired_retention: input.fetch('desired_retention'),
          days_elapsed: input.fetch('days_elapsed')
        )
        %w[again hard good easy].each do |branch|
          actual = result.public_send(branch)
          branch_expected = expected.fetch(branch)
          compare_scalar('stability', actual.memory.stability, branch_expected.fetch('stability'), maxima, mismatches,
                         meta, id, kind, input, branch)
          compare_scalar('difficulty', actual.memory.difficulty, branch_expected.fetch('difficulty'), maxima,
                         mismatches, meta, id, kind, input, branch)
          compare_scalar('interval', actual.interval, branch_expected.fetch('interval'), maxima, mismatches, meta, id,
                         kind, input, branch)
        end
      when 'memory_state'
        reviews = input.fetch('reviews').map { |review| FsrsCore::Review.new(rating: review.fetch('rating'), delta_t: review.fetch('delta_t')) }
        actual = scheduler.memory_state(reviews: reviews)
        compare_scalar('stability', actual.stability, expected.fetch('stability'), maxima, mismatches, meta, id, kind,
                       input)
        compare_scalar('difficulty', actual.difficulty, expected.fetch('difficulty'), maxima, mismatches, meta, id,
                       kind, input)
      when 'next_interval'
        actual = scheduler.next_interval(stability: input.fetch('stability'),
                                         desired_retention: input.fetch('desired_retention'))
        compare_scalar('interval', actual, expected.fetch('interval'), maxima, mismatches, meta, id, kind, input)
      when 'current_retrievability'
        actual = scheduler.current_retrievability(memory_state: memory(input.fetch('memory')),
                                                  days_elapsed: input.fetch('days_elapsed'))
        compare_scalar('retrievability', actual, expected.fetch('retrievability'), maxima, mismatches, meta, id, kind,
                       input)
      end
    end
    private_class_method :compare_case

    def scheduler_for(input)
      parameters = input.fetch('parameters')
      parameters.nil? ? FsrsCore::Scheduler.new : FsrsCore::Scheduler.new(parameters: parameters)
    end
    private_class_method :scheduler_for

    def memory(value)
      return nil if value.nil?

      FsrsCore::MemoryState.new(stability: value.fetch('stability'), difficulty: value.fetch('difficulty'))
    end
    private_class_method :memory

    def compare_scalar(result_type, actual, expected, maxima, mismatches, meta, id, kind, input, branch = nil)
      unless actual.is_a?(Numeric) && actual.finite? && expected.is_a?(Numeric) && expected.finite?
        mismatches << context(meta, id, kind, input,
                              "#{location(result_type, branch)} is not finite: expected=#{expected.inspect} actual=#{actual.inspect}")
        return
      end

      abs_delta = (actual - expected).abs
      rel_delta = expected.zero? ? abs_delta : abs_delta / expected.abs
      tolerance = Tolerances.for_corpus(result_type, expected)
      if abs_delta > maxima[result_type][:abs]
        maxima[result_type][:abs] = abs_delta       # largest deviation seen for this metric
        maxima[result_type][:tol] = tolerance       # and the tolerance allowed at that case
      end
      maxima[result_type][:rel] = [maxima[result_type][:rel], rel_delta].max
      return if abs_delta <= tolerance

      detail = format(
        '%s expected=%.17g actual=%.17g abs_delta=%.6e rel_delta=%.6e tolerance=%.6e',
        location(result_type, branch), expected, actual, abs_delta, rel_delta, tolerance
      )
      mismatches << context(meta, id, kind, input, detail)
    end
    private_class_method :compare_scalar

    def location(result_type, branch)
      branch ? "#{branch}.#{result_type}" : result_type
    end
    private_class_method :location

    def context(meta, id, kind, input, detail)
      "seed=#{meta.fetch('seed')} case=#{id} operation=#{kind} input=#{JSON.generate(input)} #{detail}\n" \
        'reproduce: cargo run --locked --quiet --manifest-path test/support/golden_gen/Cargo.toml ' \
        "--bin oracle_corpus -- --case #{id}"
    end
    private_class_method :context

    def validate_counts!(meta, observed_case_count, observed_counts)
      expected_case_count = meta.fetch('case_count')
      unless observed_case_count == expected_case_count
        raise VerificationError,
              "case_count mismatch: expected #{expected_case_count}, observed #{observed_case_count}"
      end

      expected_counts = meta.fetch('counts').sort.to_h
      actual_counts = observed_counts.sort.to_h
      unless actual_counts == expected_counts
        raise VerificationError,
              "counts mismatch: expected #{expected_counts.inspect}, observed #{actual_counts.inspect}"
      end
      return if expected_counts.values.sum == expected_case_count

      raise VerificationError,
            'counts do not sum to case_count'
    end
    private_class_method :validate_counts!

    def print_summary(out, cases, _counts, maxima)
      out.puts "PASS: Ruby matches Rust FSRS #{FsrsCore::FSRS_CRATE_VERSION}"
      out.puts "Checked #{cases} cases; all results conform within minimal tolerances."
      out.puts
      out.puts format('%-18s %-18s %s', 'Metric', 'Largest deviation', 'Tolerance')
      maxima.each do |kind, delta|
        label = kind.split('_').map(&:capitalize).join(' ')
        out.puts format('%-18s %-18s %s', label, format('%.3e', delta.fetch(:abs)), format('%.3e', delta.fetch(:tol)))
      end

      return unless ENV['ORACLE_VERBOSE'] == '1'

      out.puts
      out.puts 'Raw diagnostics'
      maxima.each do |kind, delta|
        out.puts format('%-15s abs=%.3e rel=%.3e', kind, delta.fetch(:abs), delta.fetch(:rel))
      end
    end
    private_class_method :print_summary
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    path = ARGV.fetch(0)
    File.open(path, 'r') { |io| FsrsCoreTestSupport::OracleVerifier.verify(io) }
  rescue StandardError => e
    warn e.message
    exit 1
  end
end
