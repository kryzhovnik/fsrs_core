# frozen_string_literal: true
module FsrsCore
  class Scheduler
    BRANCH = { 1 => :again, 2 => :hard, 3 => :good, 4 => :easy }.freeze

    def initialize(parameters: nil)
      @w = parameters.nil? ? Parameters::DEFAULT : Validate.parameters(parameters)
    end

    def next_states(memory_state:, desired_retention:, days_elapsed:)
      r = Validate.retention(desired_retention)
      days = Validate.u32(days_elapsed, "days_elapsed")
      mem = memory_state.nil? ? nil : Validate.memory(memory_state)
      raw = Algorithm.next_states(@w, mem, r, days)
      NextStates.new(**raw.transform_values { |b| item_state(b) })
    end

    def next_state(memory_state:, desired_retention:, days_elapsed:, rating:)
      g = Validate.rating(rating)
      next_states(memory_state: memory_state, desired_retention: desired_retention, days_elapsed: days_elapsed)
        .public_send(BRANCH.fetch(g))
    end

    def next_interval(stability:, desired_retention:)
      s = Validate.stability(stability)
      r = Validate.retention(desired_retention)
      finite!(Algorithm.next_interval(@w, s, r), "interval")
    end

    def memory_state(reviews:)
      ratings, deltas = Validate.reviews(reviews)
      s, d = Algorithm.memory_state(@w, ratings, deltas)
      MemoryState.new(stability: finite!(s, "stability"), difficulty: finite!(d, "difficulty"))
    end

    def current_retrievability(memory_state:, days_elapsed:)
      s, = Validate.memory(memory_state)
      days = Validate.fractional_days(days_elapsed)
      finite!(Algorithm.power_forgetting_curve(@w, days, s), "retrievability")
    end

    private

    def item_state(b)
      ItemState.new(
        memory: MemoryState.new(stability: finite!(b[:stability], "stability"), difficulty: finite!(b[:difficulty], "difficulty")),
        interval: finite!(b[:interval], "interval")
      )
    end

    def finite!(value, name)
      raise ValidationError, "computed #{name} is not finite (degenerate input)" unless value.is_a?(Float) && value.finite?
      value
    end
  end
end
