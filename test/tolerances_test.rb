# frozen_string_literal: true
require "test_helper"
require "support/tolerances"

class TolerancesTest < Minitest::Test
  T = FsrsCoreTestSupport::Tolerances

  def test_fixed_tolerances
    assert_equal 1e-6, T.for("retrievability", 0.9)
    assert_equal 1e-4, T.for("difficulty", 5.0)
  end

  def test_scaled_tolerances
    assert_in_delta 0.3001, T.for("stability", 100_000.0), 1e-12
    assert_in_delta 0.301, T.for("interval", -100_000.0), 1e-12
  end

  def test_unknown_result_type
    assert_raises(KeyError) { T.for("unknown", 1.0) }
  end

  def test_corpus_tolerances_allow_measured_f32_accumulation
    assert_in_delta 10.0, T.for_corpus("stability", 100_000.0), 1e-12
    assert_in_delta 10.0, T.for_corpus("interval", 100_000.0), 1e-12
    assert_equal 1e-4, T.for_corpus("difficulty", 5.0)
    assert_equal 1e-6, T.for_corpus("retrievability", 0.9)
  end
end
