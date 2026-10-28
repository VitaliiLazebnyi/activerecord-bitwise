# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/constants'
require 'active_record/bitwise/raw_mask'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # Backs the generated `flag=` and `flag!` methods.
      module FlagWrites
        extend T::Sig
        extend T::Helpers

        requires_ancestor { ActiveRecord::Base }

        # Enables or disables +key+ in +column_name+ using ActiveModel boolean semantics
        # ("0", "false", "", "off" and 0 disable the flag).
        # @param column_name [T.any(Symbol, String)]
        # @param key [Symbol]
        # @param value [T.untyped] The raw boolean-ish assignment.
        # @return [void]
        sig { params(column_name: Types::Name, key: Symbol, value: T.untyped).void }
        def _bitwise_assign_flag(column_name, key, value)
          original = public_send(column_name)
          flags = Array(original).dup # keeps the raw bitmask marker of +original+
          BOOLEAN_TYPE.cast(value) ? flags << key : flags.delete(key)
          public_send("#{column_name}=", flags)
        end
      end
    end
  end
end
