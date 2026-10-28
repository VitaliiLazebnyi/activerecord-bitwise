# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/instance_methods/attribute_writes'
require 'active_record/bitwise/instance_methods/raw_cache'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # Shared implementation of the instance-level atomic methods (`add_<singular>!` / `remove_<singular>!`).
      module AtomicOperations
        extend T::Sig
        extend T::Helpers

        requires_ancestor { ActiveRecord::Base }
        requires_ancestor { RawCache }

        private

        # Adds or removes flags of +column_name+ with one atomic UPDATE, then re-synchronizes the record.
        # @note The database update and read-back run inside a transaction with a
        #   row lock. If an *enclosing* transaction is later rolled back, the
        #   in-memory attribute keeps the applied value (like `update_column`);
        #   call `reload` after a rollback if you need the record re-synchronized.
        # @raise [ActiveRecord::ActiveRecordError] When called on a new (unsaved) record.
        # @param column_name [Symbol]
        # @param operation [Symbol] Either :add or :remove.
        # @param values [Array<Object>] The flags to add or remove.
        # @return [void]
        sig { params(column_name: Symbol, operation: Symbol, values: T::Array[Object]).void }
        def _bitwise_atomic_update!(column_name, operation, values)
          if new_record?
            raise ActiveRecordError,
                  "cannot atomically #{operation} #{column_name} on a new record; save the record first"
          end

          transaction { _bitwise_apply(column_name, operation, values) }
        end

        # Runs the class-level atomic UPDATE (see {Model::GeneratedMethods}) for this record and reads the
        # result back.
        # @param column_name [Symbol]
        # @param operation [Symbol] Either :add or :remove.
        # @param values [Array<Object>] The flags to add or remove.
        # @return [void]
        sig { params(column_name: Symbol, operation: Symbol, values: T::Array[Object]).void }
        def _bitwise_apply(column_name, operation, values)
          klass = self.class
          identity = id
          klass.__send__(:"_bitwise_#{operation}_#{column_name}", values, identity)
          _bitwise_store(column_name, klass.where(id: identity).lock(true).pluck(column_name).first)
        end

        # Stores +plucked+, the value just read from the database, as the record's value for +column_name+.
        # @param column_name [Symbol]
        # @param plucked [Object, nil] The column value as read (the flag array, stamped with the raw bitmask).
        # @return [void]
        sig { params(column_name: Symbol, plucked: T.nilable(Object)).void }
        def _bitwise_store(column_name, plucked)
          write_attribute(column_name, plucked)
          _bitwise_settle(column_name)
        end

        # Forgets the pending changes of +column_name+ (the value just written equals the database).
        # @param column_name [Symbol]
        # @return [void]
        sig { params(column_name: Symbol).void }
        def _bitwise_settle(column_name)
          clear_attribute_changes([column_name])
        end
      end
    end
  end
end
