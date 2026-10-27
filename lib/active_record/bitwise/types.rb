# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module ActiveRecord
  # Namespace for the ActiveRecord::Bitwise gem.
  module Bitwise
    # Sorbet type aliases shared by the signatures of this gem.
    module Types
      # A column or flag name, as users may spell it.
      Name = T.type_alias { T.any(Symbol, String) }
      public_constant :Name

      # A list of flag names.
      Flags = T.type_alias { T::Array[T.any(Symbol, String)] }
      public_constant :Flags

      # Flag names mapped to their bit positions.
      Positions = T.type_alias { T::Hash[Symbol, Integer] }
      public_constant :Positions

      # A flag mapping as declared by the user: names to bit positions, or an ordered list of names.
      Definition = T.type_alias { T.any(T::Hash[T.untyped, T.untyped], T::Array[T.untyped]) }
      public_constant :Definition

      # Query conditions or assignments keyed by column.
      Params = T.type_alias { T::Hash[T.untyped, T.untyped] }
      public_constant :Params
    end
  end
end
