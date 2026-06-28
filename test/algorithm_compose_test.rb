# frozen_string_literal: true
require "test_helper"

class AlgorithmComposeTest < Minitest::Test
  A = FsrsCore::Algorithm
  W = FsrsCore::Parameters::DEFAULT

  def test_step_recall
    r = A.power_forgetting_curve(W, 7.0, 10.0)
    exp_s = [A.stability_after_success(W, 10.0, 5.0, r, 3.0), A::S_MAX].min
    exp_d = A.mean_reversion(W, A.next_difficulty(W, 5.0, 3.0)).clamp(1.0, 10.0)
    s, d = A.step(W, 7.0, 3.0, 10.0, 5.0)
    assert_in_delta exp_s, s, 1e-9
    assert_in_delta exp_d, d, 1e-9
  end

  def test_step_same_day_short_term_all_ratings
    (1..4).each do |g|
      exp_s = [A.stability_short_term(W, 10.0, g.to_f), A::S_MAX].min
      s, = A.step(W, 0.0, g.to_f, 10.0, 5.0)
      assert_in_delta exp_s, s, 1e-9, "rating #{g}"
    end
  end

  def test_step_lapse_uses_failure
    r = A.power_forgetting_curve(W, 7.0, 10.0)
    exp_s = [A.stability_after_failure(W, 10.0, 5.0, r), A::S_MAX].min
    s, = A.step(W, 7.0, 1.0, 10.0, 5.0)
    assert_in_delta exp_s, s, 1e-9
  end

  def test_step_saturates_at_s_max
    s, = A.step(W, 1.0, 4.0, A::S_MAX, 1.0)
    assert_equal A::S_MAX, s
  end

  def test_next_states_new_card
    ns = A.next_states(W, nil, 0.9, 0)
    (1..4).each do |g|
      key = %i[again hard good easy][g - 1]
      assert_in_delta [A.init_stability(W, g), A::S_MAX].min, ns[key][:stability], 1e-9
      assert_in_delta A.init_difficulty(W, g).clamp(1.0, 10.0), ns[key][:difficulty], 1e-9
      assert_in_delta A.next_interval(W, ns[key][:stability], 0.9), ns[key][:interval], 1e-9
    end
  end

  def test_memory_state_first_is_init
    s, d = A.memory_state(W, [3], [0])
    assert_in_delta A.init_stability(W, 3), s, 1e-9
    assert_in_delta A.init_difficulty(W, 3).clamp(1.0, 10.0), d, 1e-9
  end

  def test_memory_state_second_same_day_short_term
    s1 = A.init_stability(W, 3)
    d1 = A.init_difficulty(W, 3).clamp(1.0, 10.0)
    exp_s = [A.stability_short_term(W, s1, 3.0), A::S_MAX].min
    exp_d = A.mean_reversion(W, A.next_difficulty(W, d1, 3.0)).clamp(1.0, 10.0)
    s, d = A.memory_state(W, [3, 3], [0, 0])
    assert_in_delta exp_s, s, 1e-9
    assert_in_delta exp_d, d, 1e-9
  end
end
