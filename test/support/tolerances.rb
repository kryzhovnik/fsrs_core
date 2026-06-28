# frozen_string_literal: true

module FsrsCoreTestSupport
  module Tolerances
    # The 4,096-case corpus includes long histories and extreme custom parameters. Where values are
    # large enough for relative error to be meaningful, f32-vs-f64 accumulation stays below ~4e-5
    # relative for stability/interval, so 1e-4 keeps roughly a 2.5x margin; the small named golden
    # set retains its tighter tolerances. (Near the S_MIN floor a sub-1e-6 absolute gap divided by a
    # near-zero value looks larger in relative terms, but the absolute tolerance floor governs there.)
    CORPUS_RELATIVE_TOLERANCE = 1e-4

    FUNCTIONS = {
      'retrievability' => ->(_expected) { 1e-6 },
      'difficulty' => ->(_expected) { 1e-4 },
      'stability' => ->(expected) { 1e-4 + (3e-6 * expected.abs) },
      'interval' => ->(expected) { 1e-3 + (3e-6 * expected.abs) }
    }.freeze

    module_function

    def for(kind, expected)
      FUNCTIONS.fetch(kind).call(expected)
    end

    def for_corpus(kind, expected)
      base = self.for(kind, expected)
      return base unless %w[stability interval].include?(kind)

      [base, CORPUS_RELATIVE_TOLERANCE * expected.abs].max
    end
  end
end
