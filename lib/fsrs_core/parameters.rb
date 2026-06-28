# frozen_string_literal: true
module FsrsCore
  module Parameters
    module_function

    # FSRS-6 defaults, verbatim from fsrs 6.6.1 src/inference.rs.
    DEFAULT = [
      0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
      1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
      1.8729, 0.5425, 0.0912, 0.0658, 0.1542
    ].freeze

    # Per-index [min, max], verbatim from fsrs 6.6.1 src/parameter_clipper.rs, resolved for the
    # default FSRS::new instance (num_relearning_steps=1 -> w17/w18 max 2.0; enable_short_term=false
    # -> w19 min 0.0). S_MIN=0.001, INIT_S_MAX=100.0, D_MIN=1.0, D_MAX=10.0.
    CLAMP_RANGES = [
      [0.001, 100.0], [0.001, 100.0], [0.001, 100.0], [0.001, 100.0], # w0..w3
      [1.0, 10.0],                                                     # w4
      [0.001, 4.0], [0.001, 4.0], [0.001, 0.75],                       # w5..w7
      [0.0, 4.5], [0.0, 0.8], [0.001, 3.5],                            # w8..w10
      [0.001, 5.0], [0.001, 0.25], [0.001, 0.9], [0.0, 4.0],           # w11..w14
      [0.0, 1.0], [1.0, 6.0],                                          # w15..w16
      [0.0, 2.0], [0.0, 2.0], [0.0, 0.8],                              # w17..w19
      [0.1, 0.8]                                                       # w20 decay
    ].map(&:freeze).freeze

    def clip(weights)
      weights.each_with_index.map { |w, i| min, max = CLAMP_RANGES[i]; w.clamp(min, max) }.freeze
    end
  end
end
