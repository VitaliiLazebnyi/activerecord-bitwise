# typed: strict
# frozen_string_literal: true

module ActiveRecord
  module Bitwise
    # Base error class for all ActiveRecord::Bitwise gem exceptions.
    class Error < StandardError; end

    # Exception raised when an unsupported query or operation is attempted.
    class NotSupportedError < Error; end

    # Exception raised at class-definition time for invalid bitwise configuration
    # (bad mappings, method collisions, invalid defaults). Inherits from
    # ArgumentError so existing `rescue ArgumentError` handlers keep working.
    class ConfigurationError < ArgumentError; end

    # Exception raised when a batch operation (`update_all`) receives flag values
    # that are not present in the mapping. Raising loudly prevents a typo from
    # silently zeroing the column for every matched row.
    class UnknownValueError < ArgumentError; end
  end
end
