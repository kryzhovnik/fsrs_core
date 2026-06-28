# frozen_string_literal: true
module FsrsCore
  module Algorithm
    module_function

    S_MIN = 0.001
    S_MAX = 36_500.0
    D_MIN = 1.0
    D_MAX = 10.0

    def power_forgetting_curve(w, t, s)
      decay = -w[20]
      factor = Math.exp(Math.log(0.9) / decay) - 1.0
      (t / s * factor + 1.0)**decay
    end

    def next_interval(w, stability, desired_retention)
      decay = -w[20]
      factor = Math.exp(Math.log(0.9) / decay) - 1.0
      stability / factor * (desired_retention**(1.0 / decay) - 1.0)
    end

    def init_stability(w, rating)
      w[[rating - 1, 3].min]            # rating 1..4 -> w0..w3
    end

    def init_difficulty(w, rating)      # RAW, unclamped: w4 - exp(w5*(rating-1)) + 1
      w[4] - Math.exp(w[5] * (rating - 1)) + 1.0
    end

    def linear_damping(delta_d, old_d)
      (10.0 - old_d) * delta_d / 9.0
    end

    def next_difficulty(w, difficulty, rating)        # NO mean reversion / clamp here (step does those)
      delta_d = -w[6] * (rating - 3.0)
      difficulty + linear_damping(delta_d, difficulty)
    end

    def mean_reversion(w, new_d)                       # target = RAW init_difficulty(w, 4)
      w[7] * (init_difficulty(w, 4) - new_d) + new_d
    end

    def stability_after_success(w, last_s, last_d, r, rating)
      hard_penalty = (rating == 2.0 ? w[15] : 1.0)
      easy_bonus   = (rating == 4.0 ? w[16] : 1.0)
      last_s * (
        Math.exp(w[8]) * (11.0 - last_d) * (last_s**(-w[9])) *
        (Math.exp((1.0 - r) * w[10]) - 1.0) * hard_penalty * easy_bonus + 1.0
      )
    end

    def stability_after_failure(w, last_s, last_d, r)
      new_s = w[11] * (last_d**(-w[12])) * (((last_s + 1.0)**w[13]) - 1.0) * Math.exp((1.0 - r) * w[14])
      new_s_min = last_s / Math.exp(w[17] * w[18])
      [new_s, new_s_min].min
    end

    def stability_short_term(w, last_s, rating)
      sinc = Math.exp(w[17] * (rating - 3.0 + w[18])) * (last_s**(-w[19]))
      last_s * (rating >= 2.0 ? [sinc, 1.0].max : sinc)
    end

    def step(w, delta_t, rating, stability, difficulty)
      last_s = stability.clamp(S_MIN, S_MAX)
      last_d = difficulty.clamp(D_MIN, D_MAX)
      r = power_forgetting_curve(w, delta_t, last_s)

      new_s =
        if delta_t == 0.0
          stability_short_term(w, last_s, rating)
        elsif rating == 1.0
          stability_after_failure(w, last_s, last_d, r)
        else
          stability_after_success(w, last_s, last_d, r, rating)
        end

      new_d = mean_reversion(w, next_difficulty(w, last_d, rating)).clamp(D_MIN, D_MAX)
      [new_s.clamp(S_MIN, S_MAX), new_d]
    end

    def init_state(w, rating)
      [init_stability(w, rating).clamp(S_MIN, S_MAX), init_difficulty(w, rating).clamp(D_MIN, D_MAX)]
    end

    def next_states(w, memory, desired_retention, days_elapsed)
      out = {}
      [[:again, 1.0], [:hard, 2.0], [:good, 3.0], [:easy, 4.0]].each do |key, g|
        s, d = memory.nil? ? init_state(w, g) : step(w, days_elapsed.to_f, g, memory[0], memory[1])
        out[key] = { stability: s, difficulty: d, interval: next_interval(w, s, desired_retention) }
      end
      out
    end

    def memory_state(w, ratings, delta_ts)
      s, d = init_state(w, ratings[0])
      (1...ratings.length).each { |i| s, d = step(w, delta_ts[i].to_f, ratings[i].to_f, s, d) }
      [s, d]
    end
  end
end
