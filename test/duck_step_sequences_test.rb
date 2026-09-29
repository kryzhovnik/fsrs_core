# frozen_string_literal: true
require "test_helper"
require "json"

# Step sequences from Duck's scheduler vectors (Duck: bin/rails "scheduler:vectors:fsrs_core[path]").
# Each step is one next_state call as Duck makes it: the memory the card held before the review
# (Duck stores stability and difficulty with three decimals), whole elapsed days and a binary
# rating (1 or 3). Values are f64 from this gem, so the tolerance is the 1e-9 relative one that
# Duck's native ports use, not the f32 tolerances of golden.json.
class DuckStepSequencesTest < Minitest::Test
  SEQUENCES = JSON.parse(File.read(File.expand_path("support/duck_step_sequences.json", __dir__)))
  RELATIVE_TOLERANCE = 1e-9

  def test_sequences_are_present
    assert_operator SEQUENCES.length, :>=, 20
  end

  SEQUENCES.each_with_index do |sequence, index|
    define_method("test_duck_sequence_#{index + 1}") do
      scheduler = FsrsCore::Scheduler.new
      sequence["steps"].each_with_index do |step, position|
        memory = step["memory"] && FsrsCore::MemoryState.new(stability: step["memory"]["stability"], difficulty: step["memory"]["difficulty"])
        item = scheduler.next_state(memory_state: memory, desired_retention: sequence["desired_retention"],
                                    days_elapsed: step["days_elapsed"], rating: step["rating"])
        label = "#{sequence['description']}, step #{position + 1}"

        close(step.dig("expected", "stability"), item.memory.stability, "#{label}: stability")
        close(step.dig("expected", "difficulty"), item.memory.difficulty, "#{label}: difficulty")
        close(step.dig("expected", "interval"), item.interval, "#{label}: interval")
      end
    end
  end

  private

  def close(expected, actual, message)
    assert_in_delta expected, actual, expected.abs * RELATIVE_TOLERANCE, message
  end
end
