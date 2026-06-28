# frozen_string_literal: true
require "test_helper"

class ValidateTest < Minitest::Test
  V = FsrsCore::Validate

  def test_real_coerces_and_rejects
    assert_in_delta 0.5, V.real(0.5, "x"), 1e-12
    assert_in_delta 3.0, V.real(3, "x"), 1e-12
    assert_in_delta 0.25, V.real(Rational(1, 4), "x"), 1e-12
    assert_raises(FsrsCore::ValidationError) { V.real(Float::NAN, "x") }
    assert_raises(FsrsCore::ValidationError) { V.real(Float::INFINITY, "x") }
    assert_raises(FsrsCore::ValidationError) { V.real("nope", "x") }
    assert_raises(FsrsCore::ValidationError) { V.real(nil, "x") }
    assert_raises(FsrsCore::ValidationError) { V.real(Complex(1, 1), "x") }
  end

  def test_retention
    assert_in_delta 0.9, V.retention(0.9), 1e-12
    assert_raises(FsrsCore::ValidationError) { V.retention(0.0) }
    assert_raises(FsrsCore::ValidationError) { V.retention(1.0001) }
  end

  def test_parameters
    assert_equal 21, V.parameters(FsrsCore::Parameters::DEFAULT).length
    assert_raises(FsrsCore::InvalidParametersError) { V.parameters([0.1] * 20) }
    assert_raises(FsrsCore::InvalidParametersError) { V.parameters(false) }
    bad = FsrsCore::Parameters::DEFAULT.dup; bad[3] = Float::INFINITY
    assert_raises(FsrsCore::InvalidParametersError) { V.parameters(bad) }
  end

  def test_memory
    ms = FsrsCore::MemoryState.new(stability: 10.0, difficulty: 5.0)
    assert_equal [10.0, 5.0], V.memory(ms)
    assert_raises(FsrsCore::ValidationError) { V.memory(FsrsCore::MemoryState.new(stability: 0.0, difficulty: 5.0)) }
    assert_raises(FsrsCore::ValidationError) { V.memory(FsrsCore::MemoryState.new(stability: 10.0, difficulty: 0.5)) }
    assert_raises(FsrsCore::ValidationError) { V.memory(FsrsCore::MemoryState.new(stability: 10.0, difficulty: 11.0)) }
    assert_raises(FsrsCore::ValidationError) { V.memory("not a memory state") }
    assert_raises(FsrsCore::ValidationError) { V.memory(false) }
  end

  def test_stability_and_fractional_days
    assert_in_delta 21.4, V.stability(21.4), 1e-9
    assert_raises(FsrsCore::ValidationError) { V.stability(0.0) }
    assert_in_delta 2.5, V.fractional_days(2.5), 1e-9
    assert_raises(FsrsCore::ValidationError) { V.fractional_days(-1.0) }
  end

  def test_u32_and_rating
    assert_equal 3, V.u32(3, "days")
    assert_raises(FsrsCore::ValidationError) { V.u32(-1, "days") }
    assert_raises(FsrsCore::ValidationError) { V.u32(1.5, "days") }
    assert_equal 4, V.rating(4)
    assert_raises(FsrsCore::ValidationError) { V.rating(5) }
    assert_raises(FsrsCore::ValidationError) { V.rating(2.0) }
  end

  def test_reviews
    ratings, deltas = V.reviews([FsrsCore::Review.new(rating: 3, delta_t: 0), FsrsCore::Review.new(rating: 4, delta_t: 7)])
    assert_equal [3, 4], ratings
    assert_equal [0, 7], deltas
    assert_raises(FsrsCore::ValidationError) { V.reviews([]) }
    assert_raises(FsrsCore::ValidationError) { V.reviews([FsrsCore::Review.new(rating: 3, delta_t: 5)]) }
    assert_raises(FsrsCore::ValidationError) { V.reviews([FsrsCore::Review.new(rating: 9, delta_t: 0)]) }
    assert_raises(FsrsCore::ValidationError) { V.reviews("nope") }
  end
end
