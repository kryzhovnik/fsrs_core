# frozen_string_literal: true
require "test_helper"

class ParametersTest < Minitest::Test
  EXPECTED_DEFAULT = [
    0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
    1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
    1.8729, 0.5425, 0.0912, 0.0658, 0.1542
  ].freeze

  EXPECTED_RANGES = [
    [0.001, 100.0], [0.001, 100.0], [0.001, 100.0], [0.001, 100.0],
    [1.0, 10.0], [0.001, 4.0], [0.001, 4.0], [0.001, 0.75],
    [0.0, 4.5], [0.0, 0.8], [0.001, 3.5], [0.001, 5.0],
    [0.001, 0.25], [0.001, 0.9], [0.0, 4.0], [0.0, 1.0],
    [1.0, 6.0], [0.0, 2.0], [0.0, 2.0], [0.0, 0.8], [0.1, 0.8]
  ].freeze

  def test_default_exact
    assert_equal 21, FsrsCore::Parameters::DEFAULT.length
    EXPECTED_DEFAULT.each_with_index { |w, i| assert_equal w, FsrsCore::Parameters::DEFAULT[i], "weight[#{i}]" }
    assert FsrsCore::Parameters::DEFAULT.frozen?
  end

  def test_clamp_ranges_exact
    assert_equal 21, FsrsCore::Parameters::CLAMP_RANGES.length
    EXPECTED_RANGES.each_with_index { |pair, i| assert_equal pair, FsrsCore::Parameters::CLAMP_RANGES[i], "range[#{i}]" }
  end

  def test_clamp_ranges_deep_frozen
    assert FsrsCore::Parameters::CLAMP_RANGES.frozen?
    FsrsCore::Parameters::CLAMP_RANGES.each_with_index do |pair, i|
      assert pair.frozen?, "range[#{i}] must be frozen"
      assert_raises(FrozenError) { pair[0] = 0.0 }
    end
  end

  def test_clip
    w = FsrsCore::Parameters::DEFAULT.dup
    w[20] = 5.0; w[8] = -1.0
    clipped = FsrsCore::Parameters.clip(w)
    assert_equal 0.8, clipped[20]
    assert_equal 0.0, clipped[8]
    assert clipped.frozen?
    assert_equal FsrsCore::Parameters::DEFAULT, FsrsCore::Parameters.clip(FsrsCore::Parameters::DEFAULT)
  end
end
