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
          enabled = BOOLEAN_TYPE.cast(value)
          original_array = public_send(column_name)
          current_values = Array(original_array).dup
          _bitwise_carry_marker(original_array, current_values)
          if enabled
            current_values << key unless current_values.include?(key)
          else
            current_values.delete(key)
          end
          public_send("#{column_name}=", current_values)
        end

        # Copies the raw bitmask marker of +source+ (when it is a stamped Array) onto +target+.
        # @param source [T.untyped]
        # @param target [T::Array[T.untyped]]
        # @return [void]
        sig { params(source: T.untyped, target: T::Array[T.untyped]).void }
        def _bitwise_carry_marker(source, target)
          return unless source.is_a?(Array) && source.instance_variable_defined?(:@_bitwise_raw_value)

          target.instance_variable_set(:@_bitwise_raw_value, source.instance_variable_get(:@_bitwise_raw_value))
        end
      end
    end
  end
end
