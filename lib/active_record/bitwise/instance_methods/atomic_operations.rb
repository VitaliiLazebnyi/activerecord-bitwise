# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/instance_methods/model_access'
require 'active_record/bitwise/instance_methods/raw_cache'
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
        def _bitwise_reload_locked(column_name) # rubocop:disable Metrics/AbcSize -- main's logic, unchanged
          typecaster = _bitwise_model.attribute_types[column_name.to_s]
          plucked = _bitwise_model.where(id: id).lock(true).pluck(column_name).first
          new_raw = _bitwise_coerce_raw(typecaster.serialize(plucked))
          _bitwise_raw_cache[column_name] = new_raw
          write_attribute(column_name, typecaster.deserialize(new_raw))
          clear_attribute_changes([column_name.to_s]) if respond_to?(:clear_attribute_changes)
        end
      end
    end
  end
end
