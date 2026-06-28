# frozen_string_literal: true
require "test_helper"

class AlgorithmStabilityTest < Minitest::Test
  A = FsrsCore::Algorithm
  W = FsrsCore::Parameters::DEFAULT

  def test_stability_after_success_fixtures
    rs = [0.9, 0.8, 0.7, 0.6]
    expected = [25.602541, 28.226582, 58.656002, 127.226685]
    (1..4).each_with_index { |g, i| assert_in_delta expected[i], A.stability_after_success(W, 5.0, g.to_f, rs[i], g.to_f), 1e-3, "rating #{g}" }
  end

  def test_stability_after_failure_fixtures
    rs = [0.9, 0.8, 0.7, 0.6]
    expected = [1.0525396, 1.1894329, 1.3680838, 1.584989]
    (1..4).each_with_index { |d, i| assert_in_delta expected[i], A.stability_after_failure(W, 5.0, d.to_f, rs[i]), 1e-4, "difficulty #{d}" }
  end

  def test_stability_after_failure_cap_active
    w = W.dup
    w[17] = 2.0; w[18] = 2.0                 # cap = 5 / exp(4) ~= 0.091578
    cap = 5.0 / Math.exp(4.0)
    got = A.stability_after_failure(w, 5.0, 1.0, 0.9)
    assert_in_delta cap, got, 1e-9          # min() must select the cap, not the (~1.05) formula
  end

  def test_stability_short_term_fixtures
    expected = [1.596818, 5.0, 5.0, 8.12961] # ratings 2,3 hit max(1.0) floor -> 5.0; rating 1 no floor
    (1..4).each_with_index { |g, i| assert_in_delta expected[i], A.stability_short_term(W, 5.0, g.to_f), 1e-4, "rating #{g}" }
  end
end
