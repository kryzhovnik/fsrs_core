# frozen_string_literal: true
require_relative "lib/fsrs_core/version"

Gem::Specification.new do |spec|
  spec.name        = "fsrs_core"
  spec.version     = FsrsCore::VERSION
  spec.authors     = ["Andrey Samsonov"]
  spec.email       = ["me@samsonov.io"]
  spec.summary     = "Pure-Ruby FSRS-6 spaced-repetition scheduler core"
  spec.description = "A faithful pure-Ruby implementation of the FSRS-6 scheduler " \
                     "(next_states, next_interval, memory_state, current_retrievability), " \
                     "ported verbatim from and golden-tested against the Rust fsrs crate 6.6.1."
  spec.homepage    = "https://github.com/kryzhovnik/fsrs_core"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  spec.files       = Dir["lib/**/*.rb", "LICENSE.txt", "THIRD_PARTY_NOTICES", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
