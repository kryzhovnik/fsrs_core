# frozen_string_literal: true
require "test_helper"

class AlgorithmDifficultyTest < Minitest::Test
  A = FsrsCore::Algorithm
  W = FsrsCore::Parameters::DEFAULT

  def test_next_difficulty_fixtures
    expected = [8.354889, 6.6774445, 5.0, 3.3225555]   # next_difficulty(5.0, rating) ratings 1..4
    (1..4).each_with_index { |g, i| assert_in_delta expected[i], A.next_difficulty(W, 5.0, g.to_f), 1e-4, "rating #{g}" }
  end

  def test_mean_reversion_fixtures
    expected = [8.341763, 6.6659956, 4.990228, 3.3144615]   # after mean_reversion(next_difficulty(5.0, rating))
    (1..4).each_with_index { |g, i| assert_in_delta expected[i], A.mean_reversion(W, A.next_difficulty(W, 5.0, g.to_f)), 1e-4, "rating #{g}" }
  end

  def test_linear_damping_zero_at_10
    assert_in_delta 0.0, A.linear_damping(5.0, 10.0), 1e-12
  end
end
