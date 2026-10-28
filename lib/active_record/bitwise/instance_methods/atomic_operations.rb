# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/raw_mask'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # Instance-level implementation of the atomic `add_<singular>!` / `remove_<singular>!` methods.
      module AtomicOperations
        extend T::Sig
        extend T::Helpers

        requires_ancestor { Kernel }

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
          if T.unsafe(self).new_record?
            raise ActiveRecord::ActiveRecordError,
                  "cannot atomically #{operation} #{column_name} on a new record; save the record first"
          end

          T.unsafe(self).class.transaction do
            T.unsafe(self).class.public_send("#{operation}_#{column_name}!", *values, records: T.unsafe(self).id)
            _bitwise_reload_locked(column_name)
          end
        end

        # Re-reads +column_name+ under a row lock and mirrors it into the in-memory
        # attribute without leaving the record dirty.
        # @param column_name [Symbol]
        # @return [void]
        sig { params(column_name: Symbol).void }
        def _bitwise_reload_locked(column_name)
          record = T.unsafe(self)
          typecaster = record.class.attribute_types.fetch(column_name.to_s)
          raw = _bitwise_locked_raw(column_name, typecaster)
          record._bitwise_raw_cache[column_name] = raw
          record.write_attribute(column_name, typecaster.deserialize(raw))
          record.clear_attribute_changes([column_name.to_s]) if record.respond_to?(:clear_attribute_changes)
        end

        # Reads the persisted bitmask of +column_name+ under a row lock.
        # @param column_name [Symbol]
        # @param typecaster [ActiveRecord::Bitwise::Type]
        # @return [Integer]
        sig { params(column_name: Symbol, typecaster: ActiveRecord::Bitwise::Type).returns(Integer) }
        def _bitwise_locked_raw(column_name, typecaster)
          record = T.unsafe(self)
          current = record.class.where(id: record.id).lock(true).pluck(column_name).first
          RawMask.coerce(typecaster.serialize(current))
        end
      end
    end
  end
end
