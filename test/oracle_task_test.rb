# frozen_string_literal: true
require "test_helper"
require "rake"
require "yaml"

class OracleTaskTest < Minitest::Test
  def setup
    @previous_application = Rake.application
    Rake.application = Rake::Application.new
    Rake::TaskManager.record_task_metadata = true
    load File.expand_path("../Rakefile", __dir__)
  end

  def teardown
    Rake.application = @previous_application
  end

  def test_oracle_task_is_available_and_documented
    assert Rake::Task.task_defined?("oracle")
    assert_includes Rake::Task["oracle"].full_comment, "Rust"
    assert_includes Rake::Task["oracle"].full_comment, "4,096"
  end

  def test_ci_runs_one_non_matrix_oracle_job
    workflow = YAML.safe_load(
      File.read(File.expand_path("../.github/workflows/ci.yml", __dir__)),
      aliases: false
    )
    oracle = workflow.fetch("jobs").fetch("oracle")
    refute oracle.key?("strategy")
    steps = oracle.fetch("steps")
    assert steps.any? { |step| step["uses"] == "actions/cache@v4" }
    assert steps.any? { |step| step["run"]&.include?("rustup toolchain install 1.96.0") }
    assert steps.any? { |step| step["run"]&.include?("bundle exec rake oracle") }
  end
end
