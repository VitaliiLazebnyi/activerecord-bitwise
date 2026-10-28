# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/instance_methods/model_access'
require 'active_record/bitwise/raw_mask'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # Access to the raw database bitmask of a bitwise column, including the unmapped
      # ("forgotten") bits that the flag arrays cannot express. Saves write those bits back
      # unchanged, so legacy data survives ordinary updates.
      module RawCache
        extend T::Sig
        extend T::Helpers

        requires_ancestor { ActiveRecord::Base }
        requires_ancestor { ModelAccess }

        # Kept for backwards compatibility: the raw bitmask used to be cached per record and
        # is now always read from the attribute itself, so there is nothing left to clear.
        # @return [void]
        sig { void }
        def clear_bitwise_raw_values_cache!; end

        # The raw bitmask currently held by +column_name+: the loaded database value, or the one
        # carried by the flags last assigned to it (0 for nil).
        # @param column_name [Symbol]
        # @return [Integer]
        sig { params(column_name: Symbol).returns(Integer) }
        def _bitwise_raw(column_name)
          RawMask.extract(read_attribute_before_type_cast(column_name))
        end
      end
    end
  end
end
