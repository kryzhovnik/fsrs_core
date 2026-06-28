# frozen_string_literal: true
require "test_helper"
require "json"
require "support/tolerances"

class GoldenVectorsTest < Minitest::Test
  GOLDEN = JSON.parse(File.read(File.expand_path("support/golden.json", __dir__)))

  # Tolerances set just above the measured f32<->f64 gap (see test/support/delta_report.rb):
  # observed max abs/rel — stability 1.7e-4/1.3e-6, interval 5.6e-2/1.3e-6, difficulty 4.7e-7,
  # retrievability 2.4e-8. A real port bug differs by >>1%.
  def test_golden_metadata_is_current
    assert_equal FsrsCore::FSRS_CRATE_VERSION, GOLDEN.fetch("crate_version")
    # golden stores f32 weights widened to f64 (e.g. 0.212 -> 0.21199999749660492); allow the f32 gap.
    GOLDEN.fetch("default_parameters").each_with_index { |w, i| assert_in_delta w, FsrsCore::Parameters::DEFAULT[i], 1e-5, "default[#{i}]" }
    assert_operator GOLDEN.fetch("cases").length, :>=, 22
  end

  def close(kind, got, exp)
    assert_in_delta exp, got, FsrsCoreTestSupport::Tolerances.for(kind, exp), "#{kind}: got #{got}, exp #{exp}"
  end

  def scheduler(c)
    params = c.dig("input", "parameters")
    params ? FsrsCore::Scheduler.new(parameters: params) : FsrsCore::Scheduler.new
  end

  def mem(h) = h && FsrsCore::MemoryState.new(stability: h["stability"], difficulty: h["difficulty"])

  GOLDEN.fetch("cases").each do |c|
    define_method("test_#{c['name']}") do
      s, inp, exp = scheduler(c), c["input"], c["expected"]
      case c["kind"]
      when "next_states"
        ns = s.next_states(memory_state: mem(inp["memory"]), desired_retention: inp["desired_retention"], days_elapsed: inp["days_elapsed"])
        %w[again hard good easy].each { |b| it = ns.public_send(b); e = exp.fetch(b)
          close("stability", it.memory.stability, e["stability"]); close("difficulty", it.memory.difficulty, e["difficulty"]); close("interval", it.interval, e["interval"]) }
      when "memory_state"
        revs = inp["reviews"].map { |r| FsrsCore::Review.new(rating: r["rating"], delta_t: r["delta_t"]) }
        ms = s.memory_state(reviews: revs); close("stability", ms.stability, exp["stability"]); close("difficulty", ms.difficulty, exp["difficulty"])
      when "next_interval"
        close("interval", s.next_interval(stability: inp["stability"], desired_retention: inp["desired_retention"]), exp["interval"])
      when "current_retrievability"
        close("retrievability", s.current_retrievability(memory_state: mem(inp["memory"]), days_elapsed: inp["days_elapsed"]), exp["retrievability"])
      else
        flunk "unknown kind #{c['kind']}"
      end
    end
  end
end
