# frozen_string_literal: true
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

task default: :test

desc "Verify 4,096 deterministic cases against the pinned Rust FSRS oracle"
task :oracle do
  require "fileutils"
  require "rbconfig"
  require "tempfile"

  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  manifest = File.expand_path("test/support/golden_gen/Cargo.toml", __dir__)
  verifier = File.expand_path("test/support/oracle_verifier.rb", __dir__)
  generator = [
    "cargo", "run", "--locked", "--quiet", "--manifest-path", manifest,
    "--bin", "oracle_corpus", "--"
  ].freeze

  Tempfile.create(["fsrs-oracle-a", ".ndjson"]) do |first|
    Tempfile.create(["fsrs-oracle-b", ".ndjson"]) do |second|
      first.close
      second.close
      sh(*generator, "--output", first.path)
      sh(*generator, "--output", second.path)
      raise "Rust oracle corpus is not byte-reproducible" unless FileUtils.compare_file(first.path, second.path)

      sh(RbConfig.ruby, "-Ilib", "-Itest", verifier, first.path)
    end
  end

  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  puts format("oracle verified in %.2fs", elapsed)
end
