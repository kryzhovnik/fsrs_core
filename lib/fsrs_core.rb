# frozen_string_literal: true
require_relative "fsrs_core/version"
require_relative "fsrs_core/errors"
require_relative "fsrs_core/values"
require_relative "fsrs_core/parameters"
require_relative "fsrs_core/validate"
require_relative "fsrs_core/algorithm"
require_relative "fsrs_core/scheduler"

module FsrsCore
  FSRS_ALGORITHM = 6
  FSRS_CRATE_VERSION = "6.6.1"
end
