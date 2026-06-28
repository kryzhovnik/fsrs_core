# frozen_string_literal: true
require "test_helper"

class AlgorithmCurveTest < Minitest::Test
  A = FsrsCore::Algorithm
  W = FsrsCore::Parameters::DEFAULT

  def test_power_forgetting_curve_fixtures
    inputs   = [[0.0, 1.0], [1.0, 2.0], [2.0, 3.0], [3.0, 4.0], [4.0, 4.0], [5.0, 2.0]]
    expected = [1.0, 0.9403443, 0.9253786, 0.9185229, 0.9, 0.8261359]
    inputs.each_with_index { |(t, s), i| assert_in_delta expected[i], A.power_forgetting_curve(W, t, s), 1e-6, "t=#{t},s=#{s}" }
  end

  def test_curve_at_stability_is_0_9
    assert_in_delta 0.9, A.power_forgetting_curve(W, 10.0, 10.0), 1e-6
  end

  def test_next_interval_at_0_9_equals_stability
    [5.0, 50.0, 500.0].each { |s| assert_in_delta s, A.next_interval(W, s, 0.9), 1e-6 * s + 1e-9 }
  end

  def test_next_interval_changes_with_retention
    assert_operator A.next_interval(W, 50.0, 0.95), :<, A.next_interval(W, 50.0, 0.9)
    assert_operator A.next_interval(W, 50.0, 0.8),  :>, A.next_interval(W, 50.0, 0.9)
  end

  def test_init_difficulty_raw_form
    (1..4).each { |g| assert_in_delta(W[4] - Math.exp(W[5] * (g - 1)) + 1.0, A.init_difficulty(W, g), 1e-9, "rating #{g}") }
  end

  def test_init_stability_maps_w0_to_w3
    (1..4).each { |g| assert_equal W[g - 1], A.init_stability(W, g) }
  end
end
