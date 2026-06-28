# frozen_string_literal: true
require "test_helper"

class SchedulerTest < Minitest::Test
  def setup
    @s = FsrsCore::Scheduler.new
  end

  def test_new_rejects_bad_parameters
    assert_raises(FsrsCore::InvalidParametersError) { FsrsCore::Scheduler.new(parameters: [0.1] * 5) }
  end

  def test_new_parameters_false_is_not_defaults
    assert_raises(FsrsCore::InvalidParametersError) { FsrsCore::Scheduler.new(parameters: false) }
  end

  def test_memory_state_false_is_not_new_card
    assert_raises(FsrsCore::ValidationError) do
      @s.next_states(memory_state: false, desired_retention: 0.9, days_elapsed: 0)
    end
  end

  def test_new_card
    ns = @s.next_states(memory_state: nil, desired_retention: 0.9, days_elapsed: 0)
    assert_instance_of FsrsCore::NextStates, ns
    assert_operator ns.good.memory.stability, :>, 0.0
    assert_operator ns.easy.interval, :>=, ns.good.interval
  end

  def test_next_state_equals_branch
    args = { memory_state: FsrsCore::MemoryState.new(stability: 10.0, difficulty: 5.0), desired_retention: 0.9, days_elapsed: 3 }
    ns = @s.next_states(**args)
    { 1 => ns.again, 2 => ns.hard, 3 => ns.good, 4 => ns.easy }.each do |rating, branch|
      assert_equal branch, @s.next_state(**args, rating: rating)
    end
  end

  def test_next_interval
    assert_operator @s.next_interval(stability: 50.0, desired_retention: 0.9), :>, @s.next_interval(stability: 5.0, desired_retention: 0.9)
  end

  def test_memory_state
    ms = @s.memory_state(reviews: [FsrsCore::Review.new(rating: 3, delta_t: 0), FsrsCore::Review.new(rating: 3, delta_t: 7)])
    assert_instance_of FsrsCore::MemoryState, ms
    assert_operator ms.stability, :>, 0.0
  end

  def test_current_retrievability
    ms = FsrsCore::MemoryState.new(stability: 10.0, difficulty: 5.0)
    r0 = @s.current_retrievability(memory_state: ms, days_elapsed: 0.0)
    r5 = @s.current_retrievability(memory_state: ms, days_elapsed: 5.0)
    assert_in_delta 1.0, r0, 1e-6
    assert_operator r5, :<, r0
  end

  def test_validation_errors
    assert_raises(FsrsCore::ValidationError) { @s.next_states(memory_state: nil, desired_retention: 1.5, days_elapsed: 0) }
    assert_raises(FsrsCore::ValidationError) { @s.next_states(memory_state: nil, desired_retention: 0.9, days_elapsed: 1.5) }
  end

  def test_finiteness_guard
    assert_raises(FsrsCore::ValidationError) { @s.next_interval(stability: 100.0, desired_retention: Float::MIN) }
  end
end
