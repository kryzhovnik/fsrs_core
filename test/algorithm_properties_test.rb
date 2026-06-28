# frozen_string_literal: true
require "test_helper"

class AlgorithmPropertiesTest < Minitest::Test
  STABILITIES = [0.001, 0.01, 1.0, 10.0, 100.0, 36_500.0].freeze
  RETENTIONS = [1.0, 0.999, 0.99, 0.95, 0.9, 0.8, 0.5, 0.1].freeze

  def setup
    @scheduler = FsrsCore::Scheduler.new
  end

  def test_forgetting_curve_identities
    STABILITIES.each do |stability|
      memory = FsrsCore::MemoryState.new(stability: stability, difficulty: 5.0)
      assert_in_delta 1.0, @scheduler.current_retrievability(memory_state: memory, days_elapsed: 0), 1e-12
      assert_in_delta 0.9, @scheduler.current_retrievability(memory_state: memory, days_elapsed: stability), 1e-12
    end
  end

  def test_interval_is_inverse_of_forgetting_curve
    STABILITIES.each do |stability|
      memory = FsrsCore::MemoryState.new(stability: stability, difficulty: 5.0)
      RETENTIONS.each do |retention|
        interval = @scheduler.next_interval(stability: stability, desired_retention: retention)
        actual = @scheduler.current_retrievability(memory_state: memory, days_elapsed: interval)
        assert_in_delta retention, actual, 1e-12, "stability=#{stability}, retention=#{retention}"
      end
    end
  end

  def test_retrievability_is_monotonic
    STABILITIES.each do |stability|
      memory = FsrsCore::MemoryState.new(stability: stability, difficulty: 5.0)
      values = [0.0, stability / 10.0, stability, stability * 10.0].map do |days|
        @scheduler.current_retrievability(memory_state: memory, days_elapsed: days)
      end
      values.each_cons(2) { |left, right| assert_operator left, :>, right }
    end

    STABILITIES.each_cons(2) do |low, high|
      low_r = @scheduler.current_retrievability(
        memory_state: FsrsCore::MemoryState.new(stability: low, difficulty: 5.0), days_elapsed: 10.0
      )
      high_r = @scheduler.current_retrievability(
        memory_state: FsrsCore::MemoryState.new(stability: high, difficulty: 5.0), days_elapsed: 10.0
      )
      assert_operator low_r, :<, high_r
    end
  end

  def test_interval_scales_linearly_with_stability
    [0.1, 0.5, 0.8, 0.9, 0.99, 0.999].each do |retention|
      base = @scheduler.next_interval(stability: 1.0, desired_retention: retention)
      STABILITIES.each do |stability|
        actual = @scheduler.next_interval(stability: stability, desired_retention: retention)
        assert_in_delta base * stability, actual, 1e-9 * [actual.abs, 1.0].max
      end
    end
  end

  def test_next_states_are_finite_and_bounded
    memories = [
      FsrsCore::MemoryState.new(stability: 0.001, difficulty: 1.0),
      FsrsCore::MemoryState.new(stability: 10.0, difficulty: 5.0),
      FsrsCore::MemoryState.new(stability: 36_500.0, difficulty: 10.0)
    ]

    memories.product([0, 1, 365, FsrsCore::Validate::U32_MAX], [1, 2, 3, 4]).each do |memory, days, rating|
      item = @scheduler.next_state(memory_state: memory, desired_retention: 0.9, days_elapsed: days, rating: rating)
      assert item.memory.stability.finite?
      assert item.memory.difficulty.finite?
      assert item.interval.finite?
      assert_operator item.memory.stability, :>=, FsrsCore::Algorithm::S_MIN
      assert_operator item.memory.stability, :<=, FsrsCore::Algorithm::S_MAX
      assert_operator item.memory.difficulty, :>=, FsrsCore::Algorithm::D_MIN
      assert_operator item.memory.difficulty, :<=, FsrsCore::Algorithm::D_MAX
    end
  end

  def test_replay_matches_folding_next_state
    [1, 2, 3, 10, 100].each do |length|
      reviews = Array.new(length) do |index|
        FsrsCore::Review.new(
          rating: 1 + ((index * 7 + length) % 4),
          delta_t: index.zero? || (index % 5).zero? ? 0 : [1, 7, 30][index % 3]
        )
      end
      folded = reviews.reduce(nil) do |memory, review|
        @scheduler.next_state(
          memory_state: memory,
          desired_retention: 0.9,
          days_elapsed: review.delta_t,
          rating: review.rating
        ).memory
      end
      replayed = @scheduler.memory_state(reviews: reviews)
      assert_in_delta replayed.stability, folded.stability, 1e-12, "length=#{length}"
      assert_in_delta replayed.difficulty, folded.difficulty, 1e-12, "length=#{length}"
    end
  end

  def test_custom_initial_stability_is_used_by_public_scheduler
    parameters = FsrsCore::Parameters::DEFAULT.dup
    parameters[0] = 50.0
    scheduler = FsrsCore::Scheduler.new(parameters: parameters)
    item = scheduler.next_state(memory_state: nil, desired_retention: 0.9, days_elapsed: 0, rating: 1)
    assert_equal 50.0, item.memory.stability
  end
end
