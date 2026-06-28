# frozen_string_literal: true
module FsrsCore
  class Error < StandardError; end
  class ValidationError < Error; end
  class InvalidParametersError < ValidationError; end
end
