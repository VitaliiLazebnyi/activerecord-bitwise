# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/layout'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # The class-level atomic `add_<column>!` / `remove_<column>!` of a column: one UPDATE that sets or clears
    # flag bits in place, so concurrent writers cannot lose each other's changes.
    class AtomicUpdate
      extend T::Sig

      # What one call updates: the records and the bits to set or clear.
      class Plan
        extend T::Sig

        # The primary keys of the records to update.
        # @return [Array<Object>]
        sig { returns(T::Array[Object]) }
        attr_reader :ids

        # @param operation [Symbol] Either :add or :remove.
        # @param column_name [Symbol, String] The database column name.
        # @param ids [Array<Object>] The primary keys of the records to update.
        # @param mask [Integer] The bits to set or clear.
        sig { params(operation: Symbol, column_name: Types::Name, ids: T::Array[Object], mask: Integer).void }
        def initialize(operation, column_name, ids, mask)
          @operation = operation
          @column_name = column_name
          @ids = ids
          @mask = mask
        end

        # The assignment for `update_all`: the SET clause with one placeholder, and the mask to bind.
        # @param adapter [ActiveRecord::ConnectionAdapters::AbstractAdapter] The database connection.
        # @return [Array<Object>]
        sig { params(adapter: ActiveRecord::ConnectionAdapters::AbstractAdapter).returns(T::Array[Object]) }
        def assignment(adapter)
          quoted = adapter.quote_column_name(@column_name)
          return ["#{quoted} = COALESCE(#{quoted}, 0) | ?", @mask] if @operation == :add

          ["#{quoted} = COALESCE(#{quoted}, 0) - (COALESCE(#{quoted}, 0) & ?)", @mask]
        end
      end

      # The primary key of +record+, or +record+ itself when it is not a record. Any object whose class has a
      # public +id+ method counts as a record.
      # @param record [Object] A record or a primary key. (Declared +T.untyped+: records are duck-typed, any
      #   object with a public +id+ qualifies, which no static type can express.)
      # @return [Object]
      sig { params(record: T.untyped).returns(Object) }
      def self.id_of(record)
        record.class.public_method_defined?(:id) ? record.id : record
      end

      # @param operation [Symbol] Either :add or :remove.
      # @param layout [ActiveRecord::Bitwise::Layout] The flags of the column.
      sig { params(operation: Symbol, layout: Layout).void }
      def initialize(operation, layout)
        @operation = operation
        @layout = layout
      end

      # What to update when adding or removing the flags in +values+ for the given records. Unknown flags
      # are ignored.
      # @param values [Array<Object>] The flags (nested arrays are flattened).
      # @param records [Object] Records, ids, or a list of either.
      # @return [ActiveRecord::Bitwise::AtomicUpdate::Plan, nil] Nil when there is nothing to do.
      sig { params(values: T::Array[Object], records: Object).returns(T.nilable(Plan)) }
      def plan(values, records)
        ids = Array(records).map { |record| self.class.id_of(record) }
        mask = @layout.mask(values.flatten)
        Plan.new(@operation, @layout.column_name, ids, mask) unless ids.empty? || mask.zero?
      end
    end
  end
end
