# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/instance_methods/atomic_operations'
require 'active_record/bitwise/instance_methods/attribute_writes'
require 'active_record/bitwise/instance_methods/column_validation'
require 'active_record/bitwise/instance_methods/flag_writes'
require 'active_record/bitwise/instance_methods/model_access'
require 'active_record/bitwise/instance_methods/raw_cache'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # Instance-level behavior shared by every model that declares a bitwise column.
    # Included exactly once per inheritance tree by the `bitwise` macro.
    module InstanceMethods
      extend T::Sig

      include ModelAccess
      include RawCache
      include AttributeWrites
      include AtomicOperations
      include ColumnValidation
      include FlagWrites
    end
  end
end
