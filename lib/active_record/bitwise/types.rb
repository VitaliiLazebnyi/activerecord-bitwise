# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'sorbet-runtime'

module ActiveRecord
  # Shared constants and Sorbet type aliases of the gem.
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

    # Sorbet type aliases shared by the signatures of this gem.
    module Types
      # An ActiveRecord model class.
      ModelClass = T.type_alias { T.class_of(ActiveRecord::Base) }
      public_constant :ModelClass

      # Query conditions or assignments keyed by column.
      Params = T.type_alias { T::Hash[Object, Object] }
      public_constant :Params

      # A column or flag name, as users may spell it.
      Name = T.type_alias { T.any(Symbol, String) }
      public_constant :Name

      # A list of flag names.
      Flags = T.type_alias { T::Array[T.any(Symbol, String)] }
      public_constant :Flags

      # Flag names mapped to their bit positions.
      Positions = T.type_alias { T::Hash[Symbol, Integer] }
      public_constant :Positions
    end
  end
end
