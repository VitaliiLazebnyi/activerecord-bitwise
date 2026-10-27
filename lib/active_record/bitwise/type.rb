# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/constants'
require 'active_record/bitwise/errors'
require 'active_record/bitwise/raw_mask'
require 'active_record/bitwise/recursion_guard'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # ActiveModel attribute type translating between an Array of flag names and the
    # integer bitmask stored in the database.
    class Type < ActiveRecord::Type::Value
      extend T::Sig

      # The column name associated with this type.
      # @return [Symbol]
      sig { returns(Symbol) }
      attr_reader :column_name

      # The mapping of symbol keys to bit position integers.
      # @return [T::Hash[Symbol, Integer]]
      sig { returns(Types::Positions) }
      attr_reader :mapping

      # The default array of values (applied to new records via the attribute API).
      # @return [T::Array[T.any(Symbol, String)]]
      sig { returns(Types::Flags) }
      attr_reader :default

      # The bitmask representing all known mapped positions.
      # @return [Integer]
      sig { returns(Integer) }
      attr_reader :known_mask

      # The list of mapping keys converted to strings for Symbol DoS prevention.
      # @return [T::Array[String]]
      sig { returns(T::Array[String]) }
      attr_reader :mapping_strings

      # Initializes the bitwise type cast configuration.
      # @param column_name [T.any(Symbol, String)] The column name.
      # @param mapping [T::Hash[Symbol, Integer]] The mapping of keys to bit positions.
      # @param default [T.nilable(T::Array[T.any(Symbol, String)])] The default values.
      # @return [void]
      sig do
        params(column_name: Types::Name, mapping: Types::Positions,
               default: T.nilable(Types::Flags)).void
      end
      def initialize(column_name, mapping, default)
        @column_name = T.let(column_name.to_sym, Symbol)
        @mapping = mapping
        @default = T.let(Array(default), Types::Flags)
        @known_mask = T.let(RawMask.known_mask(mapping), Integer)
        @mapping_strings = T.let(RawMask.names(mapping), T::Array[String])
        @empty_value = T.let(RawMask.empty, Types::Flags)
        super()
      end

      # Casts a value to a frozen array of symbols or strings.
      # @param value [T.untyped] The value to cast.
      # @raise [ArgumentError] When the value cannot be meaningfully cast (Hash, true, false)
      #   or exceeds {MAX_ARRAY_SIZE} elements.
      # @return [T.nilable(T::Array[T.any(Symbol, String)])] The casted array or nil.
      sig { override.params(value: T.untyped).returns(T.nilable(Types::Flags)) }
      def cast(value)
        return nil if value.nil?
        return deserialize(value) if value.is_a?(Integer)
        return value if value.is_a?(Array) && value.frozen? && RawMask.stamped?(value)

        assert_castable(value)
        return deserialize(RawMask.integer(value)) if bitmask_string?(value)

        build_flags(value)
      end

      # Deserializes a database integer value into an array of symbols or strings.
      # A database NULL deserializes to an empty array; the configured default is
      # applied only to new records (via the attribute API), never resurrected for
      # persisted NULL rows, so getters, scopes, and persistence stay consistent.
      # @param value [T.untyped] The raw value from the database.
      # @return [T::Array[T.any(Symbol, String)]] The array of symbols/strings represented by the bitmask.
      sig { override.params(value: T.untyped).returns(Types::Flags) }
      def deserialize(value)
        RecursionGuard.run do
          next @empty_value if value.nil?

          value.is_a?(Array) ? restamp(value) : flags_for_mask(RawMask.integer(value))
        end
      end

      # Serializes an array of symbols into a database integer bitmask, merging
      # any unmapped ("forgotten") bits carried on the array's raw-value marker.
      # @param value [T.untyped] The value to serialize.
      # @return [T.nilable(Integer)] The resulting integer bitmask.
      sig { override.params(value: T.untyped).returns(T.nilable(Integer)) }
      def serialize(value)
        return nil if value.nil?
        return value if value.is_a?(Integer)

        (RawMask.mask_of(value) & ~@known_mask) | mask_for(Array(value))
      end

      private

      # Rejects values that cannot be meaningfully cast to a flag array.
      # @param value [T.untyped]
      # @raise [ArgumentError] For a Hash, +true+ or +false+.
      # @return [void]
      sig { params(value: T.untyped).void }
      def assert_castable(value)
        return unless value.is_a?(Hash) || value == true || value == false

        raise ArgumentError, "cannot cast #{value.inspect} to a bitwise flag array for column #{column_name}"
      end

      # A bare numeric string (e.g. from a raw SQLite read) is a bitmask, not a flag name.
      # @param value [T.untyped]
      # @return [Boolean]
      sig { params(value: T.untyped).returns(T::Boolean) }
      def bitmask_string?(value)
        return false unless value.is_a?(String)

        !@mapping_strings.include?(value) && value.match?(/\A\d+\z/)
      end

      # Builds the frozen flag array for a list-like +value+, carrying over a raw marker.
      # @param value [T.untyped]
      # @raise [ArgumentError] When the list exceeds {MAX_ARRAY_SIZE} elements.
      # @return [T::Array[T.any(Symbol, String)]]
      sig { params(value: T.untyped).returns(Types::Flags) }
      def build_flags(value)
        items = Array(value).reject { |item| item.nil? || item == '' }
        raise ArgumentError, "Array size cannot exceed #{MAX_ARRAY_SIZE}" if items.size > MAX_ARRAY_SIZE

        flags = items.uniq(&:to_s)
        flags.map! { |item| symbolize(item) }
        RawMask.stamp(flags, RawMask.read(value)) if RawMask.stamped?(value)
        flags.freeze
      end

      # Mapped names become Symbols; everything else stays a String.
      # @param item [T.untyped]
      # @return [T.any(Symbol, String)]
      sig { params(item: T.untyped).returns(Types::Name) }
      def symbolize(item)
        name = item.to_s
        @mapping_strings.include?(name) ? name.to_sym : name
      end

      # Re-wraps an Array input as a frozen flag array stamped with its raw mask.
      # @param value [T::Array[T.untyped]]
      # @return [T::Array[T.any(Symbol, String)]]
      sig { params(value: T::Array[T.untyped]).returns(Types::Flags) }
      def restamp(value)
        raw = RawMask.stamped?(value) ? RawMask.read(value) : serialize(value)
        RawMask.stamp(T.must(cast(value)).dup, raw).freeze
      end

      # The flags whose bits are set in +raw+, stamped with +raw+.
      # @param raw [Integer]
      # @return [T::Array[T.any(Symbol, String)]]
      sig { params(raw: Integer).returns(Types::Flags) }
      def flags_for_mask(raw)
        flags = @mapping.select { |_name, position| raw.anybits?(1 << position) }.keys
        RawMask.stamp(flags, raw).freeze
      end

      # ORs the bit of every mapped flag in +values+.
      # @param values [T::Array[T.untyped]]
      # @return [Integer]
      sig { params(values: T::Array[T.untyped]).returns(Integer) }
      def mask_for(values)
        values.reduce(0) do |mask, value|
          name = value.to_s
          @mapping_strings.include?(name) ? mask | (1 << T.must(@mapping[name.to_sym])) : mask
        end
      end
    end
  end
end
