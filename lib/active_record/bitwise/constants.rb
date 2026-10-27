# typed: strict
# frozen_string_literal: true

require 'active_model'
require 'sorbet-runtime'

module ActiveRecord
  # Namespace for the ActiveRecord::Bitwise gem.
  module Bitwise
    # Maximum number of elements accepted in an assigned array (RAM-exhaustion defense).
    MAX_ARRAY_SIZE = 100
    public_constant :MAX_ARRAY_SIZE

    # Highest permitted bit position. Signed BIGINT columns physically cap at bit 62.
    MAX_BIT_POSITION = 62
    public_constant :MAX_BIT_POSITION

    # Shared boolean coercion used by the generated single-flag setters so that
    # form-style values ("0", "false", "", "off") disable a flag instead of enabling it.
    BOOLEAN_TYPE = ActiveModel::Type::Boolean.new
    public_constant :BOOLEAN_TYPE
  end
end
