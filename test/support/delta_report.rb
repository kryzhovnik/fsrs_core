# frozen_string_literal: true
# Usage: ruby -Ilib -Itest test/support/delta_report.rb
require "fsrs_core"
require "json"
G = JSON.parse(File.read(File.expand_path("golden.json", __dir__)))
max = Hash.new { |h, k| h[k] = { abs: 0.0, rel: 0.0 } }
rec = lambda do |kind, got, exp|
  a = (got - exp).abs
  max[kind][:abs] = a if a > max[kind][:abs]
  rel = exp.abs > 0 ? a / exp.abs : a
  max[kind][:rel] = rel if rel > max[kind][:rel]
end
sched = lambda do |c|
  params = c.dig("input", "parameters")
  params ? FsrsCore::Scheduler.new(parameters: params) : FsrsCore::Scheduler.new
end
mem = ->(h) { h && FsrsCore::MemoryState.new(stability: h["stability"], difficulty: h["difficulty"]) }
G["cases"].each do |c|
  s, inp, exp = sched.call(c), c["input"], c["expected"]
  case c["kind"]
  when "next_states"
    ns = s.next_states(memory_state: mem.call(inp["memory"]), desired_retention: inp["desired_retention"], days_elapsed: inp["days_elapsed"])
    %w[again hard good easy].each { |b| it = ns.public_send(b); e = exp[b]
      rec.call("stability", it.memory.stability, e["stability"]); rec.call("difficulty", it.memory.difficulty, e["difficulty"]); rec.call("interval", it.interval, e["interval"]) }
  when "memory_state"
    revs = inp["reviews"].map { |r| FsrsCore::Review.new(rating: r["rating"], delta_t: r["delta_t"]) }
    ms = s.memory_state(reviews: revs); rec.call("stability", ms.stability, exp["stability"]); rec.call("difficulty", ms.difficulty, exp["difficulty"])
  when "next_interval"
    rec.call("interval", s.next_interval(stability: inp["stability"], desired_retention: inp["desired_retention"]), exp["interval"])
  when "current_retrievability"
    rec.call("retrievability", s.current_retrievability(memory_state: mem.call(inp["memory"]), days_elapsed: inp["days_elapsed"]), exp["retrievability"])
  end
end
max.each { |k, v| puts format("%-15s abs=%.3e rel=%.3e", k, v[:abs], v[:rel]) }
