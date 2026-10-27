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

        # Enables or disables +key+ in +column_name+ using ActiveModel boolean semantics
        # ("0", "false", "", "off" and 0 disable the flag).
        # @param column_name [T.any(Symbol, String)]
        # @param key [Symbol]
        # @param value [T.untyped] The raw boolean-ish assignment.
        # @return [void]
        sig { params(column_name: Types::Name, key: Symbol, value: T.untyped).void }
        def _bitwise_assign_flag(column_name, key, value)
          original = T.unsafe(self).public_send(column_name)
          flags = Kernel.Array(original).dup
          RawMask.stamp(flags, RawMask.read(original)) if RawMask.stamped?(original)
          if BOOLEAN_TYPE.cast(value)
            flags << key unless flags.include?(key)
          else
            flags.delete(key)
          end
          T.unsafe(self).public_send("#{column_name}=", flags)
        end
      end
    end
  end
end
