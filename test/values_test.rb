# frozen_string_literal: true
require "test_helper"

class ValuesTest < Minitest::Test
  def test_memory_state
    ms = FsrsCore::MemoryState.new(stability: 10.0, difficulty: 5.0)
    assert_equal 10.0, ms.stability
    assert_equal 5.0, ms.difficulty
    assert ms.frozen?
  end

  def test_compose
    ms = FsrsCore::MemoryState.new(stability: 10.0, difficulty: 5.0)
    item = FsrsCore::ItemState.new(memory: ms, interval: 7.0)
    ns = FsrsCore::NextStates.new(again: item, hard: item, good: item, easy: item)
    assert_equal 7.0, ns.good.interval
    assert_equal 10.0, ns.good.memory.stability
  end

  def test_review
    r = FsrsCore::Review.new(rating: 3, delta_t: 0)
    assert_equal 3, r.rating
    assert_equal 0, r.delta_t
  end
end
