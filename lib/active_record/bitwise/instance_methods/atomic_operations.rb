# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/instance_methods/model_access'
require 'active_record/bitwise/instance_methods/raw_cache'
require 'active_record/bitwise/raw_mask'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # Instance-level implementation of the atomic `add_<singular>!` / `remove_<singular>!` methods.
      module AtomicOperations
        extend T::Sig
        extend T::Helpers

        requires_ancestor { ActiveRecord::Base }
        requires_ancestor { ModelAccess }
        requires_ancestor { RawCache }

        # Shared implementation of the instance-level atomic methods
        # (`add_<singular>!` / `remove_<singular>!`).
        # @note The database update and read-back run inside a transaction with a
        #   row lock. If an *enclosing* transaction is later rolled back, the
        #   in-memory attribute keeps the applied value (like `update_column`);
        #   call `reload` after a rollback if you need the record re-synchronized.
        # @raise [ActiveRecord::ActiveRecordError] When called on a new (unsaved) record.
        # @param column_name [Symbol]
        # @param operation [Symbol] Either :add or :remove.
        # @param values [T::Array[T.untyped]]
        # @return [void]
        sig { params(column_name: Symbol, operation: Symbol, values: T::Array[T.untyped]).void }
        def _bitwise_atomic_update!(column_name, operation, values)
          if new_record?
            raise ActiveRecord::ActiveRecordError,
                  "cannot atomically #{operation} #{column_name} on a new record; save the record first"
          end

          _bitwise_model.transaction do
            _bitwise_apply_atomic(column_name, operation, values)
            _bitwise_reload_locked(column_name)
          end
        end

        # Runs the class-level atomic UPDATE for this record only.
        # @param column_name [Symbol]
        # @param operation [Symbol] Either :add or :remove.
        # @param values [T::Array[T.untyped]]
        # @return [void]
        sig { params(column_name: Symbol, operation: Symbol, values: T::Array[T.untyped]).void }
        def _bitwise_apply_atomic(column_name, operation, values)
          _bitwise_model.public_send("#{operation}_#{column_name}!", *values, records: id)
        end

        # Re-reads +column_name+ under a row lock and mirrors it into the in-memory
        # attribute without leaving the record dirty.
        # @param column_name [Symbol]
        # @return [void]
        sig { params(column_name: Symbol).void }
        def _bitwise_reload_locked(column_name)
          raw = _bitwise_locked_raw(column_name)
          _bitwise_raw_cache[column_name] = raw
          write_attribute(column_name, raw)
          clear_attribute_changes([column_name])
        end

        # Reads the persisted bitmask of +column_name+ under a row lock.
        # @param column_name [Symbol]
        # @return [Integer] The raw bitmask, 0 when the row no longer exists.
        sig { params(column_name: Symbol).returns(Integer) }
        def _bitwise_locked_raw(column_name)
          record_id = id
          flags = _bitwise_model.where(id: record_id).lock(true).pluck(column_name).first
          RawMask.mask_of(flags)
        end
      end
    end
  end
end
