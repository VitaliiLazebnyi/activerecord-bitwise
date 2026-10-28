# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module Model
      # Generators of the methods defined for each bitwise column.
      module Definers
        # Defines the class-level and instance-level atomic add/remove methods.
        module AtomicMethods
          extend T::Sig

          # SQL assignment (with one bind for the mask) per operation. Unmapped bits are
          # never touched, and NULL is treated as zero.
          SQL = T.let({
            add: '%<col>s = COALESCE(%<col>s, 0) | ?',
            remove: '%<col>s = COALESCE(%<col>s, 0) - (COALESCE(%<col>s, 0) & ?)'
          }.freeze, T::Hash[Symbol, String])
          private_constant :SQL

          # One atomic operation (add or remove) on one bitwise column.
          class Operation < T::Struct
            # @return [T.any(Symbol, String)] The column name.
            const :column_name, Types::Name
            # @return [Symbol] Either :add or :remove.
            const :kind, Symbol
            # @return [T::Hash[Symbol, Integer]] Flag names to bit positions.
            const :mapping, Types::Positions
          end

          # Defines `add_<column>!` / `remove_<column>!` on the class and on instances.
          # @param model [T.untyped] The model class being configured.
          # @param column_name [T.any(Symbol, String)]
          # @param mapping [T::Hash[Symbol, Integer]]
          # @return [void]
          sig { params(model: T.untyped, column_name: Types::Name, mapping: Types::Positions).void }
          def self.define(model, column_name, mapping)
            %i[add remove].each do |kind|
              define_class_method(model, Operation.new(column_name: column_name, kind: kind, mapping: mapping))
              define_instance_methods(model, column_name, kind)
            end
          end

          # Defines the class-level method updating many records in one statement.
          # @param model [T.untyped]
          # @param operation [Operation]
          # @return [void]
          sig { params(model: T.untyped, operation: Operation).void }
          def self.define_class_method(model, operation)
            model.define_singleton_method("#{operation.kind}_#{operation.column_name}!") do |*values, records:|
              AtomicMethods.apply(self, operation, values, records)
            end
          end
          private_class_method :define_class_method

          # Defines the instance-level methods. When the column name is already singular
          # (or uncountable), only one method is defined: an alias with the same name would
          # overwrite the implementation and recurse infinitely.
          # @param model [T.untyped]
          # @param column_name [T.any(Symbol, String)]
          # @param operation [Symbol] :add or :remove.
          # @return [void]
          sig { params(model: T.untyped, column_name: Types::Name, operation: Symbol).void }
          def self.define_instance_methods(model, column_name, operation)
            column = column_name.to_sym
            implementation = "#{operation}_#{T.unsafe(column_name.to_s).singularize}!"
            model.define_method(implementation) do |*values|
              T.unsafe(self)._bitwise_atomic_update!(column, operation, values)
            end
            plural = "#{operation}_#{column_name}!"
            return if plural == implementation

            model.define_method(plural) { |*values| T.unsafe(self).send(implementation, *values) } # rubocop:disable Style/Send -- as on main
          end
          private_class_method :define_instance_methods

          # Applies +operation+ to the given records with a single UPDATE.
          # @param model [T.untyped]
          # @param operation [Operation]
          # @param values [T::Array[T.untyped]] Flag names (possibly nested).
          # @param records [T.untyped] A record, an id, or an array of either.
          # @return [T.untyped] The number of updated rows, or nil when there was nothing to do.
          sig do
            params(model: T.untyped, operation: Operation, values: T::Array[T.untyped], records: T.untyped)
              .returns(T.untyped)
          end
          def self.apply(model, operation, values, records)
            ids = Array(records).map { |record| record.respond_to?(:id) ? record.id : record }
            mask = mask_for(operation.mapping, values)
            return if ids.empty? || mask.zero?

            column = model.connection.quote_column_name(operation.column_name)
            model.where(id: ids).update_all([format(SQL.fetch(operation.kind), col: column), mask])
          end

          # ORs the bit of every mapped flag in +values+. Names are compared as strings so
          # arbitrary input is never converted to a Symbol.
          # @param mapping [T::Hash[Symbol, Integer]]
          # @param values [T::Array[T.untyped]]
          # @return [Integer]
          sig { params(mapping: Types::Positions, values: T::Array[T.untyped]).returns(Integer) }
          def self.mask_for(mapping, values)
            positions = mapping.transform_keys(&:to_s)
            values.flatten.reduce(0) do |acc, value|
              position = positions[value.to_s]
              position ? acc | (1 << position) : acc
            end
          end
          private_class_method :mask_for
        end
      end
    end
  end
end
