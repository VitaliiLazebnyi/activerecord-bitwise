# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/declaration'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # Validates (lazily, on first initialization) that every bitwise column is an integer column whose
      # byte limit can hold the highest mapped bit position.
      class ColumnValidation
        extend T::Sig

        # Name of the class-level instance variable that remembers a completed validation.
        MEMO = :@_bitwise_columns_validated
        private_constant :MEMO

        # The number of usable flags (signed bits) per byte limit of the column; anything else holds 31.
        CAPACITY = T.let({ 1 => 7, 2 => 15, 3 => 23, 4 => 31, 8 => 63 }.freeze, T::Hash[Integer, Integer])
        private_constant :CAPACITY

        # The capacity of a column that reports no byte limit or an unusual one.
        DEFAULT_CAPACITY = 31
        private_constant :DEFAULT_CAPACITY

        # @param model [Class] The model class that declared the bitwise columns.
        sig { params(model: Types::ModelClass).void }
        def initialize(model)
          @model = model
        end

        # Validates the columns that are not validated yet. Columns of a missing table or a connection that
        # is not usable stay unvalidated and are checked again on the next call.
        # @raise [ArgumentError] When a column is not an integer column or too small for its mapping.
        # @return [void]
        sig { void }
        def call
          return if memoized?

          outcomes = unvalidated.map { |column, config| check(column, config) }
          @model.instance_variable_set(MEMO, true) if outcomes.all? && definitions.present?
        end

        private

        # The bitwise definitions of the model.
        # @return [Hash{Symbol => Hash}]
        sig { returns(T::Hash[Symbol, Declaration::Definition]) }
        def definitions
          @model.bitwise_definitions
        end

        # The definitions of the columns that are not validated yet.
        # @return [Hash{Symbol => Hash}]
        sig { returns(T::Hash[Symbol, Declaration::Definition]) }
        def unvalidated
          definitions.reject { |_column, config| config[:validated] }
        end

        # Whether an earlier call validated every column of the model.
        # @return [Boolean]
        sig { returns(T::Boolean) }
        def memoized?
          return false unless @model.instance_variable_get(MEMO)

          definitions.values.all? { |config| config[:validated] }
        end

        # Validates one column.
        # @param column [Symbol]
        # @param config [Hash] The definition of the column.
        # @raise [ArgumentError] When the column does not fit its mapping.
        # @return [Boolean] False when the database could not be inspected.
        sig { params(column: Symbol, config: Declaration::Definition).returns(T::Boolean) }
        def check(column, config)
          verify(column, config)
          true
        rescue ArgumentError
          raise
        rescue StandardError
          false
        end

        # Verifies the database column behind +column+ and flags it as validated.
        # @param column [Symbol]
        # @param config [Hash] The definition of the column.
        # @return [void]
        sig { params(column: Symbol, config: Declaration::Definition).void }
        def verify(column, config)
          return unless @model.connection.active? && @model.table_exists?

          database_column = @model.columns_hash[column.to_s]
          unless database_column&.type == :integer
            raise ArgumentError, "Bitwise column #{column} must be an integer database column"
          end

          verify_fit(column, config[:mapping].values.max || 0, database_column.limit || 4)
          config[:validated] = true
        end

        # @param column [Symbol]
        # @param position [Integer] The highest bit position of the mapping.
        # @param bytes [Integer] The byte limit of the database column (4 when it reports none).
        # @raise [ArgumentError] When +position+ does not fit.
        # @return [void]
        sig { params(column: Symbol, position: Integer, bytes: Integer).void }
        def verify_fit(column, position, bytes)
          capacity = CAPACITY.fetch(bytes, DEFAULT_CAPACITY)
          return if position < capacity

          raise ArgumentError, "Bitwise column #{column} has limit of #{bytes} bytes (max #{capacity} flags), " \
                               "but mapping requires bit shift position #{position}."
        end
      end
    end
  end
end
