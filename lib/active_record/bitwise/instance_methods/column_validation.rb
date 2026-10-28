# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # Lazy validation that every bitwise column is an integer column wide enough
      # for its mapping.
      module ColumnValidation
        extend T::Sig
        extend T::Helpers

        requires_ancestor { Kernel }

        # Highest usable bit position count (signed) per integer column byte limit.
        MAX_BITS_BY_LIMIT = T.let({ 1 => 7, 2 => 15, 4 => 31, nil => 31, 8 => 63 }.freeze,
                                  T::Hash[T.nilable(Integer), Integer])
        private_constant :MAX_BITS_BY_LIMIT

        # Fallback capacity for unexpected column limits.
        DEFAULT_MAX_BITS = 31
        private_constant :DEFAULT_MAX_BITS

        # Validates (lazily, on first initialization) that every bitwise column is an
        # integer column whose byte limit can hold the highest mapped bit position.
        # @return [void]
        sig { void }
        def _validate_bitwise_column_type_and_bounds
          return if _bitwise_columns_validated?

          results = _bitwise_definitions.map { |column, config| _bitwise_validate_definition(column, config) }
          return unless results.all? && !_bitwise_definitions.empty?

          T.unsafe(self).class.instance_variable_set(:@_bitwise_columns_validated, true)
        end

        # The bitwise definitions of the model class.
        # @return [T::Hash[Symbol, T::Hash[Symbol, T.untyped]]]
        sig { returns(T::Hash[Symbol, T::Hash[Symbol, T.untyped]]) }
        def _bitwise_definitions
          T.unsafe(self).class.bitwise_definitions
        end

        # Whether the class-level flag and every definition already record a successful check.
        # @return [Boolean]
        sig { returns(T::Boolean) }
        def _bitwise_columns_validated?
          return false unless T.unsafe(self).class.instance_variable_get(:@_bitwise_columns_validated) == true

          _bitwise_definitions.values.all? { |config| config.fetch(:validated) }
        end

        # Validates a single definition once. Configuration errors (ArgumentError) are
        # re-raised; any other failure (e.g. database unavailable) is tolerated and
        # reported so validation is retried on the next initialization.
        # @param column [Symbol]
        # @param config [T::Hash[Symbol, T.untyped]]
        # @raise [ArgumentError] When the column cannot hold the mapping.
        # @return [Boolean] False when the check could not be completed.
        sig { params(column: Symbol, config: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
        def _bitwise_validate_definition(column, config)
          _bitwise_check_definition(column, config) unless config.fetch(:validated)
          true
        rescue StandardError => e
          raise if e.is_a?(ArgumentError)

          false
        end

        # Checks one definition against the database schema (when reachable).
        # @param column [Symbol]
        # @param config [T::Hash[Symbol, T.untyped]]
        # @raise [ArgumentError] When the column is not an integer column or is too narrow.
        # @return [void]
        sig { params(column: Symbol, config: T::Hash[Symbol, T.untyped]).void }
        def _bitwise_check_definition(column, config)
          klass = T.unsafe(self).class
          return unless klass.connection.active? && klass.table_exists?

          db_column = ColumnValidation.integer_column(klass, column)
          ColumnValidation.check_capacity(column, db_column.limit, config.fetch(:mapping).values.max || 0)
          config[:validated] = true
        end

        # The database column backing +column+, which must be an integer column.
        # @param klass [T.untyped] The model class.
        # @param column [Symbol]
        # @raise [ArgumentError] When the column is missing or not an integer column.
        # @return [T.untyped] The column definition.
        sig { params(klass: T.untyped, column: Symbol).returns(T.untyped) }
        def self.integer_column(klass, column)
          db_column = klass.columns_hash[column.to_s]
          return db_column if db_column&.type == :integer

          raise ArgumentError, "Bitwise column #{column} must be an integer database column"
        end

        # Verifies the highest bit position fits the column's byte limit.
        # @param column [Symbol]
        # @param limit [T.nilable(Integer)] The column's byte limit.
        # @param position [Integer] The highest mapped bit position.
        # @raise [ArgumentError] When the position does not fit.
        # @return [void]
        sig { params(column: Symbol, limit: T.nilable(Integer), position: Integer).void }
        def self.check_capacity(column, limit, position)
          max_bits = MAX_BITS_BY_LIMIT.fetch(limit, DEFAULT_MAX_BITS)
          return if position < max_bits

          raise ArgumentError,
                "Bitwise column #{column} has limit of #{limit || 4} bytes (max #{max_bits} flags), " \
                "but mapping requires bit shift position #{position}."
        end
      end
    end
  end
end
