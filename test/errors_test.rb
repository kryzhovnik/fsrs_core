# frozen_string_literal: true
require "test_helper"

class ErrorsTest < Minitest::Test
  def test_constants
    assert_equal "0.1.0", FsrsCore::VERSION
    assert_equal 6, FsrsCore::FSRS_ALGORITHM
    assert_equal "6.6.1", FsrsCore::FSRS_CRATE_VERSION
  end

  def test_error_hierarchy
    assert FsrsCore::Error < StandardError
    assert FsrsCore::ValidationError < FsrsCore::Error
    assert FsrsCore::InvalidParametersError < FsrsCore::ValidationError
  end
end
