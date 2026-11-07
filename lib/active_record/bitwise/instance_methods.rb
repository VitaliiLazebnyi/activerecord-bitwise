# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/instance_methods/atomic_operations'
require 'active_record/bitwise/instance_methods/attribute_writes'
require 'active_record/bitwise/instance_methods/column_validation'
require 'active_record/bitwise/instance_methods/flag_access'
require 'active_record/bitwise/instance_methods/raw_cache'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # Instance-level behavior shared by every model that declares a bitwise column.
    # Included exactly once per inheritance tree by the `bitwise` macro.
    module InstanceMethods
      extend T::Sig
      extend T::Helpers

      requires_ancestor { ActiveRecord::Base }

      include RawCache
      include AttributeWrites
      include AtomicOperations
      include FlagAccess

      # Validates (lazily, on first initialization) that every bitwise column is an
      # integer column whose byte limit can hold the highest mapped bit position.
      # @return [void]
      sig { void }
      def _validate_bitwise_column_type_and_bounds
        ColumnValidation.new(self.class).call
      end
    end
  end
end
